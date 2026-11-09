import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../core/clipboard_service.dart';
import '../core/crypto/vault_crypto.dart';
import '../core/lockout.dart';
import '../core/password_tools.dart';
import '../data/settings_store.dart';
import '../data/vault_repository.dart';
import '../domain/category.dart';
import '../domain/credential.dart';
import '../domain/field_def.dart';
import '../domain/vault_data.dart';

// ---- Infrastructure (overridden in main / tests) ---------------------------

final sharedPrefsProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('override in main'),
);
final vaultDirProvider = Provider<Directory>(
  (ref) => throw UnimplementedError('override in main'),
);

final settingsStoreProvider = Provider(
  (ref) => SettingsStore(ref.watch(sharedPrefsProvider)),
);
final repositoryProvider = Provider(
  (ref) => VaultRepository(ref.watch(vaultDirProvider)),
);
final clipboardProvider = Provider((ref) => ClipboardService());
final localAuthProvider = Provider((ref) => LocalAuthentication());
final secureStorageProvider = Provider(
  (ref) => const FlutterSecureStorage(
    iOptions: IOSOptions(accessibility: KeychainAccessibility.passcode),
  ),
);

const _bioKeyName = 'sv_bio_dek';
const _uuid = Uuid();
String newId() => _uuid.v4();

// ---- Settings --------------------------------------------------------------

class SettingsController extends Notifier<AppSettings> {
  @override
  AppSettings build() => ref.read(settingsStoreProvider).load();

  Future<void> update(AppSettings s) async {
    state = s;
    await ref.read(settingsStoreProvider).save(s);
  }
}

final settingsProvider = NotifierProvider<SettingsController, AppSettings>(
  SettingsController.new,
);

// ---- Vault -----------------------------------------------------------------

enum VaultStatus { loading, noVault, locked, unlocked }

enum UnlockResult { ok, wrongPassword, lockedOut, error }

@immutable
class VaultState {
  const VaultState({
    this.status = VaultStatus.loading,
    this.data,
    this.revision = 0,
    this.lockedUntil,
    this.failedAttempts = 0,
  });

  final VaultStatus status;
  final VaultData? data;

  /// Bumped on every mutation so listeners rebuild.
  final int revision;
  final DateTime? lockedUntil;
  final int failedAttempts;

  VaultState copyWith({
    VaultStatus? status,
    VaultData? data,
    bool clearData = false,
    int? revision,
    DateTime? lockedUntil,
    bool clearLock = false,
    int? failedAttempts,
  }) => VaultState(
    status: status ?? this.status,
    data: clearData ? null : (data ?? this.data),
    revision: revision ?? this.revision,
    lockedUntil: clearLock ? null : (lockedUntil ?? this.lockedUntil),
    failedAttempts: failedAttempts ?? this.failedAttempts,
  );
}

class VaultController extends Notifier<VaultState> {
  VaultSession? _session;
  static const _policy = LockoutPolicy();
  static const recentlyDeletedRetention = Duration(days: 30);

  VaultRepository get _repo => ref.read(repositoryProvider);
  SettingsStore get _store => ref.read(settingsStoreProvider);

  @override
  VaultState build() => const VaultState();

  VaultData get _data => state.data!;

  Future<void> init() async {
    final exists = await _repo.exists();
    state = VaultState(
      status: exists ? VaultStatus.locked : VaultStatus.noVault,
      failedAttempts: _store.failedAttempts,
      lockedUntil: _store.lockedUntil,
    );
  }

  void _unlocked(VaultSession s, VaultData d) {
    _session = s;
    // Auto-purge items past the Recently Deleted retention window.
    final cutoff = DateTime.now().subtract(recentlyDeletedRetention);
    d.credentials.removeWhere(
      (c) => c.deletedAt != null && c.deletedAt!.isBefore(cutoff),
    );
    state = VaultState(
      status: VaultStatus.unlocked,
      data: d,
      revision: state.revision + 1,
    );
  }

  Future<void> createVault(String password) async {
    final (s, d) = await _repo.create(password);
    await _store.saveAttempts(0, null);
    _unlocked(s, d);
  }

  Duration? lockoutRemaining() =>
      _policy.remaining(state.lockedUntil, DateTime.now());

  Future<UnlockResult> unlock(String password) async {
    if (lockoutRemaining() != null) return UnlockResult.lockedOut;
    try {
      final (s, d) = await _repo.unlock(password);
      await _store.saveAttempts(0, null);
      _unlocked(s, d);
      return UnlockResult.ok;
    } on DecryptionFailure {
      final n = state.failedAttempts + 1;
      final delay = _policy.delayFor(n);
      final until = delay == Duration.zero ? null : DateTime.now().add(delay);
      await _store.saveAttempts(n, until);
      state = state.copyWith(
        failedAttempts: n,
        lockedUntil: until,
        clearLock: until == null,
      );
      return UnlockResult.wrongPassword;
    } catch (_) {
      return UnlockResult.error;
    }
  }

