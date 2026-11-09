import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Argon2id parameters stored (unencrypted) beside each wrapped key so they
/// can be raised in future versions without breaking existing vaults.
class KdfParams {
  const KdfParams({
    required this.memoryKiB,
    required this.iterations,
    required this.parallelism,
    required this.salt,
  });

  /// OWASP-recommended minimum profile for Argon2id (19 MiB, t=2, p=1).
  static const int defaultMemoryKiB = 19456;
  static const int defaultIterations = 2;
  static const int defaultParallelism = 1;

  /// Used when the key header is stored in the cloud (64 MiB, t=3).
  static const int cloudMemoryKiB = 65536;
  static const int cloudIterations = 3;

  /// Upper bounds accepted from an untrusted source (a cloud header), so a
  /// malicious server cannot make the device allocate gigabytes.
  bool get withinSafeLimits =>
      memoryKiB >= 8192 &&
      memoryKiB <= 262144 &&
      iterations >= 1 &&
      iterations <= 10 &&
      parallelism >= 1 &&
      parallelism <= 4 &&
      salt.length >= 16 &&
      salt.length <= 64;

  final int memoryKiB;
  final int iterations;
  final int parallelism;
  final List<int> salt;

  factory KdfParams.fresh({
    int memoryKiB = defaultMemoryKiB,
    int iterations = defaultIterations,
    int parallelism = defaultParallelism,
  }) => KdfParams(
    memoryKiB: memoryKiB,
    iterations: iterations,
    parallelism: parallelism,
    salt: VaultCrypto.randomBytes(16),
  );

  Map<String, dynamic> toJson() => {
    'alg': 'argon2id',
    'm': memoryKiB,
    't': iterations,
    'p': parallelism,
    'salt': base64Encode(salt),
  };

  factory KdfParams.fromJson(Map<String, dynamic> j) {
    if (j['alg'] != 'argon2id') {
      throw const FormatException('Unsupported key derivation algorithm');
    }
    return KdfParams(
      memoryKiB: j['m'] as int,
      iterations: j['t'] as int,
      parallelism: j['p'] as int,
      salt: base64Decode(j['salt'] as String),
    );
  }
}

/// An AES-256-GCM sealed blob (nonce + ciphertext + 128-bit tag).
class Sealed {
  const Sealed(this.nonce, this.cipherText, this.mac);
  final List<int> nonce;
  final List<int> cipherText;
  final List<int> mac;

  Map<String, dynamic> toJson() => {
    'nonce': base64Encode(nonce),
    'ct': base64Encode(cipherText),
    'mac': base64Encode(mac),
  };

  factory Sealed.fromJson(Map<String, dynamic> j) => Sealed(
    base64Decode(j['nonce'] as String),
    base64Decode(j['ct'] as String),
    base64Decode(j['mac'] as String),
  );
}

class DecryptionFailure implements Exception {
  const DecryptionFailure();
  @override
  String toString() => 'Decryption failed (wrong key or tampered data)';
}

/// Thin wrapper over vetted primitives from `package:cryptography`:
/// Argon2id for key derivation and AES-256-GCM for authenticated encryption.
/// No custom cryptography is implemented here.
class VaultCrypto {
  static final AesGcm _aes = AesGcm.with256bits();

  static List<int> randomBytes(int n) => SecretKeyData.random(length: n).bytes;

  static List<int> newKey() => randomBytes(32);

  /// Derives a 256-bit key from [password]. Runs in a background isolate
  /// because Argon2id is deliberately expensive.
  static Future<List<int>> deriveKey(String password, KdfParams p) {
    final pw = utf8.encode(password);
    final m = p.memoryKiB, t = p.iterations, par = p.parallelism;
    final salt = List<int>.of(p.salt);
    return Isolate.run(() async {
      final kdf = Argon2id(
        memory: m,
        parallelism: par,
        iterations: t,
        hashLength: 32,
      );
      final key = await kdf.deriveKey(secretKey: SecretKey(pw), nonce: salt);
      return key.extractBytes();
    });
  }

  static Future<Sealed> seal(
    List<int> plain,
    List<int> key, {
    List<int> aad = const [],
  }) async {
    final box = await _aes.encrypt(
      plain,
      secretKey: SecretKey(key),
      nonce: _aes.newNonce(), // 96-bit random nonce, unique per message
      aad: aad,
    );
    return Sealed(box.nonce, box.cipherText, box.mac.bytes);
  }

  static Future<List<int>> open(
    Sealed s,
    List<int> key, {
    List<int> aad = const [],
  }) async {
    try {
      return await _aes.decrypt(
        SecretBox(s.cipherText, nonce: s.nonce, mac: Mac(s.mac)),
        secretKey: SecretKey(key),
        aad: aad,
      );
    } on SecretBoxAuthenticationError {
      throw const DecryptionFailure();
    }
  }

  /// Best-effort zeroing; Dart cannot guarantee no copies remain.
  static void wipe(List<int>? bytes) {
    if (bytes == null) return;
    for (var i = 0; i < bytes.length; i++) {
      try {
        bytes[i] = 0;
      } on UnsupportedError {
        return; // unmodifiable list
      }
    }
  }

  static Uint8List u8(List<int> b) =>
      b is Uint8List ? b : Uint8List.fromList(b);
}
