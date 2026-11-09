import 'dart:convert';
import 'dart:typed_data';

import '../core/crypto/vault_crypto.dart';
import '../domain/vault_data.dart';

class BackupFormatException implements Exception {
  const BackupFormatException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Non-secret header, readable before the passphrase is entered. It is bound
/// into the AEAD as associated data, so editing it makes decryption fail.
class BackupHeader {
  const BackupHeader({
    required this.version,
    required this.createdAt,
    required this.recordCount,
  });
  final int version;
  final DateTime createdAt;
  final int recordCount;
}

/// Versioned, passphrase-encrypted backup file (.svbackup).
/// Argon2id(passphrase, random salt) -> AES-256-GCM (random nonce).
/// The backup passphrase is independent of the master password and is never
/// stored. No plaintext is ever written to disk.
class BackupService {
  static const _format = 'securevault-backup';
  static const supportedVersion = 1;
  static const fileExtension = 'svbackup';

  static List<int> _aad(int v, String created, int count) =>
      utf8.encode('$_format|$v|$created|$count');

  static Future<Uint8List> create(
    VaultData data,
    String passphrase, {
    KdfParams? kdf,
    DateTime? now,
  }) async {
    final live = data.credentials.where((c) => !c.isDeleted).length;
    final created = (now ?? DateTime.now()).toUtc().toIso8601String();
    final params = kdf ?? KdfParams.fresh();
    final key = await VaultCrypto.deriveKey(passphrase, params);
    final plain = utf8.encode(jsonEncode(data.toJson()));
    final sealed = await VaultCrypto.seal(
      plain,
      key,
      aad: _aad(supportedVersion, created, live),
    );
    VaultCrypto.wipe(key);
    VaultCrypto.wipe(plain);
    return Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          'format': _format,
          'v': supportedVersion,
          'createdAt': created,
          'records': live,
          'kdf': params.toJson(),
          'payload': sealed.toJson(),
        }),
      ),
    );
  }

  static Map<String, dynamic> _parse(Uint8List bytes) {
    if (bytes.isEmpty) throw const BackupFormatException('The file is empty.');
    try {
      final j = jsonDecode(utf8.decode(bytes));
      if (j is! Map<String, dynamic> || j['format'] != _format) {
        throw const BackupFormatException('This is not a SecureVault backup.');
      }
      final v = j['v'];
      if (v is! int || v < 1) {
        throw const BackupFormatException('Unreadable backup version.');
      }
      if (v > supportedVersion) {
        throw const BackupFormatException(
          'This backup was made by a newer app version. Update the app.',
        );
      }
      for (final k in ['createdAt', 'records', 'kdf', 'payload']) {
        if (!j.containsKey(k)) {
          throw const BackupFormatException(
            'The backup is incomplete or corrupted.',
          );
        }
      }
      return j;
    } on BackupFormatException {
      rethrow;
    } catch (_) {
      throw const BackupFormatException(
        'The backup is incomplete or corrupted.',
      );
    }
  }

  /// Structural validation + safe metadata only. Does not need the passphrase.
  static BackupHeader inspect(Uint8List bytes) {
    final j = _parse(bytes);
    try {
      return BackupHeader(
        version: j['v'] as int,
        createdAt: DateTime.parse(j['createdAt'] as String).toLocal(),
        recordCount: j['records'] as int,
      );
    } catch (_) {
      throw const BackupFormatException('The backup header is corrupted.');
    }
  }

  /// Authenticates and decrypts into memory only (staging). Throws
  /// [DecryptionFailure] for a wrong passphrase or a tampered file.
  static Future<VaultData> decrypt(Uint8List bytes, String passphrase) async {
    final j = _parse(bytes);
    final KdfParams kdf;
    final Sealed sealed;
    try {
      kdf = KdfParams.fromJson(Map<String, dynamic>.from(j['kdf'] as Map));
      sealed = Sealed.fromJson(Map<String, dynamic>.from(j['payload'] as Map));
    } catch (_) {
      throw const BackupFormatException('The backup is corrupted.');
    }
    final key = await VaultCrypto.deriveKey(passphrase, kdf);
    final List<int> plain;
    try {
      plain = await VaultCrypto.open(
        sealed,
        key,
        aad: _aad(j['v'] as int, j['createdAt'] as String, j['records'] as int),
      );
    } finally {
      VaultCrypto.wipe(key);
    }
    try {
      return VaultData.fromJson(
        jsonDecode(utf8.decode(plain)) as Map<String, dynamic>,
      );
    } on FormatException catch (e) {
      throw BackupFormatException(e.message);
    } finally {
      VaultCrypto.wipe(plain);
    }
  }
}
