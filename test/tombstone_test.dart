import 'package:flutter_test/flutter_test.dart';
import 'package:secure_vault/core/crypto/vault_crypto.dart';
import 'package:secure_vault/domain/vault_data.dart';

void main() {
  test('tombstones round-trip through the vault JSON', () {
    final d = VaultData(tombstones: {'a': DateTime.utc(2030, 1, 2, 3)});
    final back = VaultData.fromJson(d.toJson());
    expect(back.tombstones['a'], DateTime.utc(2030, 1, 2, 3));
    expect(d.toJson()['schema'], 2);
  });

  test('a schema 1 vault loads with no tombstones and upgrades to 2', () {
    final d = VaultData.fromJson({
      'schema': 1,
      'categories': [],
      'credentials': [],
    });
    expect(d.tombstones, isEmpty);
    expect(d.toJson()['schema'], 2);
    expect(d.toJson().containsKey('tombstones'), isFalse);
  });

  test('KDF parameters from the cloud are bounded', () {
    KdfParams p(int m, int t, int par, int salt) => KdfParams(
      memoryKiB: m,
      iterations: t,
      parallelism: par,
      salt: List.filled(salt, 1),
    );
    expect(p(65536, 3, 1, 16).withinSafeLimits, isTrue);
    expect(p(4000000, 3, 1, 16).withinSafeLimits, isFalse); // memory bomb
    expect(p(65536, 500, 1, 16).withinSafeLimits, isFalse); // time bomb
    expect(p(64, 1, 1, 16).withinSafeLimits, isFalse); // too weak
    expect(p(65536, 3, 1, 4).withinSafeLimits, isFalse); // short salt
  });
}
