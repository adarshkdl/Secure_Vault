import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:secure_vault/core/crypto/qr_transfer.dart';

// Synthetic payload only.
final _payload = utf8.encode(
  '{"t":"Demo","f":[{"l":"Password","v":"synthetic-pw-1","s":true}]}',
);

Future<({QrReceiveSession rx, String offer, QrResponse resp})> _handshake({
  DateTime? now,
}) async {
  final rx = await QrReceiveSession.start(now: now);
  final offer = await rx.offer();
  final resp = await QrTransfer.respond(
    offer: offer,
    payload: _payload,
    now: now,
  );
  return (rx: rx, offer: offer, resp: resp);
}

void main() {
  test('round trip: payload decrypts and confirmation codes match', () async {
    final h = await _handshake();
    final got = await h.rx.accept(h.resp.message);
    expect(utf8.decode(got.payload), utf8.decode(_payload));
    expect(got.confirmationCode, h.resp.confirmationCode);
    expect(got.confirmationCode, matches(RegExp(r'^\d{6}$')));
  });

  test('offer and response never contain the plaintext', () async {
    final h = await _handshake();
    for (final s in [h.offer, h.resp.message]) {
      expect(s.contains('synthetic-pw-1'), isFalse);
      final inner = utf8.decode(
        base64Url.decode(base64Url.normalize(s.substring(s.indexOf(':') + 1))),
      );
      expect(inner.contains('synthetic-pw-1'), isFalse);
    }
  });

  test('one-time use: second accept is refused', () async {
    final h = await _handshake();
    await h.rx.accept(h.resp.message);
    expect(h.rx.consumed, isTrue);
    expect(
      () => h.rx.accept(h.resp.message),
      throwsA(isA<QrTransferException>()),
    );
  });

  test('expired offer is rejected by the sender', () async {
    final t0 = DateTime(2030, 1, 1, 12);
    final rx = await QrReceiveSession.start(now: t0);
    final offer = await rx.offer();
    expect(
      () => QrTransfer.respond(
        offer: offer,
        payload: _payload,
        now: t0.add(const Duration(minutes: 3)),
      ),
      throwsA(isA<QrTransferException>()),
    );
  });

  test('expired session is rejected by the receiver', () async {
    final t0 = DateTime(2030, 1, 1, 12);
    final h = await _handshake(now: t0);
    expect(
      () =>
          h.rx.accept(h.resp.message, now: t0.add(const Duration(minutes: 3))),
      throwsA(isA<QrTransferException>()),
    );
  });

  test('tampered ciphertext fails and kills the session', () async {
    final h = await _handshake();
    final raw = utf8.decode(
      base64Url.decode(
        base64Url.normalize(
          h.resp.message.substring(QrTransfer.responsePrefix.length),
        ),
      ),
    );
    final m = jsonDecode(raw) as Map<String, dynamic>;
    final ct = base64Url.decode(base64Url.normalize(m['ct'] as String));
    ct[0] ^= 1;
    m['ct'] = base64Url.encode(ct).replaceAll('=', '');
    final bad =
        QrTransfer.responsePrefix +
        base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');
    expect(() => h.rx.accept(bad), throwsA(isA<QrTransferException>()));
    // Session is burned even though the genuine message is intact.
    expect(
      () => h.rx.accept(h.resp.message),
      throwsA(isA<QrTransferException>()),
    );
  });

  test(
    'response for a different session is refused without burning ours',
    () async {
      final a = await _handshake();
      final b = await _handshake();
      await expectLater(
        a.rx.accept(b.resp.message),
        throwsA(isA<QrTransferException>()),
      );
      expect(a.rx.consumed, isFalse);
      final got = await a.rx.accept(a.resp.message);
      expect(got.payload, _payload);
    },
  );

  test('a third party without the private key cannot decrypt', () async {
    final h = await _handshake();
    final other = await QrReceiveSession.start();
    await expectLater(
      other.accept(h.resp.message),
      throwsA(isA<QrTransferException>()),
    );
  });

  test('oversized, empty and garbage inputs are rejected', () async {
    final rx = await QrReceiveSession.start();
    final offer = await rx.offer();
    expect(
      () => QrTransfer.respond(offer: offer, payload: List.filled(2000, 65)),
      throwsA(isA<QrTransferException>()),
    );
    expect(
      () => QrTransfer.respond(offer: offer, payload: const []),
      throwsA(isA<QrTransferException>()),
    );
    expect(
      () => QrTransfer.respond(offer: 'https://example.com', payload: _payload),
      throwsA(isA<QrTransferException>()),
    );
    expect(() => rx.accept('garbage'), throwsA(isA<QrTransferException>()));
  });
}
