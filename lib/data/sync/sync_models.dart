import '../../core/crypto/vault_crypto.dart';

enum SyncKind {
  credential('c'),
  category('k');

  const SyncKind(this.code);

  /// Stored in the clear in the cloud so a device knows what to decode.
  final String code;

  static SyncKind? fromCode(String? c) {
    for (final k in values) {
      if (k.code == c) return k;
    }
    return null;
  }
}

int ms(DateTime d) => d.millisecondsSinceEpoch;

/// One decrypted unit of sync: a credential, a custom category, or the
/// tombstone of a permanently deleted one ([json] == null).
class SyncItem {
  const SyncItem({
    required this.id,
    required this.kind,
    required this.updatedAt,
    this.json,
  });
  final String id;
  final SyncKind kind;
  final DateTime updatedAt;
  final Map<String, dynamic>? json;
  bool get deleted => json == null;
  int get ut => ms(updatedAt);
}

/// What is stored in the cloud for one item. Only [id], [kind], [ut],
/// [deleted] and the ciphertext size are readable by the server.
class RemoteItem {
  const RemoteItem({
    required this.id,
    required this.kind,
    required this.ut,
    required this.deleted,
    required this.sealed,
    this.serverTime,
  });
  final String id;
  final SyncKind kind;
  final int ut;
  final bool deleted;
  final Sealed sealed;

  /// Server-side write time (set by the backend, used as a sync cursor).
  final DateTime? serverTime;
}

/// The vault's KDF parameters and wrapped data key, stored once per account.
/// Same material as the local vault file header: useless without the master
/// password, but it is what lets a new device derive the key.
class RemoteHeader {
  const RemoteHeader({
    required this.kdf,
    required this.wrapped,
    required this.rev,
  });
  final KdfParams kdf;
  final Sealed wrapped;
  final int rev;

  bool sameKeyAs(KdfParams k, Sealed w) =>
      _eq(wrapped.cipherText, w.cipherText) &&
      _eq(wrapped.nonce, w.nonce) &&
      _eq(kdf.salt, k.salt);

  static bool _eq(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Storage backend for sync. Firestore in the app, in-memory in tests.
abstract class SyncRemote {
  Future<RemoteHeader?> getHeader();
  Future<void> putHeader(RemoteHeader header);

  /// Items written after [since] (all items when null).
  Future<List<RemoteItem>> fetchChanged(DateTime? since);
  Future<void> pushItems(List<RemoteItem> items);

  /// Deletes every item and the header for this account.
  Future<void> deleteEverything();
}
