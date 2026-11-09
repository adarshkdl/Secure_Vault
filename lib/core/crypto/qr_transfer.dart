import 'dart:convert';

import 'package:cryptography/cryptography.dart';

import 'vault_crypto.dart';

/// Thrown for any QR-transfer failure. The message is safe to show to users and
/// never contains payload data.
class QrTransferException implements Exception {
  const QrTransferException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Result of a successful receive: the decrypted payload and the short
/// confirmation code both devices must show identically.
class QrReceived {
  const QrReceived(this.payload, this.confirmationCode);
  final List<int> payload;
  final String confirmationCode;
}

/// What the sender produces after scanning the receiver's offer.
class QrResponse {
  const QrResponse(this.message, this.confirmationCode, this.expiresAt);

  /// Text to render as the second QR code.
  final String message;
  final String confirmationCode;
  final DateTime expiresAt;
}

/// Offline, two-step encrypted QR transfer.
///
/// 1. The receiver creates an ephemeral X25519 key pair and shows the public
///    key, a random session id and an expiry as QR #1 (the "offer"). The offer
///    contains no secret.
/// 2. The sender scans it, creates its own ephemeral key pair, derives a
///    one-time key with X25519 + HKDF-SHA256, seals the payload with
///    AES-256-GCM and shows the result as QR #2 (the "response").
/// 3. The receiver scans QR #2, decrypts, and both devices display the same
///    6-digit confirmation code (derived from the shared secret) so the users
///    can detect a swapped QR code. Nothing is saved until the receiver
///    confirms.
///
/// The receiver's private key lives only in memory, is usable exactly once,
/// and is destroyed on the first decryption attempt, on expiry or on cancel.
/// A photographed response QR is useless without that private key.
/// All primitives come from `package:cryptography`; nothing custom.
class QrTransfer {
  QrTransfer._();

  static const int version = 1;
  static const String offerPrefix = 'svq1o:';
  static const String responsePrefix = 'svq1r:';

  /// How long an offer stays valid.
  static const Duration offerTtl = Duration(minutes: 2);

  /// Upper bound on a plaintext payload so the response fits a scannable QR.
  static const int maxPayloadBytes = 700;

  static final _x25519 = X25519();
  static final _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);

  static String _b64(List<int> b) => base64UrlEncode(b).replaceAll('=', '');
  static List<int> _unb64(String s) => base64Url.decode(base64Url.normalize(s));

  static List<int> _aad(List<int> sid, List<int> senderPk, int expMs) => [
    ...utf8.encode('securevault-qr-v$version'),
    ...sid,
    ...senderPk,
    ...utf8.encode('|$expMs'),
  ];

  static Future<({List<int> key, String code})> _derive(
    SecretKey shared,
    List<int> sid,
  ) async {
    final key = await _hkdf.deriveKey(
      secretKey: shared,
      nonce: sid,
      info: utf8.encode('securevault-qr key'),
    );
    final sasKey = await _hkdf.deriveKey(
      secretKey: shared,
      nonce: sid,
      info: utf8.encode('securevault-qr confirmation'),
    );
    final sas = await sasKey.extractBytes();
    final n =
        ((sas[0] << 24) | (sas[1] << 16) | (sas[2] << 8) | sas[3]) & 0x7fffffff;
    return (
      key: await key.extractBytes(),
      code: (n % 1000000).toString().padLeft(6, '0'),
    );
  }

  /// Sender side: validate the scanned [offer] and produce the response QR.
  static Future<QrResponse> respond({
    required String offer,
    required List<int> payload,
    DateTime? now,
  }) async {
    final t = now ?? DateTime.now();
    if (payload.isEmpty) {
      throw const QrTransferException('Nothing selected to send.');
    }
    if (payload.length > maxPayloadBytes) {
      throw const QrTransferException(
        'Too much data for a QR code. Select fewer fields or shorten the notes.',
      );
    }
    final Map<String, dynamic> o;
    final List<int> sid, receiverPk;
    final int expMs;
    try {
      if (!offer.startsWith(offerPrefix)) throw const FormatException();
      o =
          jsonDecode(utf8.decode(_unb64(offer.substring(offerPrefix.length))))
              as Map<String, dynamic>;
      if (o['v'] != version) throw const FormatException();
      sid = _unb64(o['sid'] as String);
      receiverPk = _unb64(o['pk'] as String);
      expMs = o['exp'] as int;
      if (sid.length != 16 || receiverPk.length != 32) {
        throw const FormatException();
      }
    } on Object {
      throw const QrTransferException(
        'This is not a valid SecureVault receive code.',
      );
    }
    final exp = DateTime.fromMillisecondsSinceEpoch(expMs);
    if (!t.isBefore(exp)) {
      throw const QrTransferException(
        'This receive code has expired. Ask the receiver to create a new one.',
      );
    }
    // Reject absurdly long-lived offers (a malicious or buggy receiver).
    if (exp.isAfter(t.add(offerTtl + const Duration(seconds: 30)))) {
      throw const QrTransferException('This receive code is not valid.');
    }

    final kp = await _x25519.newKeyPair();
    final senderPk = (await kp.extractPublicKey()).bytes;
    final shared = await _x25519.sharedSecretKey(
      keyPair: kp,
      remotePublicKey: SimplePublicKey(receiverPk, type: KeyPairType.x25519),
    );
    final d = await _derive(shared, sid);
    final sealed = await VaultCrypto.seal(
      payload,
      d.key,
      aad: _aad(sid, senderPk, expMs),
    );
    VaultCrypto.wipe(d.key);
    final msg = jsonEncode({
      'v': version,
      'sid': _b64(sid),
      'spk': _b64(senderPk),
      'exp': expMs,
      'n': _b64(sealed.nonce),
      'ct': _b64([...sealed.cipherText, ...sealed.mac]),
    });
    return QrResponse(responsePrefix + _b64(utf8.encode(msg)), d.code, exp);
  }
}

