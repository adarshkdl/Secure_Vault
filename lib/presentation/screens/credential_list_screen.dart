import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers.dart';
import '../widgets/credential_list_view.dart';
import 'credential_form_screen.dart';

class CredentialListScreen extends ConsumerWidget {
  const CredentialListScreen({super.key, required this.categoryId});
  final String categoryId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(vaultProvider.select((s) => s.data));
    final cat = data?.category(categoryId);
    return Scaffold(
      appBar: AppBar(title: Text(cat?.name ?? 'Category')),
      body: SafeArea(
        child: CredentialListView(
          categoryId: categoryId,
          emptyTitle: 'No ${cat?.name ?? 'items'} yet',
          emptyMessage: 'Tap Add to create one.',
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: null,
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => CredentialFormScreen(categoryId: categoryId),
          ),
        ),
        icon: const Icon(Icons.add),
        label: const Text('Add'),
      ),
    );
  }
}
