import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers.dart';
import '../helpers.dart';

class DeletedScreen extends ConsumerWidget {
  const DeletedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(deletedCredentialsProvider);
    final data = ref.watch(vaultProvider.select((s) => s.data));
    final ctl = ref.read(vaultProvider.notifier);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Recently deleted'),
        actions: [
          if (items.isNotEmpty)
            TextButton(
              onPressed: () async {
                final ok = await confirmDialog(
                  context,
                  title: 'Empty trash?',
                  message:
                      'All ${items.length} item(s) are permanently deleted.',
                  confirmLabel: 'Delete all',
                  destructive: true,
                );
                if (ok) await ctl.emptyTrash();
              },
              child: const Text('Empty'),
            ),
        ],
      ),
      body: items.isEmpty
          ? const Center(child: Text('Nothing deleted recently'))
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                final c = items[i];
                final left =
                    VaultController.recentlyDeletedRetention.inDays -
                    DateTime.now().difference(c.deletedAt!).inDays;
                return Card(
                  child: ListTile(
                    title: Text(c.title),
                    subtitle: Text(
                      '${data?.category(c.categoryId)?.name ?? ''}  -  removed in ${left < 0 ? 0 : left} day(s)',
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Restore',
                          icon: const Icon(Icons.restore_from_trash),
                          onPressed: () => ctl.restore(c.id),
                        ),
                        IconButton(
                          tooltip: 'Delete permanently',
                          icon: const Icon(Icons.delete_forever),
                          onPressed: () async {
                            final ok = await confirmDialog(
                              context,
                              title: 'Delete permanently?',
                              message: 'This cannot be undone.',
                              confirmLabel: 'Delete',
                              destructive: true,
                            );
                            if (ok) await ctl.deleteForever(c.id);
                          },
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
