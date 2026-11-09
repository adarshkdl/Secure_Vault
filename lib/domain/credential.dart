import 'field_def.dart';

class Credential {
  Credential({
    required this.id,
    required this.categoryId,
    required this.title,
    Map<String, String>? values,
    List<FieldDef>? extraFields,
    this.notes = '',
    List<String>? tags,
    this.isFavorite = false,
    required this.createdAt,
    required this.updatedAt,
    this.lastAccessedAt,
    this.deletedAt,
  }) : values = values ?? {},
       extraFields = extraFields ?? [],
       tags = tags ?? [];

  final String id;
  final String categoryId;
  final String title;

  /// Field key -> value. Unknown keys are preserved on edit.
  final Map<String, String> values;

  /// Per-record custom fields (their values live in [values]).
  final List<FieldDef> extraFields;
  final String notes;
  final List<String> tags;
  final bool isFavorite;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? lastAccessedAt;

  /// Soft-delete marker (Recently Deleted). Records stay inside the encrypted
  /// vault, so keeping them there does not weaken confidentiality.
  final DateTime? deletedAt;

  bool get isDeleted => deletedAt != null;

  Credential copyWith({
    String? categoryId,
    String? title,
    Map<String, String>? values,
    List<FieldDef>? extraFields,
    String? notes,
    List<String>? tags,
    bool? isFavorite,
    DateTime? updatedAt,
    DateTime? lastAccessedAt,
    DateTime? deletedAt,
    bool clearDeleted = false,
  }) => Credential(
    id: id,
    categoryId: categoryId ?? this.categoryId,
    title: title ?? this.title,
    values: values ?? Map.of(this.values),
    extraFields: extraFields ?? List.of(this.extraFields),
    notes: notes ?? this.notes,
    tags: tags ?? List.of(this.tags),
    isFavorite: isFavorite ?? this.isFavorite,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    lastAccessedAt: lastAccessedAt ?? this.lastAccessedAt,
    deletedAt: clearDeleted ? null : (deletedAt ?? this.deletedAt),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'categoryId': categoryId,
    'title': title,
    'values': values,
    'extraFields': extraFields.map((f) => f.toJson()).toList(),
    'notes': notes,
    'tags': tags,
    'fav': isFavorite,
    'created': createdAt.toIso8601String(),
    'updated': updatedAt.toIso8601String(),
    'accessed': lastAccessedAt?.toIso8601String(),
    'deleted': deletedAt?.toIso8601String(),
  };

  factory Credential.fromJson(Map<String, dynamic> j) {
    DateTime? d(String k) =>
        j[k] == null ? null : DateTime.parse(j[k] as String);
    return Credential(
      id: j['id'] as String,
      categoryId: j['categoryId'] as String,
      title: j['title'] as String,
      values: Map<String, String>.from(j['values'] as Map),
      extraFields: (j['extraFields'] as List? ?? const [])
          .map((e) => FieldDef.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
      notes: j['notes'] as String? ?? '',
      tags: (j['tags'] as List? ?? const []).cast<String>(),
      isFavorite: j['fav'] as bool? ?? false,
      createdAt: d('created')!,
      updatedAt: d('updated')!,
      lastAccessedAt: d('accessed'),
      deletedAt: d('deleted'),
    );
  }
}
