import 'builtin_categories.dart';
import 'category.dart';
import 'credential.dart';

class VaultData {
  VaultData({
    List<Category>? customCategories,
    List<Credential>? credentials,
    Map<String, DateTime>? tombstones,
  }) : customCategories = customCategories ?? [],
       credentials = credentials ?? [],
       tombstones = tombstones ?? {};

  /// 2 adds [tombstones]. Older payloads load with an empty map.
  static const int currentSchema = 2;

  final List<Category> customCategories;
  final List<Credential> credentials;

  /// Records and custom categories that were permanently deleted: id ->
  /// deletion time. Needed so cloud sync can tell "deleted here" from "never
  /// existed here" and not bring a deleted item back from another device.
  final Map<String, DateTime> tombstones;

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
    if (tombstones.isNotEmpty)
      'tombstones': {
        for (final e in tombstones.entries) e.key: e.value.toIso8601String(),
      },
  };

  factory VaultData.fromJson(Map<String, dynamic> j) {
    final v = migrate(j);
    final t = v['tombstones'];
    return VaultData(
      customCategories: (v['categories'] as List? ?? const [])
          .map((e) => Category.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
      credentials: (v['credentials'] as List? ?? const [])
          .map((e) => Credential.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
      tombstones: t is Map
          ? {
              for (final e in t.entries)
                e.key as String: DateTime.parse(e.value as String),
            }
          : null,
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
    // 1 -> 2: tombstones are optional, so nothing to rewrite.
    out['schema'] = currentSchema;
    return out;
  }
}
