import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:secure_vault/core/qr_payload.dart';

void main() {
  test('record round-trips and keeps sensitivity flags', () {
    const r = QrRecord(
      title: 'Demo router',
      notes: 'synthetic',
      fields: [
        QrField('User', 'admin'),
        QrField('Password', 'synthetic-pw', sensitive: true),
      ],
    );
    final back = QrRecord.decode(r.encode());
    expect(back.title, 'Demo router');
    expect(back.notes, 'synthetic');
    expect(back.fields[0].sensitive, isFalse);
    expect(back.fields[1].sensitive, isTrue);
    expect(back.fields[1].value, 'synthetic-pw');
  });

  test('malformed or hostile content is rejected', () {
    for (final bad in [
      'not json',
      '{"v":2,"t":"x","f":[]}',
      '{"v":1,"t":"","f":[]}',
      '{"v":1,"t":"x","f":[1]}',
      '{"v":1,"t":"x","f":[{"l":"","v":"a"}]}',
      jsonEncode({'v': 1, 't': 'x' * 601, 'f': []}),
      jsonEncode({
        'v': 1,
        't': 'x',
        'f': List.generate(31, (i) => {'l': 'a', 'v': 'b'}),
      }),
    ]) {
      expect(
        () => QrRecord.decode(utf8.encode(bad)),
        throwsFormatException,
        reason: bad,
      );
    }
  });
}
