import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'sync_engine.dart';

/// Stores [SyncState] and the sync on/off choice in SharedPreferences. Holds
/// only ids and timestamps, never record content or keys.
class PrefsSyncStateStore implements SyncStateStore {
  PrefsSyncStateStore(this._p);
  final SharedPreferences _p;

  static const _enabledKey = 'sync.enabledUid';
  static String _key(String uid) => 'sync.state.$uid';

  /// The account this device is syncing with, or null when sync is off.
  String? get enabledUid => _p.getString(_enabledKey);
  Future<void> setEnabledUid(String? uid) =>
      uid == null ? _p.remove(_enabledKey) : _p.setString(_enabledKey, uid);

  @override
  SyncState load(String uid) {
    final raw = _p.getString(_key(uid));
    if (raw == null) return const SyncState();
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      final c = j['cursor'] as int?;
      return SyncState(
        cursor: c == null ? null : DateTime.fromMillisecondsSinceEpoch(c),
        pushed: {
          for (final e in (j['pushed'] as Map).entries)
            e.key as String: e.value as int,
        },
      );
    } on Object {
      return const SyncState(); // corrupt state: do a full resync
    }
  }

  @override
  Future<void> save(String uid, SyncState s) => _p.setString(
    _key(uid),
    jsonEncode({
      'cursor': s.cursor?.millisecondsSinceEpoch,
      'pushed': s.pushed,
    }),
  );

  @override
  Future<void> clear(String uid) => _p.remove(_key(uid));
}