  // -- Biometrics: the data key is released from Keystore/Keychain only after
  // the OS biometric prompt succeeds. The master password remains the root of
  // trust and is required to enable/disable and after any password change.

  Future<bool> biometricsAvailable() async {
    try {
      final auth = ref.read(localAuthProvider);
      return await auth.canCheckBiometrics && await auth.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  Future<bool> _promptBiometric(String reason) async {
    try {
      return await ref
          .read(localAuthProvider)
          .authenticate(localizedReason: reason, biometricOnly: true);
    } catch (_) {
      return false;
    }
  }

  Future<bool> enableBiometric() async {
    if (_session == null || !await biometricsAvailable()) return false;
    if (!await _promptBiometric('Enable biometric unlock')) return false;
    await ref
        .read(secureStorageProvider)
        .write(key: _bioKeyName, value: base64Encode(_session!.dek));
    final s = ref.read(settingsProvider);
    await ref
        .read(settingsProvider.notifier)
        .update(s.copyWith(biometricEnabled: true));
    return true;
  }

  Future<void> disableBiometric() async {
    await ref.read(secureStorageProvider).delete(key: _bioKeyName);
    final s = ref.read(settingsProvider);
    await ref
        .read(settingsProvider.notifier)
        .update(s.copyWith(biometricEnabled: false));
  }

  Future<UnlockResult> unlockWithBiometric() async {
    if (!ref.read(settingsProvider).biometricEnabled) return UnlockResult.error;
    if (!await _promptBiometric('Unlock your vault')) return UnlockResult.error;
    try {
      final stored = await ref
          .read(secureStorageProvider)
          .read(key: _bioKeyName);
      if (stored == null) return UnlockResult.error;
      final (s, d) = await _repo.unlockWithKey(base64Decode(stored));
      _unlocked(s, d);
      return UnlockResult.ok;
    } catch (_) {
      // Key invalidated or vault replaced: fall back to the master password.
      await disableBiometric();
      return UnlockResult.error;
    }
  }

  /// Confirms identity for sensitive actions.
  Future<bool> verifyMasterPassword(String password) =>
      _repo.verifyPassword(password);

  Future<bool> verifyBiometric() => _promptBiometric('Confirm it is you');

  void lock() {
    _session?.wipe();
    _session = null;
    ref.read(clipboardProvider).flush();
    state = VaultState(
      status: VaultStatus.locked,
      revision: state.revision + 1,
      failedAttempts: state.failedAttempts,
      lockedUntil: state.lockedUntil,
    );
  }

  Future<void> _persist() async {
    await _repo.save(_session!, _data);
    state = state.copyWith(revision: state.revision + 1);
  }

  // -- Credentials ----------------------------------------------------------

  Future<void> saveCredential(Credential c) async {
    final list = _data.credentials;
    final i = list.indexWhere((x) => x.id == c.id);
    if (i >= 0) {
      list[i] = c;
    } else {
      list.add(c);
    }
    await _persist();
  }

  /// Adds many records with a single encrypted write. All-or-nothing: if the
  /// save fails the in-memory vault is left as it was.
  Future<void> addCredentials(List<Credential> items) async {
    final before = List.of(_data.credentials);
    _data.credentials.addAll(items);
    try {
      await _persist();
    } catch (_) {
      _data.credentials
        ..clear()
        ..addAll(before);
      rethrow;
    }
  }

  Future<void> toggleFavorite(String id) async {
    final i = _data.credentials.indexWhere((c) => c.id == id);
    if (i < 0) return;
    final c = _data.credentials[i];
    _data.credentials[i] = c.copyWith(isFavorite: !c.isFavorite);
    await _persist();
  }

  Future<void> markAccessed(String id) async {
    final i = _data.credentials.indexWhere((c) => c.id == id);
    if (i < 0) return;
    _data.credentials[i] = _data.credentials[i].copyWith(
      lastAccessedAt: DateTime.now(),
    );
    await _persist();
  }

  Future<void> softDelete(String id) async {
    final i = _data.credentials.indexWhere((c) => c.id == id);
    if (i < 0) return;
    _data.credentials[i] = _data.credentials[i].copyWith(
      deletedAt: DateTime.now(),
    );
    await _persist();
  }

  Future<void> restore(String id) async {
    final i = _data.credentials.indexWhere((c) => c.id == id);
    if (i < 0) return;
    _data.credentials[i] = _data.credentials[i].copyWith(clearDeleted: true);
    await _persist();
  }

  Future<void> deleteForever(String id) async {
    _data.credentials.removeWhere((c) => c.id == id);
    await _persist();
  }

  Future<void> emptyTrash() async {
    _data.credentials.removeWhere((c) => c.isDeleted);
    await _persist();
  }

  // -- Categories -----------------------------------------------------------

  Future<void> saveCategory(Category c) async {
    final list = _data.customCategories;
    final i = list.indexWhere((x) => x.id == c.id);
    if (i >= 0) {
      list[i] = c;
    } else {
      list.add(c);
    }
    await _persist();
  }

  /// Returns false if records still use the category.
  Future<bool> deleteCategory(String id) async {
    if (_data.credentials.any((c) => c.categoryId == id)) return false;
    _data.customCategories.removeWhere((c) => c.id == id);
    await _persist();
    return true;
  }

  // -- Master password / destructive ---------------------------------------

  Future<void> changeMasterPassword(String newPassword) async {
    await _repo.changePassword(_session!, _data, newPassword);
    // The stored biometric key is still valid (data key unchanged).
  }

  /// Replaces vault contents with a verified, decrypted backup. The existing
  /// master password and data key are kept, so device-bound secrets are never
  /// imported. The previous file is only replaced by the atomic save.
  Future<void> replaceWithBackup(VaultData restored) async {
    final old = _data;
    state = state.copyWith(data: restored, revision: state.revision + 1);
    try {
      await _repo.save(_session!, restored);
    } catch (_) {
      state = state.copyWith(data: old, revision: state.revision + 1);
      rethrow;
    }
  }

  Future<void> wipeEverything() async {
    _session?.wipe();
    _session = null;
    await _repo.deleteAll();
    await ref.read(secureStorageProvider).delete(key: _bioKeyName);
    await _store.clearAll();
    ref.invalidate(settingsProvider);
    state = const VaultState(status: VaultStatus.noVault);
  }
}

final vaultProvider = NotifierProvider<VaultController, VaultState>(
  VaultController.new,
);

// ---- Derived views ---------------------------------------------------------

enum SortMode { name, updated, used }

/// Case-insensitive in-memory search over non-secret data only: title, tags,
/// category name and NON-sensitive field values. Secrets are never indexed.
bool matchesQuery(Credential c, VaultData data, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return true;
  if (c.title.toLowerCase().contains(q)) return true;
  if (c.tags.any((t) => t.toLowerCase().contains(q))) return true;
  final cat = data.category(c.categoryId);
  if (cat != null && cat.name.toLowerCase().contains(q)) return true;
  final defs = [...?cat?.fields, ...c.extraFields];
  for (final f in defs) {
    if (f.sensitive || f.type == FieldType.longText) continue;
    final v = c.values[f.key];
    if (v != null && v.toLowerCase().contains(q)) return true;
  }
  return false;
}

List<Credential> sortCredentials(List<Credential> l, SortMode mode) {
  final out = [...l];
  switch (mode) {
    case SortMode.name:
      out.sort(
        (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
      );
    case SortMode.updated:
      out.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    case SortMode.used:
      DateTime t(Credential c) => c.lastAccessedAt ?? c.createdAt;
      out.sort((a, b) => t(b).compareTo(t(a)));
  }
  return out;
}

/// Likely duplicate: same category and same title, or same category with the
/// same non-secret subtitle identifier (e.g. same email address).
Credential? findDuplicate(VaultData data, Credential candidate) {
  final cat = data.category(candidate.categoryId);
  final sub = cat?.subtitleKey;
  final subVal = sub == null
      ? null
      : candidate.values[sub]?.trim().toLowerCase();
  for (final c in data.credentials) {
    if (c.id == candidate.id || c.isDeleted) continue;
    if (c.categoryId != candidate.categoryId) continue;
    if (c.title.trim().toLowerCase() == candidate.title.trim().toLowerCase()) {
      return c;
    }
    if (subVal != null &&
        subVal.isNotEmpty &&
        c.values[sub]?.trim().toLowerCase() == subVal) {
      return c;
    }
  }
  return null;
}

/// Local-only security hints; returns counts, never the passwords themselves.
class SecurityReport {
  const SecurityReport(this.weak, this.reused);
  final int weak;
  final int reused;
  bool get hasIssues => weak > 0 || reused > 0;
}

SecurityReport buildSecurityReport(VaultData data) {
  final seen = <String, int>{};
  var weak = 0;
  for (final c in data.credentials.where((c) => !c.isDeleted)) {
    final cat = data.category(c.categoryId);
    final defs = [...?cat?.fields, ...c.extraFields];
    for (final f in defs) {
      if (f.type != FieldType.password) continue;
      final v = c.values[f.key];
      if (v == null || v.isEmpty) continue;
      if (PasswordTools.isWeak(v)) weak++;
      seen.update(v, (n) => n + 1, ifAbsent: () => 1);
    }
  }
  final reused = seen.values.where((n) => n > 1).fold<int>(0, (a, n) => a + n);
  return SecurityReport(weak, reused);
}

final visibleCredentialsProvider = Provider<List<Credential>>((ref) {
  final s = ref.watch(vaultProvider);
  return s.data?.credentials.where((c) => !c.isDeleted).toList() ?? const [];
});

final deletedCredentialsProvider = Provider<List<Credential>>((ref) {
  final s = ref.watch(vaultProvider);
  return s.data?.credentials.where((c) => c.isDeleted).toList() ?? const [];
});
