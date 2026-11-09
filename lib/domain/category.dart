import 'field_def.dart';

class Category {
  const Category({
    required this.id,
    required this.name,
    required this.iconKey,
    required this.colorKey,
    required this.fields,
    this.isBuiltIn = false,
    this.sortOrder = 0,
    this.subtitleKey,
    this.autoTitleKey,
    this.allowCustomFields = true,
  });

  final String id;
  final String name;
  final String iconKey;
  final String colorKey;
  final List<FieldDef> fields;
  final bool isBuiltIn;
  final int sortOrder;

  /// Key of a NON-sensitive field shown as the list subtitle.
  final String? subtitleKey;

  /// When set, the form has no Title box: the record title is taken from
  /// this field's value (built-in categories only).
  final String? autoTitleKey;

  /// When false the form hides "Add custom field" (built-in categories only).
  /// Custom fields already on a record stay and can still be removed.
  final bool allowCustomFields;

  Category copyWith({
    String? name,
    String? iconKey,
    String? colorKey,
    List<FieldDef>? fields,
    int? sortOrder,
    String? subtitleKey,
  }) => Category(
    id: id,
    name: name ?? this.name,
    iconKey: iconKey ?? this.iconKey,
    colorKey: colorKey ?? this.colorKey,
    fields: fields ?? this.fields,
    isBuiltIn: isBuiltIn,
    sortOrder: sortOrder ?? this.sortOrder,
    subtitleKey: subtitleKey ?? this.subtitleKey,
    autoTitleKey: autoTitleKey,
    allowCustomFields: allowCustomFields,
  );

  // Only custom categories are persisted; built-ins live in code so new
  // built-in fields can ship in app updates.
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'icon': iconKey,
    'color': colorKey,
    'sortOrder': sortOrder,
    'subtitleKey': subtitleKey,
    'fields': fields.map((f) => f.toJson()).toList(),
  };

  factory Category.fromJson(Map<String, dynamic> j) => Category(
    id: j['id'] as String,
    name: j['name'] as String,
    iconKey: j['icon'] as String? ?? 'folder',
    colorKey: j['color'] as String? ?? 'blue',
    sortOrder: j['sortOrder'] as int? ?? 100,
    subtitleKey: j['subtitleKey'] as String?,
    fields: (j['fields'] as List)
        .map((e) => FieldDef.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList(),
  );
}
