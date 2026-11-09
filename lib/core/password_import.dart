import 'dart:convert';

/// One login read from another password manager's export. Lives in memory only.
class ImportedLogin {
  const ImportedLogin({
    required this.name,
    this.url = '',
    this.username = '',
    this.password = '',
    this.notes = '',
    this.totp = '',
  });
  final String name;
  final String url;
  final String username;
  final String password;
  final String notes;

  /// One-time-password secret or otpauth URI, if the export had one.
  final String totp;
}

class ImportResult {
  const ImportResult({
    required this.source,
    required this.logins,
    required this.skipped,
  });
  final String source;
  final List<ImportedLogin> logins;

  /// Entries that are not logins (cards, identities, empty rows).
  final int skipped;
}

class ImportException implements Exception {
  const ImportException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Parses plaintext exports from common password managers (Bitwarden JSON and
/// CSV, 1Password CSV, Chrome/Edge/Firefox CSV, LastPass CSV, or any CSV with
/// recognisable column names). Pure and in-memory: it never touches disk and
/// never logs content. Input is untrusted, so size and row counts are capped.
class PasswordImport {
  PasswordImport._();

  static const int maxBytes = 10 * 1024 * 1024;
  static const int maxRows = 10000;
  static const int maxField = 20000;

  static ImportResult parse(List<int> bytes) {
    if (bytes.isEmpty) throw const ImportException('The file is empty.');
    if (bytes.length > maxBytes) {
      throw const ImportException('The file is too large (limit 10 MB).');
    }
    final String text;
    try {
      text = utf8.decode(bytes);
    } on FormatException {
      throw const ImportException('The file is not UTF-8 text.');
    }
    final t = text.startsWith('﻿') ? text.substring(1) : text;
    if (t.trimLeft().startsWith('{')) return _bitwarden(t);
    return _csv(t);
  }

  // ---- Bitwarden JSON ------------------------------------------------------

  static ImportResult _bitwarden(String text) {
    final Object? j;
    try {
      j = jsonDecode(text);
    } on FormatException {
      throw const ImportException('The file is not valid JSON.');
    }
    if (j is! Map) throw const ImportException('Unrecognised JSON export.');
    if (j['encrypted'] == true) {
      throw const ImportException(
        'This is an encrypted export. Export it unencrypted from the other app, or use its CSV export.',
      );
    }
    final items = j['items'];
    if (items is! List) {
      throw const ImportException('Unrecognised JSON export.');
    }
    if (items.length > maxRows) {
      throw const ImportException('Too many entries (limit 10,000).');
    }
    final out = <ImportedLogin>[];
    var skipped = 0;
    String s(Object? v) {
      final x = v is String ? v : '';
      return x.length > maxField ? x.substring(0, maxField) : x;
    }

    for (final it in items) {
      if (it is! Map || it['type'] != 1 || it['login'] is! Map) {
        skipped++;
        continue;
      }
      final l = it['login'] as Map;
      final uris = l['uris'];
      final url = uris is List && uris.isNotEmpty && uris.first is Map
          ? s((uris.first as Map)['uri'])
          : '';
      final login = ImportedLogin(
        name: s(it['name']),
        url: url,
        username: s(l['username']),
        password: s(l['password']),
        notes: s(it['notes']),
        totp: s(l['totp']),
      );
      _add(out, login) ? null : skipped++;
    }
    return ImportResult(
      source: 'Bitwarden (JSON)',
      logins: out,
      skipped: skipped,
    );
  }

  // ---- CSV -----------------------------------------------------------------

  static const _nameCols = ['name', 'title', 'account', 'site name'];
  static const _urlCols = [
    'url',
    'login_uri',
    'website',
    'web site',
    'login url',
    'uri',
  ];
  static const _userCols = [
    'username',
    'login_username',
    'login',
    'user',
    'login name',
    'email',
  ];
  static const _passCols = ['password', 'login_password', 'pass'];
  static const _noteCols = ['notes', 'note', 'extra', 'comments', 'comment'];
  static const _totpCols = ['totp', 'login_totp', 'otpauth', 'otp'];

  static ImportResult _csv(String text) {
    final rows = parseCsv(text);
    if (rows.length < 2) {
      throw const ImportException('No entries found in the file.');
    }
    if (rows.length - 1 > maxRows) {
      throw const ImportException('Too many entries (limit 10,000).');
    }
    final header = [for (final h in rows.first) h.trim().toLowerCase()];
    int? col(List<String> names) {
      for (final n in names) {
        final i = header.indexOf(n);
        if (i >= 0) return i;
      }
      return null;
    }

    final cName = col(_nameCols),
        cUrl = col(_urlCols),
        cUser = col(_userCols),
        cPass = col(_passCols),
        cNote = col(_noteCols),
        cTotp = col(_totpCols),
        cType = header.indexOf('type');
    if (cPass == null || (cName == null && cUrl == null)) {
      throw const ImportException(
        'Could not recognise this CSV. It needs at least password and name or url columns.',
      );
    }
    String at(List<String> r, int? i) {
      if (i == null || i < 0 || i >= r.length) return '';
      final v = r[i];
      return v.length > maxField ? v.substring(0, maxField) : v;
    }

    final out = <ImportedLogin>[];
    var skipped = 0;
    for (final r in rows.skip(1)) {
      if (r.every((c) => c.trim().isEmpty)) continue;
      // Bitwarden/1Password mark non-login rows with a type column.
      if (cType >= 0) {
        final t = at(r, cType).trim().toLowerCase();
        if (t.isNotEmpty && t != 'login') {
          skipped++;
          continue;
        }
      }
      final login = ImportedLogin(
        name: at(r, cName),
        url: at(r, cUrl),
        username: at(r, cUser),
        password: at(r, cPass),
        notes: at(r, cNote),
        totp: at(r, cTotp),
      );
      _add(out, login) ? null : skipped++;
    }
    return ImportResult(
      source: header.contains('login_uri')
          ? 'Bitwarden (CSV)'
          : header.contains('grouping')
          ? 'LastPass (CSV)'
          : header.contains('otpauth') || header.contains('type')
          ? '1Password (CSV)'
          : 'CSV',
      logins: out,
      skipped: skipped,
    );
  }

  /// Adds [l] with a derived name when blank; rejects fully empty entries.
  static bool _add(List<ImportedLogin> out, ImportedLogin l) {
    if (l.password.isEmpty && l.username.isEmpty && l.url.isEmpty) {
      return false;
    }
    var name = l.name.trim();
    if (name.isEmpty) name = hostOf(l.url) ?? l.username;
    if (name.isEmpty) name = 'Imported login';
    out.add(
      ImportedLogin(
        name: name,
        url: l.url.trim(),
        username: l.username,
        password: l.password,
        notes: l.notes,
        totp: l.totp,
      ),
    );
    return true;
  }

  static String? hostOf(String url) {
    final u = Uri.tryParse(url.contains('://') ? url : 'https://$url');
    final h = u?.host ?? '';
    return h.isEmpty ? null : h;
  }

  /// RFC 4180 CSV: quoted fields, doubled quotes, embedded newlines, CRLF/LF.
  static List<List<String>> parseCsv(String text) {
    final rows = <List<String>>[];
    var row = <String>[];
    final f = StringBuffer();
    var inQuotes = false;
    var fieldStarted = false;

    void endField() {
      row.add(f.toString());
      f.clear();
      fieldStarted = false;
    }

    void endRow() {
      endField();
      rows.add(row);
      row = <String>[];
    }

    for (var i = 0; i < text.length; i++) {
      final ch = text[i];
      if (inQuotes) {
        if (ch == '"') {
          if (i + 1 < text.length && text[i + 1] == '"') {
            f.write('"');
            i++;
          } else {
            inQuotes = false;
          }
        } else {
          f.write(ch);
        }
      } else if (ch == '"' && !fieldStarted) {
        inQuotes = true;
        fieldStarted = true;
      } else if (ch == ',') {
        endField();
      } else if (ch == '\n' || ch == '\r') {
        if (ch == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
        endRow();
      } else {
        f.write(ch);
        fieldStarted = true;
      }
    }
    if (f.isNotEmpty || fieldStarted || row.isNotEmpty) endRow();
    return rows;
  }
}
