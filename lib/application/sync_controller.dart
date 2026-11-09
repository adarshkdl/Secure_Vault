import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart' show FirebaseAuthException;
import 'package:firebase_core/firebase_core.dart' show FirebaseException;
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/crypto/vault_crypto.dart';
import '../data/sync/firestore_remote.dart';
import '../data/sync/sync_auth.dart';
import '../data/sync/sync_engine.dart';
import '../data/sync/sync_models.dart';
import '../data/sync/sync_state_prefs.dart';
import '../data/vault_repository.dart';
import 'providers.dart';

enum SyncPhase {
  /// Firebase is not configured in this build (no google-services.json).
  unavailable,
  signedOut,

  /// Signed in; looking at what the cloud account already holds.
  checking,

  /// Signed in, the account has no cloud vault yet.
  needsSetup,

  /// The account already has a cloud vault protected by another key.
  needsJoin,
  ready,
  syncing,
  error,
}

class SyncUiState {
  const SyncUiState({
    required this.phase,
    this.email,
    this.lastSync,
    this.lastReport,
    this.message,
  });
  final SyncPhase phase;
  final String? email;
  final DateTime? lastSync;
  final SyncReport? lastReport;
  final String? message;

  SyncUiState copyWith({
    SyncPhase? phase,
    String? email,
    DateTime? lastSync,
    SyncReport? lastReport,
    String? message,
    bool clearMessage = false,
  }) => SyncUiState(
    phase: phase ?? this.phase,
    email: email ?? this.email,
    lastSync: lastSync ?? this.lastSync,
    lastReport: lastReport ?? this.lastReport,
    message: clearMessage ? null : (message ?? this.message),
  );
}

/// Set to true in main() once Firebase initialised from the platform config.
final firebaseReadyProvider = Provider<bool>((_) => false);

final syncAuthProvider = Provider<SyncAuth?>(
  (ref) => ref.watch(firebaseReadyProvider) ? FirebaseSyncAuth() : null,
);

final syncRemoteFactoryProvider = Provider<SyncRemote Function(String uid)>(
  (_) =>
      (uid) => FirestoreSyncRemote(uid),
);

final syncStoreProvider = Provider(
  (ref) => PrefsSyncStateStore(ref.watch(sharedPrefsProvider)),
);

class SyncController extends Notifier<SyncUiState> {
  Timer? _debounce;
  bool _busy = false;
  bool _selfChange = false;

  SyncAuth? get _auth => ref.read(syncAuthProvider);
  PrefsSyncStateStore get _store => ref.read(syncStoreProvider);
  VaultController get _vault => ref.read(vaultProvider.notifier);

  @override
  SyncUiState build() {
    ref.onDispose(() => _debounce?.cancel());
    ref.listen(vaultProvider, _onVault);
    final auth = _auth;
    if (auth == null) return const SyncUiState(phase: SyncPhase.unavailable);
    final u = auth.currentUser;
    if (u == null) return const SyncUiState(phase: SyncPhase.signedOut);
    return SyncUiState(
      phase: _store.enabledUid == u.uid ? SyncPhase.ready : SyncPhase.checking,
      email: u.email,
    );
  }

  bool get _enabled {
    final u = _auth?.currentUser;
    return u != null && _store.enabledUid == u.uid;
  }

  void _onVault(VaultState? prev, VaultState next) {
    if (!_enabled || next.status != VaultStatus.unlocked) return;
    if (prev?.status != VaultStatus.unlocked) {
      _schedule(const Duration(seconds: 1)); // just unlocked
    } else if (!_selfChange && next.revision != prev?.revision) {
      _schedule(const Duration(seconds: 3)); // local edit: batch changes
    }
  }

  void _schedule(Duration d) {
    _debounce?.cancel();
    _debounce = Timer(d, syncNow);
  }

  SyncRemote _remote(String uid) => ref.read(syncRemoteFactoryProvider)(uid);

  String _describe(Object e) {
    if (e is FirebaseAuthException) {
      return 'Sign-in failed (${e.code}).';
    }
    if (e is FirebaseException) {
      return 'Cloud request failed (${e.code}). Check your connection and the Firestore rules.';
    }
    return 'Something went wrong. Nothing was changed.';
  }

