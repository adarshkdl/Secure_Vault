import '../../domain/vault_data.dart';
import 'sync_crypto.dart';
import 'sync_merge.dart';
import 'sync_models.dart';

/// Non-secret bookkeeping kept on this device between syncs: ids and edit
/// times only (the server already sees those).
class SyncState {
  const SyncState({this.cursor, this.pushed = const {}});

  /// Newest server write time seen, so later syncs fetch only what changed.
  final DateTime? cursor;

  /// id -> edit time of the version this device last uploaded or received.
  final Map<String, int> pushed;
}

abstract class SyncStateStore {
  SyncState load(String uid);
  Future<void> save(String uid, SyncState state);
  Future<void> clear(String uid);
}

class SyncReport {
  const SyncReport({
    required this.pulled,
    required this.applied,
    required this.pushed,
    required this.rejected,
    required this.at,
  });
  final int pulled;
  final int applied;
  final int pushed;

  /// Cloud items that failed their integrity check or could not be decoded.
  final int rejected;
  final DateTime at;
}

/// Result of one sync pass. Call [commit] only after [merged] has been saved
/// to the local vault, so a failed local save never marks changes as synced.
class SyncRun {
  const SyncRun({
    required this.merged,
    required this.changed,
    required this.report,
    required this.commit,
  });
  final VaultData merged;
  final bool changed;
  final SyncReport report;
  final Future<void> Function() commit;
}

/// Two-way, per-record sync of an unlocked vault with an encrypted remote.
class SyncEngine {
  SyncEngine({required this.remote, required this.store, required this.uid});

  final SyncRemote remote;
  final SyncStateStore store;
  final String uid;

  /// Cursor overlap: re-reading a few already-seen items is harmless (merging
  /// is idempotent) and protects against writes that become visible late.
  static const overlap = Duration(minutes: 5);

  Future<SyncRun> run(VaultData local, List<int> dek) async {
    final key = await SyncCrypto.deriveKey(dek);
    try {
      final state = store.load(uid);
      final since = state.cursor?.subtract(overlap);
      final fetched = await remote.fetchChanged(since);

      var cursor = state.cursor;
      final decoded = <SyncItem>[];
      var rejected = 0;
      for (final r in fetched) {
        final st = r.serverTime;
        if (st != null && (cursor == null || st.isAfter(cursor))) cursor = st;
        try {
          decoded.add(await SyncCrypto.open(r, key, uid));
        } on SyncIntegrityException {
          rejected++;
        }
      }

      final out = mergeSync(
        local: local,
        remote: decoded,
        pushed: state.pushed,
      );

      if (out.toPush.isNotEmpty) {
        final sealed = [
          for (final i in out.toPush) await SyncCrypto.seal(i, key, uid),
        ];
        await remote.pushItems(sealed);
      }

      final pushed = {
        ...state.pushed,
        ...out.inSync,
        for (final i in out.toPush) i.id: i.ut,
      };
      return SyncRun(
        merged: out.merged,
        changed: out.changed,
        report: SyncReport(
          pulled: fetched.length,
          applied: out.applied,
          pushed: out.toPush.length,
          rejected: rejected + out.rejected,
          at: DateTime.now(),
        ),
        commit: () =>
            store.save(uid, SyncState(cursor: cursor, pushed: pushed)),
      );
    } finally {
      // Best effort: the derived key must not outlive the pass.
      for (var i = 0; i < key.length; i++) {
        try {
          key[i] = 0;
        } on UnsupportedError {
          break;
        }
      }
    }
  }
}
