import 'dart:convert';

/// One field in a QR transfer.
class QrField {
  const QrField(this.label, this.value, {this.sensitive = false});
  final String label;
  final String value;
  final bool sensitive;
}

/// The plaintext carried (encrypted) inside a QR transfer. Deliberately
/// generic: the receiver imports every field as a custom field so nothing
/// depends on the sender and receiver sharing the same category schema.
class QrRecord {
  const QrRecord({required this.title, required this.fields, this.notes = ''});
  final String title;
  final List<QrField> fields;
  final String notes;

  static const int maxFields = 30;
  static const int maxText = 600;

  List<int> encode() => utf8.encode(
    jsonEncode({
      'v': 1,
      't': title,
      'f': [
        for (final f in fields)
          {'l': f.label, 'v': f.value, if (f.sensitive) 's': true},
      ],
      if (notes.isNotEmpty) 'n': notes,
    }),
  );

  /// Parses and strictly validates untrusted bytes. Throws [FormatException].
  factory QrRecord.decode(List<int> bytes) {
    String str(Object? v, {bool allowEmpty = true}) {
      if (v is! String || v.length > maxText || (!allowEmpty && v.isEmpty)) {
        throw const FormatException('Invalid transfer content');
      }
      return v;
    }

    final Object? j;
    try {
      j = jsonDecode(utf8.decode(bytes));
    } on Object {
      throw const FormatException('Invalid transfer content');
    }
    if (j is! Map || j['v'] != 1 || j['f'] is! List) {
      throw const FormatException('Unsupported transfer content');
    }
    final raw = j['f'] as List;
    if (raw.length > maxFields) {
      throw const FormatException('Invalid transfer content');
    }
    return QrRecord(
      title: str(j['t'], allowEmpty: false),
      notes: j['n'] == null ? '' : str(j['n']),
      fields: [
        for (final e in raw)
          if (e is Map)
            QrField(
              str(e['l'], allowEmpty: false),
              str(e['v']),
              sensitive: e['s'] == true,
            )
          else
            throw const FormatException('Invalid transfer content'),
      ],
    );
  }
}