  // -- Sign in / link --------------------------------------------------------

  Future<void> signIn() async {
    final auth = _auth;
    if (auth == null) return;
    state = state.copyWith(phase: SyncPhase.checking, clearMessage: true);
    try {
      final u = await auth.signInWithGoogle();
      state = state.copyWith(email: u.email);
    } on FirebaseAuthException catch (e) {
      final cancelled = e.code.contains('cancel');
      state = SyncUiState(
        phase: SyncPhase.signedOut,
        message: cancelled ? null : _describe(e),
      );
      return;
    } catch (e) {
      state = SyncUiState(phase: SyncPhase.signedOut, message: _describe(e));
      return;
    }
    await checkCloud();
  }

  /// Looks at what the signed-in account already holds and decides the next
  /// step: link directly, create a cloud vault, or join an existing one.
  Future<void> checkCloud() async {
    final u = _auth?.currentUser;
    final keys = _vault.syncKeys();
    if (u == null || keys == null) return;
    state = state.copyWith(phase: SyncPhase.checking, clearMessage: true);
    try {
      final header = await _remote(u.uid).getHeader();
      if (header == null) {
        state = state.copyWith(phase: SyncPhase.needsSetup);
      } else if (header.sameKeyAs(keys.kdf, keys.wrapped)) {
        await _enable(u.uid);
        await syncNow();
      } else {
        state = state.copyWith(phase: SyncPhase.needsJoin);
      }
    } catch (e) {
      state = state.copyWith(phase: SyncPhase.error, message: _describe(e));
    }
  }

  Future<void> _enable(String uid) async {
    await _store.setEnabledUid(uid);
    state = state.copyWith(phase: SyncPhase.ready, clearMessage: true);
  }

  /// First device: uploads the key header and all records, encrypted. Returns
  /// an error message, or null on success.
  Future<String?> createCloudVault(String masterPassword) async {
    final u = _auth?.currentUser;
    if (u == null) return 'Sign in first.';
    state = state.copyWith(phase: SyncPhase.checking, clearMessage: true);
    try {
      if (!await _vault.strengthenKdfForCloud(masterPassword)) {
        state = state.copyWith(phase: SyncPhase.needsSetup);
        return 'Wrong master password.';
      }
      final keys = _vault.syncKeys()!;
      await _remote(
        u.uid,
      ).putHeader(RemoteHeader(kdf: keys.kdf, wrapped: keys.wrapped, rev: 1));
      await _store.clear(u.uid);
      await _enable(u.uid);
      await syncNow();
      return null;
    } catch (e) {
      state = state.copyWith(
        phase: SyncPhase.needsSetup,
        message: _describe(e),
      );
      return _describe(e);
    }
  }

  /// Another device: unlocks the cloud vault with the master password it was
  /// created with, then merges this device's records into it. This device then
  /// uses the cloud vault's master password. Returns an error message or null.
  Future<String?> joinCloudVault(String cloudPassword) async {
    final u = _auth?.currentUser;
    final keys = _vault.syncKeys();
    final data = ref.read(vaultProvider).data;
    if (u == null || keys == null || data == null) return 'Sign in first.';
    state = state.copyWith(phase: SyncPhase.checking, clearMessage: true);
    try {
      final remote = _remote(u.uid);
      final header = await remote.getHeader();
      if (header == null) {
        state = state.copyWith(phase: SyncPhase.needsSetup);
        return 'No cloud vault found.';
      }
      if (!header.kdf.withinSafeLimits) {
        state = state.copyWith(phase: SyncPhase.needsJoin);
        return 'The cloud vault header is not valid.';
      }
      final List<int> dek;
      try {
        dek = await VaultRepository.unwrapDek(
          cloudPassword,
          header.kdf,
          header.wrapped,
        );
      } on DecryptionFailure {
        state = state.copyWith(phase: SyncPhase.needsJoin);
        return 'Wrong master password for the cloud vault.';
      }
      if (listEquals(dek, keys.dek)) {
        // Same data key already (e.g. password changed on another device).
        VaultCrypto.wipe(dek);
        await _enable(u.uid);
        await syncNow();
        return null;
      }
      await _store.clear(u.uid);
      final engine = SyncEngine(remote: remote, store: _store, uid: u.uid);
      final run = await engine.run(data, dek);
      _selfChange = true;
      try {
        await _vault.adoptCloudKey(
          dek: dek,
          kdf: header.kdf,
          wrapped: header.wrapped,
          merged: run.merged,
        );
      } finally {
        _selfChange = false;
      }
      await run.commit();
      await _enable(u.uid);
      state = state.copyWith(lastSync: run.report.at, lastReport: run.report);
      return null;
    } catch (e) {
      state = state.copyWith(phase: SyncPhase.needsJoin, message: _describe(e));
      return _describe(e);
    }
  }

