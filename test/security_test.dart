import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:secure_vault/core/crypto/vault_crypto.dart';
import 'package:secure_vault/core/lockout.dart';
import 'package:secure_vault/data/backup_service.dart';
import 'package:secure_vault/data/vault_repository.dart';
import 'package:secure_vault/domain/credential.dart';
import 'package:secure_vault/domain/vault_data.dart';

// Cheap KDF so tests are fast. Production defaults are in KdfParams.
KdfParams _fastKdf() =>
    KdfParams.fresh(memoryKiB: 64, iterations: 1, parallelism: 1);

Credential _cred(String id, {String title = 'Synthetic mail'}) => Credential(
  id: id,
  categoryId: 'email',
  title: title,
  values: {'address': 'user@example.test', 'password': 'Synthetic-Pass-123!'},
  createdAt: DateTime(2026, 1, 1),
  updatedAt: DateTime(2026, 1, 1),
);

void main() {
  group('VaultCrypto', () {
    test('seal/open round-trip', () async {
      final key = VaultCrypto.newKey();
      final s = await VaultCrypto.seal(utf8.encode('hello'), key);
      expect(utf8.decode(await VaultCrypto.open(s, key)), 'hello');
    });

    test('nonces are unique per message', () async {
      final key = VaultCrypto.newKey();
      final a = await VaultCrypto.seal([1, 2, 3], key);
      final b = await VaultCrypto.seal([1, 2, 3], key);
      expect(a.nonce, isNot(b.nonce));
      expect(a.cipherText, isNot(b.cipherText));
    });

    test('tampered ciphertext is rejected', () async {
      final key = VaultCrypto.newKey();
      final s = await VaultCrypto.seal(utf8.encode('secret'), key);
      final ct = List<int>.of(s.cipherText)..[0] ^= 1;
      expect(
        () => VaultCrypto.open(Sealed(s.nonce, ct, s.mac), key),
        throwsA(isA<DecryptionFailure>()),
      );
    });

    test('wrong AAD is rejected', () async {
      final key = VaultCrypto.newKey();
      final s = await VaultCrypto.seal([1], key, aad: [1]);
      expect(
        () => VaultCrypto.open(s, key, aad: [2]),
        throwsA(isA<DecryptionFailure>()),
      );
    });

    test(
      'Argon2id is deterministic for same salt, differs by password',
      () async {
        final p = _fastKdf();
        final a = await VaultCrypto.deriveKey('pw-one', p);
        final b = await VaultCrypto.deriveKey('pw-one', p);
        final c = await VaultCrypto.deriveKey('pw-two', p);
        expect(a, b);
        expect(a, isNot(c));
        expect(a.length, 32);
      },
    );
  });

  group('VaultRepository', () {
    late Directory dir;
    late VaultRepository repo;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('sv_test');
      repo = VaultRepository(dir, kdfFactory: _fastKdf);
    });
    tearDown(() => dir.delete(recursive: true));

    test('create, save, unlock restores data', () async {
      final (s, data) = await repo.create('correct horse battery');
      data.credentials.add(_cred('1'));
      await repo.save(s, data);
      final (_, loaded) = await repo.unlock('correct horse battery');
      expect(
        loaded.credentials.single.values['password'],
        'Synthetic-Pass-123!',
      );
    });

    test('wrong master password fails', () async {
      await repo.create('correct horse battery');
      expect(
        () => repo.unlock('wrong password!!'),
        throwsA(isA<DecryptionFailure>()),
      );
    });

    test('no plaintext (titles, secrets) on disk', () async {
      final (s, data) = await repo.create('correct horse battery');
      data.credentials.add(_cred('1', title: 'UniqueTitleMarker'));
      await repo.save(s, data);
      final raw = await File('${dir.path}/vault.bin').readAsString();
      expect(raw.contains('UniqueTitleMarker'), isFalse);
      expect(raw.contains('Synthetic-Pass-123!'), isFalse);
      expect(raw.contains('user@example.test'), isFalse);
    });

    test('tampered vault file is rejected', () async {
      final (s, data) = await repo.create('correct horse battery');
      data.credentials.add(_cred('1'));
      await repo.save(s, data);
      final f = File('${dir.path}/vault.bin');
      final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      final ct = base64Decode((j['data'] as Map)['ct'] as String);
      ct[ct.length ~/ 2] ^= 0xff;
      (j['data'] as Map)['ct'] = base64Encode(ct);
      await f.writeAsString(jsonEncode(j));
      expect(
        () => repo.unlock('correct horse battery'),
        throwsA(isA<DecryptionFailure>()),
      );
    });

    test('change password keeps data, invalidates old password', () async {
      final (s, data) = await repo.create('old password 123');
      data.credentials.add(_cred('1'));
      await repo.save(s, data);
      await repo.changePassword(s, data, 'new password 456');
      expect(await repo.verifyPassword('old password 123'), isFalse);
      final (_, loaded) = await repo.unlock('new password 456');
      expect(loaded.credentials.length, 1);
    });

    test('unlockWithKey works for biometric path', () async {
      final (s, data) = await repo.create('correct horse battery');
      data.credentials.add(_cred('1'));
      await repo.save(s, data);
      final (_, loaded) = await repo.unlockWithKey(List<int>.of(s.dek));
      expect(loaded.credentials.length, 1);
    });

    test('rejects non-vault files', () async {
      await File('${dir.path}/vault.bin').writeAsString('{"hello":1}');
      expect(() => repo.unlock('x'), throwsA(isA<VaultFormatException>()));
    });
  });

  group('BackupService', () {
    final data = VaultData(credentials: [_cred('1'), _cred('2')]);

    test('round-trip with metadata', () async {
      final bytes = await BackupService.create(
        data,
        'backup-passphrase-1',
        kdf: _fastKdf(),
      );
      final h = BackupService.inspect(bytes);
      expect(h.recordCount, 2);
      expect(h.version, 1);
      final out = await BackupService.decrypt(bytes, 'backup-passphrase-1');
      expect(out.credentials.length, 2);
    });

    test('file contains no plaintext', () async {
      final bytes = await BackupService.create(
        data,
        'backup-passphrase-1',
        kdf: _fastKdf(),
      );
      final text = utf8.decode(bytes);
      expect(text.contains('Synthetic-Pass-123!'), isFalse);
      expect(text.contains('Synthetic mail'), isFalse);
    });

    test('wrong passphrase fails', () async {
      final bytes = await BackupService.create(
        data,
        'backup-passphrase-1',
        kdf: _fastKdf(),
      );
      expect(
        () => BackupService.decrypt(bytes, 'nope-nope-nope'),
        throwsA(isA<DecryptionFailure>()),
      );
    });

    test('tampered payload fails authentication', () async {
      final bytes = await BackupService.create(
        data,
        'backup-passphrase-1',
        kdf: _fastKdf(),
      );
      final j = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      final ct = base64Decode((j['payload'] as Map)['ct'] as String);
      ct[0] ^= 1;
      (j['payload'] as Map)['ct'] = base64Encode(ct);
      expect(
        () => BackupService.decrypt(
          Uint8List.fromList(utf8.encode(jsonEncode(j))),
          'backup-passphrase-1',
        ),
        throwsA(isA<DecryptionFailure>()),
      );
    });

    test('edited header metadata fails authentication', () async {
      final bytes = await BackupService.create(
        data,
        'backup-passphrase-1',
        kdf: _fastKdf(),
      );
      final j = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      j['records'] = 99;
      expect(
        () => BackupService.decrypt(
          Uint8List.fromList(utf8.encode(jsonEncode(j))),
          'backup-passphrase-1',
        ),
        throwsA(isA<DecryptionFailure>()),
      );
    });

    test('corrupt / truncated / foreign files are rejected', () {
      expect(
        () => BackupService.inspect(Uint8List(0)),
        throwsA(isA<BackupFormatException>()),
      );
      expect(
        () => BackupService.inspect(Uint8List.fromList(utf8.encode('{"a":'))),
        throwsA(isA<BackupFormatException>()),
      );
      expect(
        () => BackupService.inspect(
          Uint8List.fromList(utf8.encode('{"format":"x"}')),
        ),
        throwsA(isA<BackupFormatException>()),
      );
    });

    test('newer format version is rejected', () async {
      final bytes = await BackupService.create(
        data,
        'backup-passphrase-1',
        kdf: _fastKdf(),
      );
      final j = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      j['v'] = 99;
      expect(
        () => BackupService.inspect(
          Uint8List.fromList(utf8.encode(jsonEncode(j))),
        ),
        throwsA(isA<BackupFormatException>()),
      );
    });
  });

  group('Schema migration', () {
    test('rejects data from a newer schema', () {
      expect(
        () => VaultData.fromJson({'schema': 999}),
        throwsA(isA<FormatException>()),
      );
    });
    test('loads legacy payload without schema field', () {
      final d = VaultData.fromJson({'credentials': []});
      expect(d.credentials, isEmpty);
    });
  });

  group('LockoutPolicy', () {
    const p = LockoutPolicy();
    test('no delay for the first attempts', () {
      expect(p.delayFor(0), Duration.zero);
      expect(p.delayFor(2), Duration.zero);
    });
    test('delay grows exponentially and is capped', () {
      expect(p.delayFor(3), const Duration(seconds: 30));
      expect(p.delayFor(4), const Duration(seconds: 60));
      expect(p.delayFor(5), const Duration(seconds: 120));
      expect(p.delayFor(50), const Duration(hours: 1));
    });
    test('remaining time', () {
      final now = DateTime(2026, 1, 1, 12);
      expect(p.remaining(null, now), isNull);
      expect(
        p.remaining(now.subtract(const Duration(seconds: 1)), now),
        isNull,
      );
      expect(
        p.remaining(now.add(const Duration(seconds: 10)), now),
        const Duration(seconds: 10),
      );
    });
  });
}
