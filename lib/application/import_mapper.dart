import '../core/password_import.dart';
import '../domain/credential.dart';
import '../domain/field_def.dart';
import '../domain/vault_data.dart';

class ImportPlan {
  const ImportPlan(this.toAdd, this.duplicates);
  final List<ImportedLogin> toAdd;

  /// Entries already in the vault (same title and username); never overwritten.
  final List<ImportedLogin> duplicates;
}

String _k(String s) => s.trim().toLowerCase();

/// Splits [logins] into new entries and ones that look like existing website
/// logins (same title and username). Also drops repeats within the file.
ImportPlan planImport(VaultData data, List<ImportedLogin> logins) {
  final seen = <String>{
    for (final c in data.credentials)
      if (!c.isDeleted && c.categoryId == 'website')
        '${_k(c.title)}\u0000${_k(c.values['username'] ?? '')}',
  };
  final add = <ImportedLogin>[], dup = <ImportedLogin>[];
  for (final l in logins) {
    final key = '${_k(l.name)}\u0000${_k(l.username)}';
    if (seen.add(key)) {
      add.add(l);
    } else {
      dup.add(l);
    }
  }
  return ImportPlan(add, dup);
}

/// Converts imported logins into Website-login records. Passwords stay in the
/// password field and a TOTP secret becomes a sensitive custom field.
List<Credential> toCredentials(
  List<ImportedLogin> logins, {
  required String Function() newId,
  DateTime? now,
}) {
  final t = now ?? DateTime.now();
  return [
    for (final l in logins)
      Credential(
        id: newId(),
        categoryId: 'website',
        title: l.name,
        values: {
          'service': l.name,
          if (l.url.isNotEmpty) 'url': l.url,
          if (l.username.isNotEmpty) 'username': l.username,
          if (l.password.isNotEmpty) 'password': l.password,
          if (l.totp.isNotEmpty) 'totp': l.totp,
        },
        extraFields: [
          if (l.totp.isNotEmpty)
            const FieldDef(
              key: 'totp',
              label: 'One-time password secret',
              type: FieldType.password,
              sensitive: true,
            ),
        ],
        notes: l.notes,
        tags: const ['imported'],
        createdAt: t,
        updatedAt: t,
      ),
  ];
}
