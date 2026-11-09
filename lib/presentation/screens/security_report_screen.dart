import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers.dart';
import '../../core/password_tools.dart';
import '../../domain/field_def.dart';
import '../helpers.dart';
import '../widgets/credential_tile.dart';

/// Local-only checks. Lists record titles with problems, never the passwords.
class SecurityReportScreen extends ConsumerWidget {
  const SecurityReportScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(vaultProvider.select((s) => s.data));
    final items = ref.watch(visibleCredentialsProvider);
    if (data == null) return const SizedBox.shrink();

    final counts = <String, int>{};
    String? pw(c, f) => c.values[f.key];
    for (final c in items) {
      for (final f in fieldsFor(data.category(c.categoryId), c)) {
        if (f.type != FieldType.password) continue;
        final v = pw(c, f);
        if (v != null && v.isNotEmpty) {
          counts.update(v, (n) => n + 1, ifAbsent: () => 1);
        }
      }
    }
    final weak = <String>{}, reused = <String>{};
    for (final c in items) {
      for (final f in fieldsFor(data.category(c.categoryId), c)) {
        if (f.type != FieldType.password) continue;
        final v = pw(c, f);
        if (v == null || v.isEmpty) continue;
        if (PasswordTools.isWeak(v)) weak.add(c.id);
        if ((counts[v] ?? 0) > 1) reused.add(c.id);
      }
    }

    Widget section(String title, Set<String> ids) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (ids.isEmpty) const Text('None found.'),
        for (final c in items.where((c) => ids.contains(c.id))) ...[
          CredentialTile(credential: c),
          const SizedBox(height: 8),
        ],
        const SizedBox(height: 16),
      ],
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Security reminders')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'These checks run only on this device, in memory, while the vault is unlocked.',
          ),
          const SizedBox(height: 16),
          section('Weak passwords', weak),
          section('Reused passwords', reused),
        ],
      ),
    );
  }
}
