import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers.dart';
import 'credential_tile.dart';

/// Searchable, sortable list used by category and favourites screens.
class CredentialListView extends ConsumerStatefulWidget {
  const CredentialListView({
    super.key,
    this.categoryId,
    this.favoritesOnly = false,
    this.emptyTitle = 'Nothing here yet',
    this.emptyMessage = 'Tap Add to create your first credential.',
  });

  final String? categoryId;
  final bool favoritesOnly;
  final String emptyTitle;
  final String emptyMessage;

  @override
  ConsumerState<CredentialListView> createState() => _CredentialListViewState();
}

class _CredentialListViewState extends ConsumerState<CredentialListView> {
  final _search = TextEditingController();
  SortMode _sort = SortMode.name;
  bool _favOnly = false;

  @override
  void initState() {
    super.initState();
    _favOnly = widget.favoritesOnly;
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(vaultProvider.select((s) => s.data));
    final all = ref.watch(visibleCredentialsProvider);
    if (data == null) return const SizedBox.shrink();

    var items = all.where((c) {
      if (widget.categoryId != null && c.categoryId != widget.categoryId) {
        return false;
      }
      if (_favOnly && !c.isFavorite) return false;
      return matchesQuery(c, data, _search.text);
    }).toList();
    items = sortCredentials(items, _sort);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: SearchBar(
            controller: _search,
            hintText: 'Search title, user, URL or tag',
            leading: const Icon(Icons.search),
            trailing: [
              if (_search.text.isNotEmpty)
                IconButton(
                  tooltip: 'Clear search',
                  icon: const Icon(Icons.close),
                  onPressed: () => setState(_search.clear),
                ),
            ],
            onChanged: (_) => setState(() {}),
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              if (!widget.favoritesOnly) ...[
                FilterChip(
                  label: const Text('Favorites'),
                  selected: _favOnly,
                  onSelected: (v) => setState(() => _favOnly = v),
                ),
                const SizedBox(width: 8),
              ],
              for (final m in SortMode.values) ...[
                ChoiceChip(
                  label: Text(switch (m) {
                    SortMode.name => 'Name',
                    SortMode.updated => 'Updated',
                    SortMode.used => 'Recently used',
                  }),
                  selected: _sort == m,
                  onSelected: (_) => setState(() => _sort = m),
                ),
                const SizedBox(width: 8),
              ],
            ],
          ),
        ),
        Expanded(
          child: items.isEmpty
              ? _Empty(
                  searching: _search.text.isNotEmpty,
                  title: widget.emptyTitle,
                  message: widget.emptyMessage,
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (_, i) => CredentialTile(credential: items[i]),
                ),
        ),
      ],
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({
    required this.searching,
    required this.title,
    required this.message,
  });
  final bool searching;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              searching ? Icons.search_off : Icons.inbox_outlined,
              size: 56,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 12),
            Text(
              searching ? 'No matches' : title,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              searching ? 'Try a different search or filter.' : message,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
