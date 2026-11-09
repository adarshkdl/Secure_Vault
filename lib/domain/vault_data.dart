import 'builtin_categories.dart';
import 'category.dart';
import 'credential.dart';

class VaultData {
  VaultData({List<Category>? customCategories, List<Credential>? credentials})
    : customCategories = customCategories ?? [],
      credentials = credentials ?? [];

  static const int currentSchema = 1;

  final List<Category> customCategories;
  final List<Credential> credentials;

  List<Category> get allCategories => [
    ...builtInCategories,
    ...customCategories,
  ];

  Category? category(String id) {
    for (final c in allCategories) {
      if (c.id == id) return c;
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
    'schema': currentSchema,
    'categories': customCategories.map((c) => c.toJson()).toList(),
    'credentials': credentials.map((c) => c.toJson()).toList(),
  };

  factory VaultData.fromJson(Map<String, dynamic> j) {
    final v = migrate(j);
    return VaultData(
      customCategories: (v['categories'] as List? ?? const [])
          .map((e) => Category.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
      credentials: (v['credentials'] as List? ?? const [])
          .map((e) => Credential.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
    );
  }

  /// Upgrades older payloads step by step. Rejects payloads from a newer app.
  static Map<String, dynamic> migrate(Map<String, dynamic> j) {
    final v = (j['schema'] as int?) ?? 1;
    if (v > currentSchema) {
      throw const FormatException(
        'This data was created by a newer version of the app.',
      );
    }
    final out = Map<String, dynamic>.from(j);
    // Future migrations: step v -> v+1 here, until v == currentSchema.
    out['schema'] = currentSchema;
    return out;
  }
}
