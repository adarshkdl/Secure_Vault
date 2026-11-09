import 'dart:convert';
import 'dart:io';

import '../core/crypto/vault_crypto.dart';
import '../domain/vault_data.dart';

/// Material held in memory only while the vault is unlocked.
class VaultSession {
  VaultSession({required this.dek, required this.kdf, required this.wrapped});

  /// Random 256-bit data-encryption key (never derived directly from the
  /// password, so changing the password only re-wraps this key).
  final List<int> dek;
  KdfParams kdf;
  Sealed wrapped;

  void wipe() => VaultCrypto.wipe(dek);
}

class VaultFormatException implements Exception {
  const VaultFormatException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Persists the whole vault as one encrypted file. Titles, field names and
/// values are all inside the ciphertext; only the KDF parameters, salt and
/// format version are in the clear.
///
/// File: { format, v, kdf, wrapped: AES-GCM(dek, KEK), data: AES-GCM(json, dek) }
class VaultRepository {
  VaultRepository(this.directory, {KdfParams Function()? kdfFactory})
    : _kdfFactory = kdfFactory ?? KdfParams.fresh;

  final Directory directory;
  final KdfParams Function() _kdfFactory;

  static const _format = 'securevault';
  static const _version = 1;
  static final _aadKey = utf8.encode('securevault/v1/wrapped-key');
  static final _aadData = utf8.encode('securevault/v1/data');

  File get _file => File('${directory.path}${Platform.pathSeparator}vault.bin');
  File get _tmp => File('${_file.path}.tmp');

  Future<bool> exists() => _file.exists();

  Future<(VaultSession, VaultData)> create(String password) async {
    final kdf = _kdfFactory();
    final kek = await VaultCrypto.deriveKey(password, kdf);
    final dek = VaultCrypto.newKey();
    final wrapped = await VaultCrypto.seal(dek, kek, aad: _aadKey);
    VaultCrypto.wipe(kek);
    final session = VaultSession(dek: dek, kdf: kdf, wrapped: wrapped);
    final data = VaultData();
    await save(session, data);
    return (session, data);
  }

  Map<String, dynamic> _read(String text) {
    final Object? j;
    try {
      j = jsonDecode(text);
    } on FormatException {
      throw const VaultFormatException('Vault file is corrupted.');
    }
    if (j is! Map<String, dynamic> || j['format'] != _format) {
      throw const VaultFormatException('Not a SecureVault file.');
    }
    if ((j['v'] as int? ?? 0) > _version) {
      throw const VaultFormatException(
        'Vault was created by a newer app version.',
      );
    }
    return j;
  }

  /// Throws [DecryptionFailure] on a wrong password.
  Future<(VaultSession, VaultData)> unlock(String password) async {
    final j = _read(await _file.readAsString());
    final kdf = KdfParams.fromJson(Map<String, dynamic>.from(j['kdf'] as Map));
    final wrapped = Sealed.fromJson(
      Map<String, dynamic>.from(j['wrapped'] as Map),
    );
    final kek = await VaultCrypto.deriveKey(password, kdf);
    final List<int> dek;
    try {
      dek = await VaultCrypto.open(wrapped, kek, aad: _aadKey);
    } finally {
      VaultCrypto.wipe(kek);
    }
    final session = VaultSession(dek: dek, kdf: kdf, wrapped: wrapped);
    final data = await _decryptData(j, dek);
    return (session, data);
  }

  /// Used by biometric unlock, which releases the stored data key.
  Future<(VaultSession, VaultData)> unlockWithKey(List<int> dek) async {
    final j = _read(await _file.readAsString());
    final kdf = KdfParams.fromJson(Map<String, dynamic>.from(j['kdf'] as Map));
    final wrapped = Sealed.fromJson(
      Map<String, dynamic>.from(j['wrapped'] as Map),
    );
    final data = await _decryptData(j, dek);
    return (VaultSession(dek: dek, kdf: kdf, wrapped: wrapped), data);
  }

  Future<VaultData> _decryptData(Map<String, dynamic> j, List<int> dek) async {
    final plain = await VaultCrypto.open(
      Sealed.fromJson(Map<String, dynamic>.from(j['data'] as Map)),
      dek,
      aad: _aadData,
    );
    try {
      return VaultData.fromJson(
        jsonDecode(utf8.decode(plain)) as Map<String, dynamic>,
      );
    } finally {
      VaultCrypto.wipe(plain);
    }
  }

  /// Re-encrypts with a fresh nonce and writes atomically (temp file, then
  /// rename) so a crash never leaves a half-written vault.
  Future<void> save(VaultSession s, VaultData data) async {
    final plain = utf8.encode(jsonEncode(data.toJson()));
    final sealed = await VaultCrypto.seal(plain, s.dek, aad: _aadData);
    VaultCrypto.wipe(plain);
    final out = jsonEncode({
      'format': _format,
      'v': _version,
      'kdf': s.kdf.toJson(),
      'wrapped': s.wrapped.toJson(),
      'data': sealed.toJson(),
    });
    await _tmp.writeAsString(out, flush: true);
    await _tmp.rename(_file.path);
  }

  /// Re-wraps the data key under a key derived from [newPassword] with a new
  /// random salt. Caller must have verified the current password.
  Future<void> changePassword(
    VaultSession s,
    VaultData data,
    String newPassword,
  ) async {
    final kdf = _kdfFactory();
    final kek = await VaultCrypto.deriveKey(newPassword, kdf);
    final wrapped = await VaultCrypto.seal(s.dek, kek, aad: _aadKey);
    VaultCrypto.wipe(kek);
    s.kdf = kdf;
    s.wrapped = wrapped;
    await save(s, data);
  }

  /// Checks a password without changing any state.
  Future<bool> verifyPassword(String password) async {
    try {
      final (s, _) = await unlock(password);
      s.wipe();
      return true;
    } on DecryptionFailure {
      return false;
    }
  }

  Future<void> deleteAll() async {
    if (await _file.exists()) await _file.delete();
    if (await _tmp.exists()) await _tmp.delete();
  }
}
