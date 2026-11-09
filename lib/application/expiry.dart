import '../domain/credential.dart';
import '../domain/field_def.dart';
import '../domain/vault_data.dart';

/// A date field (expiry / renewal / any date) that is overdue or coming up.
/// Holds only the record, the field label and the date - never secret values.
class ExpiryItem {
  const ExpiryItem(this.credential, this.fieldLabel, this.date, this.daysLeft);
  final Credential credential;
  final String fieldLabel;
  final DateTime date;

  /// Negative when overdue, 0 when due today.
  final int daysLeft;

  bool get isOverdue => daysLeft < 0;
}

class ExpiryReport {
  const ExpiryReport(this.items);
  final List<ExpiryItem> items;
  int get overdue => items.where((i) => i.isOverdue).length;
  int get upcoming => items.length - overdue;
  bool get isEmpty => items.isEmpty;
}

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// Finds every non-empty date field on non-deleted records that is overdue or
/// due within [leadDays]. [leadDays] <= 0 disables reminders. Runs in memory on
/// the unlocked vault only; nothing is scheduled, stored or sent anywhere.
ExpiryReport buildExpiryReport(
  VaultData data, {
  required int leadDays,
  DateTime? now,
}) {
  if (leadDays <= 0) return const ExpiryReport([]);
  final today = _dateOnly(now ?? DateTime.now());
  final out = <ExpiryItem>[];
  for (final c in data.credentials) {
    if (c.isDeleted) continue;
    final defs = [...?data.category(c.categoryId)?.fields, ...c.extraFields];
    for (final f in defs) {
      if (f.type != FieldType.date) continue;
      final raw = c.values[f.key]?.trim();
      if (raw == null || raw.isEmpty) continue;
      final d = DateTime.tryParse(raw);
      if (d == null) continue;
      final days = _dateOnly(d).difference(today).inDays;
      if (days <= leadDays) out.add(ExpiryItem(c, f.label, d, days));
    }
  }
  out.sort((a, b) => a.daysLeft.compareTo(b.daysLeft));
  return ExpiryReport(out);
}

/// Human wording for a day count, e.g. "in 3 days", "today", "5 days ago".
String describeDays(int days) {
  if (days == 0) return 'today';
  if (days == 1) return 'tomorrow';
  if (days == -1) return 'yesterday';
  return days > 0 ? 'in $days days' : '${-days} days ago';
}
