import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secure_vault/application/providers.dart';
import 'package:secure_vault/core/crypto/vault_crypto.dart';
import 'package:secure_vault/core/password_tools.dart';
import 'package:secure_vault/core/validators.dart';
import 'package:secure_vault/data/vault_repository.dart';
import 'package:secure_vault/domain/builtin_categories.dart';
import 'package:secure_vault/domain/category.dart';
import 'package:secure_vault/domain/credential.dart';
import 'package:secure_vault/domain/vault_data.dart';
import 'package:secure_vault/domain/field_def.dart';
import 'package:shared_preferences/shared_preferences.dart';

KdfParams _fast() => KdfParams.fresh(memoryKiB: 64, iterations: 1);

Credential _c(
  String id,
  String title, {
  String category = 'website',
  Map<String, String>? values,
  List<String>? tags,
}) => Credential(
  id: id,
  categoryId: category,
  title: title,
  values:
      values ??
      {'username': 'alice@example.test', 'password': 'Zq9!synthetic-Only'},
  tags: tags,
  createdAt: DateTime(2026, 1, 1),
  updatedAt: DateTime(2026, 1, 1),
);

void main() {
  group('Validators', () {
    test('IPv4', () {
      expect(Validators.isIPv4('192.168.1.10'), isTrue);
      expect(Validators.isIPv4('256.1.1.1'), isFalse);
      expect(Validators.isIPv4('1.2.3'), isFalse);
      expect(Validators.isIPv4('a.b.c.d'), isFalse);
    });
    test('IPv6', () {
      expect(Validators.isIPv6('fd00::1'), isTrue);
      expect(Validators.isIPv6('2001:db8::8a2e:370:7334'), isTrue);
      expect(Validators.isIPv6('12345::1'), isFalse);
      expect(Validators.isIPv6('192.168.1.1'), isFalse);
    });
    test('subnet masks and prefixes', () {
      expect(Validators.isSubnet('255.255.255.0'), isTrue);
      expect(Validators.isSubnet('255.255.254.0'), isTrue);
      expect(Validators.isSubnet('255.0.255.0'), isFalse);
      expect(Validators.isSubnet('24'), isTrue);
      expect(Validators.isSubnet('/64'), isTrue);
      expect(Validators.isSubnet('192.168.1.0/24'), isTrue);
      expect(Validators.isSubnet('10.0.0.0/33'), isFalse);
      expect(Validators.isSubnet('fd00::/64'), isTrue);
      expect(Validators.isSubnet('fd00::/129'), isFalse);
      expect(Validators.isSubnet('abc'), isFalse);
    });
    test('field validation by type and required', () {
      const ip = FieldDef(
        key: 'ip',
        label: 'IP',
        type: FieldType.ip,
        required: true,
      );
      expect(Validators.validate(ip, ''), 'IP is required');
      expect(Validators.validate(ip, '10.0.0.1'), isNull);
      expect(Validators.validate(ip, '10.0.0'), isNotNull);
      const port = FieldDef(key: 'p', label: 'Port', type: FieldType.port);
      expect(Validators.validate(port, '0'), isNotNull);
      expect(Validators.validate(port, '65535'), isNull);
      expect(Validators.validate(port, '65536'), isNotNull);
      const mac = FieldDef(key: 'm', label: 'MAC', type: FieldType.mac);
      expect(Validators.validate(mac, 'AA:BB:CC:DD:EE:FF'), isNull);
      expect(Validators.validate(mac, 'AA:BB:CC'), isNotNull);
      const email = FieldDef(key: 'e', label: 'Email', type: FieldType.email);
      expect(Validators.validate(email, 'not-an-email'), isNotNull);
      expect(Validators.validate(email, 'a@b.test'), isNull);
    });
    test('static IP category requires name and IP', () {
      final cat = builtInCategories.firstWhere((c) => c.id == 'static_ip');
      expect(
        cat.fields.where((f) => f.required).map((f) => f.key),
        containsAll(['device', 'ip']),
      );
    });
    test('no built-in secret field is used as a list subtitle', () {
      for (final cat in builtInCategories) {
        if (cat.subtitleKey == null) continue;
        final f = cat.fields.firstWhere((f) => f.key == cat.subtitleKey);
        expect(f.sensitive, isFalse, reason: cat.id);
      }
    });
  });

  group('PasswordTools', () {
    test('generator honours length and classes', () {
      final p = PasswordTools.generate(length: 24);
      expect(p.length, 24);
      expect(RegExp('[a-z]').hasMatch(p), isTrue);
      expect(RegExp('[A-Z]').hasMatch(p), isTrue);
      expect(RegExp(r'\d').hasMatch(p), isTrue);
      expect(RegExp(r'[^A-Za-z0-9]').hasMatch(p), isTrue);
      final digitsOnly = PasswordTools.generate(
        length: 12,
        lower: false,
        upper: false,
        symbols: false,
      );
      expect(RegExp(r'^\d{12}$').hasMatch(digitsOnly), isTrue);
    });
    test('strength grading', () {
      expect(PasswordTools.isWeak('password'), isTrue);
      expect(PasswordTools.isWeak('aaaaaaaa'), isTrue);
      expect(
        PasswordTools.strength('correct-Horse-battery-9!staple').index,
        greaterThanOrEqualTo(Strength.strong.index),
      );
    });
  });

  group('Vault controller flow', () {
    late Directory dir;
    late ProviderContainer container;

    VaultController ctl() => container.read(vaultProvider.notifier);

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      dir = await Directory.systemTemp.createTemp('sv_flow');
      container = ProviderContainer(
        overrides: [
          sharedPrefsProvider.overrideWithValue(prefs),
          vaultDirProvider.overrideWithValue(dir),
          repositoryProvider.overrideWith(
            (ref) => VaultRepository(dir, kdfFactory: _fast),
          ),
        ],
      );
      await ctl().init();
    });

    tearDown(() async {
      container.dispose();
      await dir.delete(recursive: true);
    });

    test('first launch has no vault; create then lock/unlock', () async {
      expect(container.read(vaultProvider).status, VaultStatus.noVault);
      await ctl().createVault('synthetic master 1');
      expect(container.read(vaultProvider).status, VaultStatus.unlocked);
      await ctl().saveCredential(_c('1', 'Mail'));
      ctl().lock();
      expect(container.read(vaultProvider).status, VaultStatus.locked);
      expect(container.read(vaultProvider).data, isNull); // cleared from memory
      expect(await ctl().unlock('synthetic master 1'), UnlockResult.ok);
      expect(
        container.read(vaultProvider).data!.credentials.single.title,
        'Mail',
      );
    });

    test('data persists across a fresh app start', () async {
      await ctl().createVault('synthetic master 1');
      await ctl().saveCredential(_c('1', 'Persisted'));
      container.invalidate(vaultProvider);
      await ctl().init();
      expect(container.read(vaultProvider).status, VaultStatus.locked);
      await ctl().unlock('synthetic master 1');
      expect(
        container.read(vaultProvider).data!.credentials.single.title,
        'Persisted',
      );
    });

    test(
      'wrong password rate-limits after 3 failures and persists lockout',
      () async {
        await ctl().createVault('synthetic master 1');
        ctl().lock();
        for (var i = 0; i < 2; i++) {
          expect(await ctl().unlock('bad'), UnlockResult.wrongPassword);
          expect(ctl().lockoutRemaining(), isNull);
        }
        expect(await ctl().unlock('bad'), UnlockResult.wrongPassword);
        expect(ctl().lockoutRemaining(), isNotNull);
        // Even the correct password is refused while locked out.
        expect(
          await ctl().unlock('synthetic master 1'),
          UnlockResult.lockedOut,
        );
        // Counter survives restart.
        container.invalidate(vaultProvider);
        await ctl().init();
        expect(container.read(vaultProvider).failedAttempts, 3);
        expect(ctl().lockoutRemaining(), isNotNull);
      },
    );

    test('favorite, soft delete, restore, delete forever', () async {
      await ctl().createVault('synthetic master 1');
      await ctl().saveCredential(_c('1', 'A'));
      await ctl().toggleFavorite('1');
      expect(
        container.read(visibleCredentialsProvider).single.isFavorite,
        isTrue,
      );
      await ctl().softDelete('1');
      expect(container.read(visibleCredentialsProvider), isEmpty);
      expect(container.read(deletedCredentialsProvider).length, 1);
      await ctl().restore('1');
      expect(container.read(visibleCredentialsProvider).length, 1);
      await ctl().softDelete('1');
      await ctl().deleteForever('1');
      expect(container.read(deletedCredentialsProvider), isEmpty);
    });

    test('deleted items past retention are purged on unlock', () async {
      await ctl().createVault('synthetic master 1');
      await ctl().saveCredential(
        _c('1', 'Old').copyWith(
          deletedAt: DateTime.now().subtract(const Duration(days: 31)),
        ),
      );
      ctl().lock();
      await ctl().unlock('synthetic master 1');
      expect(container.read(vaultProvider).data!.credentials, isEmpty);
    });

    test(
      'search covers title, tags, username, category; never secrets',
      () async {
        await ctl().createVault('synthetic master 1');
        await ctl().saveCredential(_c('1', 'GitHub', tags: ['work']));
        final data = container.read(vaultProvider).data!;
        final c = data.credentials.single;
        expect(matchesQuery(c, data, 'github'), isTrue);
        expect(matchesQuery(c, data, 'WORK'), isTrue);
        expect(matchesQuery(c, data, 'alice@'), isTrue);
        expect(matchesQuery(c, data, 'website login'), isTrue);
        expect(matchesQuery(c, data, 'synthetic-only'), isFalse); // password
        expect(matchesQuery(c, data, 'zzz'), isFalse);
      },
    );

    test('sorting', () {
      final a = _c('1', 'beta').copyWith(updatedAt: DateTime(2026, 1, 2));
      final b = _c('2', 'Alpha').copyWith(updatedAt: DateTime(2026, 1, 3));
      expect(sortCredentials([a, b], SortMode.name).first.title, 'Alpha');
      expect(sortCredentials([a, b], SortMode.updated).first.title, 'Alpha');
    });

    test(
      'duplicate detection by title or identifier, ignoring deleted',
      () async {
        await ctl().createVault('synthetic master 1');
        await ctl().saveCredential(
          _c(
            '1',
            'Work mail',
            category: 'email',
            values: {'address': 'me@example.test'},
          ),
        );
        final data = container.read(vaultProvider).data!;
        expect(
          findDuplicate(
            data,
            _c('2', 'work MAIL', category: 'email', values: {}),
          ),
          isNotNull,
        );
        expect(
          findDuplicate(
            data,
            _c(
              '2',
              'Other',
              category: 'email',
              values: {'address': 'ME@example.test'},
            ),
          ),
          isNotNull,
        );
        expect(
          findDuplicate(data, _c('1', 'Work mail', category: 'email')),
          isNull,
        ); // itself
        expect(
          findDuplicate(data, _c('3', 'Work mail', category: 'website')),
          isNull,
        );
      },
    );

    test('custom category with sensitive field round-trips', () async {
      await ctl().createVault('synthetic master 1');
      await ctl().saveCategory(
        const Category(
          id: 'c_1',
          name: 'Licences',
          iconKey: 'key',
          colorKey: 'red',
          fields: [
            FieldDef(
              key: 'f_key',
              label: 'Key',
              type: FieldType.password,
              sensitive: true,
            ),
          ],
        ),
      );
      ctl().lock();
      await ctl().unlock('synthetic master 1');
      final cats = container.read(vaultProvider).data!.customCategories;
      expect(cats.single.name, 'Licences');
      expect(cats.single.fields.single.sensitive, isTrue);
      // Category in use cannot be deleted.
      await ctl().saveCredential(_c('1', 'L', category: 'c_1', values: {}));
      expect(await ctl().deleteCategory('c_1'), isFalse);
    });

    test('security report counts weak and reused only', () async {
      await ctl().createVault('synthetic master 1');
      await ctl().saveCredential(
        _c('1', 'A', values: {'password': '12345678'}),
      );
      await ctl().saveCredential(
        _c('2', 'B', values: {'password': '12345678'}),
      );
      await ctl().saveCredential(
        _c('3', 'C', values: {'password': 'Xk3!vQ8#mZ2@pL9'}),
      );
      final r = buildSecurityReport(container.read(vaultProvider).data!);
      expect(r.weak, 2);
      expect(r.reused, 2);
    });

    test('replaceWithBackup swaps data and persists it', () async {
      await ctl().createVault('synthetic master 1');
      await ctl().saveCredential(_c('1', 'Current'));
      await ctl().replaceWithBackup(
        VaultData(credentials: [_c('9', 'FromBackup')]),
      );
      ctl().lock();
      await ctl().unlock('synthetic master 1');
      expect(
        container.read(vaultProvider).data!.credentials.single.title,
        'FromBackup',
      );
    });
  });
}