/// Receiver side of the transfer. Holds the ephemeral private key and enforces
/// expiry and one-time use.
class QrReceiveSession {
  QrReceiveSession._(this._keyPair, this._sid, this.expiresAt);

  final SimpleKeyPair _keyPair;
  final List<int> _sid;
  final DateTime expiresAt;
  bool _consumed = false;

  bool get consumed => _consumed;

  static Future<QrReceiveSession> start({DateTime? now}) async {
    final kp = await QrTransfer._x25519.newKeyPair();
    return QrReceiveSession._(
      kp,
      VaultCrypto.randomBytes(16),
      (now ?? DateTime.now()).add(QrTransfer.offerTtl),
    );
  }

  bool isExpired([DateTime? now]) =>
      !(now ?? DateTime.now()).isBefore(expiresAt);

  /// Text for QR #1. Contains only a public key, a session id and an expiry.
  Future<String> offer() async {
    final pk = (await _keyPair.extractPublicKey()).bytes;
    return QrTransfer.offerPrefix +
        QrTransfer._b64(
          utf8.encode(
            jsonEncode({
              'v': QrTransfer.version,
              'sid': QrTransfer._b64(_sid),
              'pk': QrTransfer._b64(pk),
              'exp': expiresAt.millisecondsSinceEpoch,
            }),
          ),
        );
  }

  /// Decrypts a scanned response. Single use: after this returns or throws
  /// (other than for an unrelated/malformed code), the session is dead.
  Future<QrReceived> accept(String response, {DateTime? now}) async {
    if (_consumed) {
      throw const QrTransferException(
        'This receive code was already used. Start a new one.',
      );
    }
    if (isExpired(now)) {
      _consumed = true;
      throw const QrTransferException(
        'This receive code has expired. Start a new one.',
      );
    }
    final Map<String, dynamic> m;
    final List<int> sid, senderPk, nonce, ctAndMac;
    final int expMs;
    try {
      if (!response.startsWith(QrTransfer.responsePrefix)) {
        throw const FormatException();
      }
      m =
          jsonDecode(
                utf8.decode(
                  QrTransfer._unb64(
                    response.substring(QrTransfer.responsePrefix.length),
                  ),
                ),
              )
              as Map<String, dynamic>;
      if (m['v'] != QrTransfer.version) throw const FormatException();
      sid = QrTransfer._unb64(m['sid'] as String);
      senderPk = QrTransfer._unb64(m['spk'] as String);
      nonce = QrTransfer._unb64(m['n'] as String);
      ctAndMac = QrTransfer._unb64(m['ct'] as String);
      expMs = m['exp'] as int;
      if (senderPk.length != 32 || nonce.length != 12 || ctAndMac.length < 17) {
        throw const FormatException();
      }
    } on Object {
      throw const QrTransferException(
        'This is not a valid SecureVault transfer code.',
      );
    }
    if (!_listEq(sid, _sid)) {
      // A code meant for another session: do not burn this one.
      throw const QrTransferException(
        'This code was not created for your current receive code.',
      );
    }
    _consumed = true; // from here on any outcome ends the session
    try {
      if (expMs != expiresAt.millisecondsSinceEpoch) {
        throw const QrTransferException('Transfer code is not valid.');
      }
      final shared = await QrTransfer._x25519.sharedSecretKey(
        keyPair: _keyPair,
        remotePublicKey: SimplePublicKey(senderPk, type: KeyPairType.x25519),
      );
      final d = await QrTransfer._derive(shared, sid);
      final split = ctAndMac.length - 16;
      try {
        final plain = await VaultCrypto.open(
          Sealed(nonce, ctAndMac.sublist(0, split), ctAndMac.sublist(split)),
          d.key,
          aad: QrTransfer._aad(sid, senderPk, expMs),
        );
        return QrReceived(plain, d.code);
      } on DecryptionFailure {
        throw const QrTransferException(
          'The transfer code could not be verified. It may be corrupted or tampered with.',
        );
      } finally {
        VaultCrypto.wipe(d.key);
      }
    } finally {
      cancel();
    }
  }

  /// Ends the session: it refuses all further decryption. (Dart cannot wipe
  /// the key object from memory; dropping the session lets it be collected.)
  void cancel() => _consumed = true;

  static bool _listEq(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var r = 0;
    for (var i = 0; i < a.length; i++) {
      r |= a[i] ^ b[i];
    }
    return r == 0;
  }
}
