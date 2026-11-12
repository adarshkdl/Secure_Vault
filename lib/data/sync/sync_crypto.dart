import 'dart:convert';

import 'package:cryptography/cryptography.dart';

import '../../core/crypto/vault_crypto.dart';
import 'sync_models.dart';

/// A cloud item failed authentication or was malformed. Never contains data.
class SyncIntegrityException implements Exception {
  const SyncIntegrityException();
  @override
  String toString() => 'A cloud item failed its integrity check.';
}

/// Encrypts and decrypts individual sync items. Primitives only from
/// `package:cryptography` (HKDF-SHA256, AES-256-GCM).
///
/// The sync key is derived from the vault data key with HKDF, so the key that
/// protects the local file is never used directly on cloud data. Each item's
/// account id, item id, type, edit time and deleted flag are bound in as
/// associated data, so the server cannot move a ciphertext to another item or
/// change its timestamp without detection. (A server can still replay an older
/// valid version; the local vault stays the authoritative copy.)
class SyncCrypto {
  SyncCrypto._();

  static final _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);

  static Future<List<int>> deriveKey(List<int> dek) async {
    final k = await _hkdf.deriveKey(
      secretKey: SecretKey(dek),
      nonce: utf8.encode('securevault-sync-salt-v1'),
      info: utf8.encode('securevault/sync/v1/items'),
    );
    return k.extractBytes();
  }

  static List<int> aad(
    String uid,
    String id,
    SyncKind kind,
    int ut,
    bool deleted,
  ) => utf8.encode(
    'securevault/sync/v1|$uid|$id|${kind.code}|$ut|${deleted ? 1 : 0}',
  );

  static Future<RemoteItem> seal(
    SyncItem item,
    List<int> key,
    String uid,
  ) async {
    final plain = utf8.encode(jsonEncode(item.json ?? const {'d': 1}));
    try {
      final s = await VaultCrypto.seal(
        plain,
        key,
        aad: aad(uid, item.id, item.kind, item.ut, item.deleted),
      );
      return RemoteItem(
        id: item.id,
        kind: item.kind,
        ut: item.ut,
        deleted: item.deleted,
        sealed: s,
      );
    } finally {
      VaultCrypto.wipe(plain);
    }
  }

  static Future<SyncItem> open(RemoteItem r, List<int> key, String uid) async {
    final List<int> plain;
    try {
      plain = await VaultCrypto.open(
        r.sealed,
        key,
        aad: aad(uid, r.id, r.kind, r.ut, r.deleted),
      );
    } on DecryptionFailure {
      throw const SyncIntegrityException();
    }
    try {
      final j = jsonDecode(utf8.decode(plain));
      if (j is! Map) throw const SyncIntegrityException();
      return SyncItem(
        id: r.id,
        kind: r.kind,
        updatedAt: DateTime.fromMillisecondsSinceEpoch(r.ut),
        json: r.deleted ? null : Map<String, dynamic>.from(j),
      );
    } on FormatException {
      throw const SyncIntegrityException();
    } finally {
      VaultCrypto.wipe(plain);
    }
  }
}
