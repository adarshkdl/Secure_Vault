import 'package:flutter_test/flutter_test.dart';
import 'package:secure_vault/application/import_mapper.dart';
import 'package:secure_vault/core/password_import.dart';
import 'package:secure_vault/domain/credential.dart';
import 'package:secure_vault/domain/vault_data.dart';

void main() {
  final t = DateTime(2030);
  const a = ImportedLogin(name: 'Demo', username: 'Alice', password: 'pw-a');

  test('duplicates of existing and in-file entries are skipped', () {
    final data = VaultData(
      credentials: [
        Credential(
          id: '1',
          categoryId: 'website',
          title: 'demo',
          values: {'username': 'alice'},
          createdAt: t,
          updatedAt: t,
        ),
        Credential(
          id: '2',
          categoryId: 'website',
          title: 'Gone',
          values: {'username': 'x'},
          createdAt: t,
          updatedAt: t,
          deletedAt: t,
        ),
      ],
    );
    const b = ImportedLogin(name: 'Gone', username: 'x', password: 'p');
    final plan = planImport(data, [a, b, b]);
    expect(plan.duplicates.length, 2); // a (existing) and second b (in file)
    expect(plan.toAdd.single.name, 'Gone');
  });

  test('credentials map into the website category with a totp secret', () {
    var n = 0;
    final out = toCredentials(
      [
        const ImportedLogin(
          name: 'Site',
          url: 'https://s.example',
          username: 'u',
          password: 'p',
          notes: 'n',
          totp: 'SYNTHETICSECRET',
        ),
      ],
      newId: () => 'id${n++}',
      now: t,
    );
    final c = out.single;
    expect(c.categoryId, 'website');
    expect(c.values['service'], 'Site');
    expect(c.values['password'], 'p');
    expect(c.tags, ['imported']);
    expect(c.extraFields.single.sensitive, isTrue);
    expect(c.values['totp'], 'SYNTHETICSECRET');
  });
}
