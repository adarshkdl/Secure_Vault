import 'package:flutter_test/flutter_test.dart';
import 'package:secure_vault/application/expiry.dart';
import 'package:secure_vault/domain/credential.dart';
import 'package:secure_vault/domain/field_def.dart';
import 'package:secure_vault/domain/vault_data.dart';

Credential _c(
  String id,
  String? date, {
  DateTime? deleted,
  String key = 'expiry',
  String catId = 'account',
  List<FieldDef> extras = const [],
}) {
  final t = DateTime(2030);
  return Credential(
    id: id,
    categoryId: catId,
    title: 'Item $id',
    values: {key: ?date, 'password': 'synthetic-pw'},
    extraFields: extras,
    createdAt: t,
    updatedAt: t,
    deletedAt: deleted,
  );
}

void main() {
  final now = DateTime(2030, 6, 15, 18, 30);

  test('classifies overdue, today, upcoming; sorts soonest first', () {
    final data = VaultData(
      credentials: [
        _c('later', '2030-07-10'),
        _c('overdue', '2030-06-01'),
        _c('today', '2030-06-15'),
        _c('far', '2031-01-01'),
        _c('none', null),
        _c('bad', 'not-a-date'),
      ],
    );
    final r = buildExpiryReport(data, leadDays: 30, now: now);
    expect(r.items.map((i) => i.credential.id), ['overdue', 'today', 'later']);
    expect(r.items.map((i) => i.daysLeft), [-14, 0, 25]);
    expect(r.overdue, 1);
    expect(r.upcoming, 2);
  });

  test('deleted records, disabled setting and window are respected', () {
    final data = VaultData(
      credentials: [
        _c('gone', '2030-06-16', deleted: now),
        _c('soon', '2030-06-20'),
      ],
    );
    expect(buildExpiryReport(data, leadDays: 0, now: now).isEmpty, isTrue);
    expect(buildExpiryReport(data, leadDays: 3, now: now).isEmpty, isTrue);
    final r = buildExpiryReport(data, leadDays: 7, now: now);
    expect(r.items.single.credential.id, 'soon');
  });

  test('custom date fields on a record are included', () {
    final data = VaultData(
      credentials: [
        _c(
          'x',
          '2030-06-16',
          key: 'qr_0',
          extras: const [
            FieldDef(key: 'qr_0', label: 'Renews', type: FieldType.date),
          ],
        ),
      ],
    );
    final r = buildExpiryReport(data, leadDays: 7, now: now);
    expect(r.items.single.fieldLabel, 'Renews');
    expect(r.items.single.daysLeft, 1);
  });

  test('wording', () {
    expect(describeDays(0), 'today');
    expect(describeDays(1), 'tomorrow');
    expect(describeDays(5), 'in 5 days');
    expect(describeDays(-3), '3 days ago');
  });
}