  // -- Syncing ---------------------------------------------------------------

  Future<void> syncNow() async {
    _debounce?.cancel();
    final u = _auth?.currentUser;
    if (u == null || !_enabled || _busy) return;
    final keys = _vault.syncKeys();
    final vs = ref.read(vaultProvider);
    final data = vs.data;
    if (keys == null || data == null) return; // locked: no key, no sync
    _busy = true;
    final revisionAtStart = vs.revision;
    state = state.copyWith(phase: SyncPhase.syncing, clearMessage: true);
    try {
      final engine = SyncEngine(
        remote: _remote(u.uid),
        store: _store,
        uid: u.uid,
      );
      final run = await engine.run(data, keys.dek);
      if (ref.read(vaultProvider).revision != revisionAtStart) {
        // The vault changed while syncing: do not overwrite it with an older
        // merge. Nothing is committed, so the next pass redoes it.
        state = state.copyWith(phase: SyncPhase.ready);
        _schedule(const Duration(seconds: 2));
        return;
      }
      if (run.changed) {
        _selfChange = true;
        try {
          await _vault.applySyncedData(run.merged);
        } finally {
          _selfChange = false;
        }
      }
      await run.commit();
      final bad = run.report.rejected;
      state = state.copyWith(
        phase: SyncPhase.ready,
        lastSync: run.report.at,
        lastReport: run.report,
        message: bad > 0
            ? '$bad cloud item(s) failed verification and were skipped.'
            : null,
        clearMessage: bad == 0,
      );
    } catch (e) {
      state = state.copyWith(phase: SyncPhase.error, message: _describe(e));
    } finally {
      _busy = false;
    }
  }

  /// Publishes the new master-password wrapper so new devices can join with
  /// the new password. Other already-linked devices keep their own password.
  Future<void> onPasswordChanged() async {
    final u = _auth?.currentUser;
    final keys = _vault.syncKeys();
    if (u == null || keys == null || !_enabled) return;
    try {
      final remote = _remote(u.uid);
      final old = await remote.getHeader();
      await remote.putHeader(
        RemoteHeader(
          kdf: keys.kdf,
          wrapped: keys.wrapped,
          rev: (old?.rev ?? 0) + 1,
        ),
      );
    } catch (e) {
      state = state.copyWith(
        message:
            'Password changed here, but the cloud copy could not be updated. '
            'Open Cloud sync and sync again.',
      );
    }
  }

  /// Stops syncing on this device and signs out. With [deleteCloud] the
  /// encrypted cloud copy is erased too (other devices keep their local data).
  Future<String?> disable({bool deleteCloud = false}) async {
    final u = _auth?.currentUser;
    try {
      if (u != null && deleteCloud) await _remote(u.uid).deleteEverything();
      if (u != null) await _store.clear(u.uid);
      await _store.setEnabledUid(null);
      await _auth?.signOut();
      state = const SyncUiState(phase: SyncPhase.signedOut);
      return null;
    } catch (e) {
      state = state.copyWith(message: _describe(e));
      return _describe(e);
    }
  }
}

final syncControllerProvider = NotifierProvider<SyncController, SyncUiState>(
  SyncController.new,
);
