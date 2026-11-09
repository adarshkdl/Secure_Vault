import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers.dart';
import '../helpers.dart';
import '../theme.dart';
import 'category_editor_screen.dart';
import 'credential_list_screen.dart';

class CategoriesTab extends ConsumerWidget {
  const CategoriesTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(vaultProvider.select((s) => s.data));
    final items = ref.watch(visibleCredentialsProvider);
    if (data == null) return const SizedBox.shrink();
    final cats = data.allCategories;

    return Stack(
      children: [
        ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
          itemCount: cats.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (_, i) {
            final c = cats[i];
            final n = items.where((x) => x.categoryId == c.id).length;
            final color = colorFor(c.colorKey);
            return Card(
              child: ListTile(
                minVerticalPadding: 12,
                leading: CircleAvatar(
                  backgroundColor: color.withValues(alpha: 0.15),
                  child: Icon(iconFor(c.iconKey), color: color),
                ),
                title: Text(c.name),
                subtitle: Text('$n record${n == 1 ? '' : 's'}'),
                trailing: c.isBuiltIn
                    ? const Icon(Icons.chevron_right)
                    : PopupMenuButton<String>(
                        tooltip: 'Category options',
                        onSelected: (v) async {
                          if (v == 'edit') {
                            Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) =>
                                    CategoryEditorScreen(existing: c),
                              ),
                            );
                          } else if (v == 'delete') {
                            final ok = await confirmDialog(
                              context,
                              title: 'Delete category?',
                              message: 'This removes the category "${c.name}".',
                              confirmLabel: 'Delete',
                              destructive: true,
                            );
                            if (!ok) return;
                            final done = await ref
                                .read(vaultProvider.notifier)
                                .deleteCategory(c.id);
                            if (!done && context.mounted) {
                              showSnack(
                                context,
                                'Move or delete its records first.',
                              );
                            }
                          }
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'edit', child: Text('Edit')),
                          PopupMenuItem(value: 'delete', child: Text('Delete')),
                        ],
                      ),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => CredentialListScreen(categoryId: c.id),
                  ),
                ),
              ),
            );
          },
        ),
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton.extended(
            heroTag: null,
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const CategoryEditorScreen(),
              ),
            ),
            icon: const Icon(Icons.create_new_folder_outlined),
            label: const Text('New category'),
          ),
        ),
      ],
    );
  }
}
