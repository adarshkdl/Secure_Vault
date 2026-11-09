enum FieldType {
  text('Short text'),
  longText('Long text'),
  email('Email'),
  url('URL'),
  phone('Phone'),
  username('Username'),
  password('Password / secret'),
  date('Date'),
  number('Number'),
  ip('IP address'),
  boolean('Yes / No'),
  // Built-in only (not offered for user-defined fields):
  choice('Choice'),
  port('Port'),
  subnet('Subnet mask / CIDR'),
  mac('MAC address'),
  // Several phone numbers in one field, stored newline-separated.
  phoneList('Phone numbers');

  const FieldType(this.label);
  final String label;

  bool get userSelectable => index <= FieldType.boolean.index;
}

class FieldDef {
  const FieldDef({
    required this.key,
    required this.label,
    this.type = FieldType.text,
    this.required = false,
    this.sensitive = false,
    this.options = const [],
    this.advanced = false,
    this.hint,
    this.initial,
  });

  final String key;
  final String label;
  final FieldType type;
  final bool required;
  final bool sensitive;
  final List<String> options;

  /// Shown under an "Advanced" expander in forms.
  final bool advanced;
  final String? hint;

  /// Value pre-filled when adding a new record (built-in fields only).
  final String? initial;

  FieldDef copyWith({
    String? label,
    FieldType? type,
    bool? required,
    bool? sensitive,
  }) => FieldDef(
    key: key,
    label: label ?? this.label,
    type: type ?? this.type,
    required: required ?? this.required,
    sensitive: sensitive ?? this.sensitive,
    options: options,
    advanced: advanced,
    hint: hint,
  );

  Map<String, dynamic> toJson() => {
    'key': key,
    'label': label,
    'type': type.name,
    'required': required,
    'sensitive': sensitive,
    if (options.isNotEmpty) 'options': options,
    if (advanced) 'advanced': true,
    if (hint != null) 'hint': hint,
  };

  factory FieldDef.fromJson(Map<String, dynamic> j) => FieldDef(
    key: j['key'] as String,
    label: j['label'] as String,
    type: FieldType.values.firstWhere(
      (t) => t.name == j['type'],
      orElse: () => FieldType.text,
    ),
    required: j['required'] as bool? ?? false,
    sensitive: j['sensitive'] as bool? ?? false,
    options: (j['options'] as List?)?.cast<String>() ?? const [],
    advanced: j['advanced'] as bool? ?? false,
    hint: j['hint'] as String?,
  );
}
