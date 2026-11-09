import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:secure_vault/core/password_import.dart';

// Synthetic data only.
ImportResult _p(String s) => PasswordImport.parse(utf8.encode(s));

void main() {
  test('Chrome-style CSV', () {
    final r = _p(
      'name,url,username,password,note\n'
      'Demo,https://demo.example,alice,pw-1,hello\n',
    );
    expect(r.logins.single.name, 'Demo');
    expect(r.logins.single.username, 'alice');
    expect(r.logins.single.password, 'pw-1');
    expect(r.logins.single.notes, 'hello');
  });

  test('quotes, commas, doubled quotes, embedded newlines, CRLF, BOM', () {
    final r = _p(
      '﻿name,url,username,password,note\r\n'
      '"A, B",x.example,u,"p""w","line1\nline2"\r\n'
      'C,,u2,pw2,\r\n',
    );
    expect(r.logins.length, 2);
    expect(r.logins[0].name, 'A, B');
    expect(r.logins[0].password, 'p"w');
    expect(r.logins[0].notes, 'line1\nline2');
    expect(r.logins[1].name, 'C');
  });

  test('Bitwarden CSV skips non-login types and keeps totp', () {
    final r = _p(
      'folder,favorite,type,name,notes,fields,reprompt,login_uri,login_username,login_password,login_totp\n'
      ',0,login,Site,,,0,https://s.example,bob,pw,otpauth://totp/x\n'
      ',0,note,Secret note,text,,0,,,,\n'
      ',0,card,Card,,,0,,,,\n',
    );
    expect(r.source, 'Bitwarden (CSV)');
    expect(r.logins.single.totp, 'otpauth://totp/x');
    expect(r.skipped, 2);
  });

  test('Bitwarden JSON; encrypted JSON is refused', () {
    final r = _p(
      jsonEncode({
        'encrypted': false,
        'items': [
          {
            'type': 1,
            'name': 'J',
            'notes': 'n',
            'login': {
              'username': 'u',
              'password': 'p',
              'uris': [
                {'uri': 'https://j.example'},
              ],
            },
          },
          {'type': 3, 'name': 'card'},
        ],
      }),
    );
    expect(r.logins.single.url, 'https://j.example');
    expect(r.skipped, 1);
    expect(
      () => _p('{"encrypted":true,"items":[]}'),
      throwsA(isA<ImportException>()),
    );
  });

  test('blank name falls back to host; empty rows ignored', () {
    final r = _p('url,username,password\nhttps://h.example/x,u,p\n,,\n');
    expect(r.logins.single.name, 'h.example');
  });

  test('unrecognised, empty, binary and oversized input is rejected', () {
    for (final bad in ['a,b\n1,2\n', '', 'only header\n']) {
      expect(() => _p(bad), throwsA(isA<ImportException>()), reason: bad);
    }
    expect(
      () => PasswordImport.parse([0xff, 0xfe, 0x00]),
      throwsA(isA<ImportException>()),
    );
    expect(
      () => PasswordImport.parse(List.filled(11 * 1024 * 1024, 97)),
      throwsA(isA<ImportException>()),
    );
  });
}
