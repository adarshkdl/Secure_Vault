import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/expiry.dart';
import '../../application/providers.dart';
import '../widgets/app_logo.dart';
import '../widgets/credential_tile.dart';
import '../widgets/glass.dart';
import 'backup_screen.dart';
import 'credential_form_screen.dart';
import 'expiry_screen.dart';
import 'qr/qr_receive_screen.dart';
import 'security_report_screen.dart';

class HomeTab extends ConsumerStatefulWidget {
  const HomeTab({super.key, this.onOpenSettings});

  /// Switches the shell to the Settings tab.
  final VoidCallback? onOpenSettings;

  @override
  ConsumerState<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends ConsumerState<HomeTab> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Widget _header(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final fg = dark ? Theme.of(context).colorScheme.onSurface : Colors.white;
    final query = _search.text.trim();
    return Container(
      color: dark ? Colors.transparent : brandDeepBlue,
      padding: EdgeInsets.fromLTRB(
        16,
        MediaQuery.paddingOf(context).top + 12,
        8,
        14,
      ),
      child: Column(
        children: [
          Row(
            children: [
              const AppLogo(size: 34, onDark: true),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'SecureVault',
                  style: TextStyle(
                    color: fg,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Lock vault now',
                icon: Icon(Icons.lock_outline, color: fg),
                onPressed: () => ref.read(vaultProvider.notifier).lock(),
              ),
              IconButton(
                tooltip: 'Settings',
                icon: Icon(Icons.settings_outlined, color: fg),
                onPressed: widget.onOpenSettings,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: SearchBar(
              controller: _search,
              hintText: 'Search credentials...',
              leading: const Icon(Icons.search),
              trailing: [
                if (query.isNotEmpty)
                  IconButton(
                    tooltip: 'Clear search',
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(_search.clear),
                  ),
              ],
              onChanged: (_) => setState(() {}),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(vaultProvider.select((s) => s.data));
    final items = ref.watch(visibleCredentialsProvider);
    if (data == null) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final query = _search.text.trim();

    final favorites = sortCredentials(
      items.where((c) => c.isFavorite).toList(),
      SortMode.used,
    ).take(5).toList();
    final recent = sortCredentials(items, SortMode.used).take(5).toList();
    final weekAgo = DateTime.now().subtract(const Duration(days: 7));
    final recentCount = items
        .where((c) => (c.lastAccessedAt ?? c.updatedAt).isAfter(weekAgo))
        .length;
    final report = buildSecurityReport(data);
    final expiry = buildExpiryReport(
      data,
      leadDays: ref.watch(settingsProvider.select((s) => s.expiryLeadDays)),
    );

    Widget statGrid() => LayoutBuilder(
      builder: (context, box) {
        // Two columns on phones, one when text is scaled very large.
        final cols = MediaQuery.textScalerOf(context).scale(1) > 1.4 ? 1 : 2;
        final w = (box.maxWidth - 10 * (cols - 1)) / cols;
        final tiles = [
          (items.length, 'Total', Icons.lock_outline, const Color(0xFF1558D6)),
          (
            items.where((c) => c.isFavorite).length,
            'Favorites',
            Icons.star_outline,
            const Color(0xFF2E7D32),
          ),
          (
            data.allCategories.length,
            'Categories',
            Icons.grid_view,
            const Color(0xFF6A1B9A),
          ),
          (recentCount, 'Recent', Icons.schedule, const Color(0xFFE65100)),
        ];
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final t in tiles)
              SizedBox(
                width: w,
                child: StatTile(
                  value: t.$1,
                  label: t.$2,
                  icon: t.$3,
                  color: t.$4,
                ),
              ),
          ],
        );
      },
    );

    final body = <Widget>[
      if (query.isNotEmpty)
        ..._results(items, data, query)
      else ...[
        if (!expiry.isEmpty) ...[
          Card(
            child: ListTile(
              leading: Icon(
                Icons.event_busy_outlined,
                color: expiry.overdue > 0 ? scheme.error : scheme.primary,
              ),
              title: const Text('Expiry reminders'),
              subtitle: Text(
                '${expiry.overdue} overdue, ${expiry.upcoming} due soon',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const ExpiryScreen()),
              ),
            ),
          ),
          const SizedBox(height: 10),
        ],
        if (report.hasIssues) ...[
          Card(
            child: ListTile(
              leading: Icon(
                Icons.health_and_safety_outlined,
                color: scheme.error,
              ),
              title: const Text('Security reminders'),
              subtitle: Text(
                '${report.weak} weak, ${report.reused} reused password(s)',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const SecurityReportScreen(),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
        ],
        statGrid(),
        const SizedBox(height: 20),
        Text('Quick Access', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: QuickAction(
                icon: Icons.add,
                label: 'Add',
                color: const Color(0xFF1558D6),
                onTap: () => pickCategoryAndAdd(context, ref),
              ),
            ),
            Expanded(
              child: QuickAction(
                icon: Icons.qr_code_scanner,
                label: 'Receive',
                color: const Color(0xFF3949AB),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const QrReceiveScreen(),
                  ),
                ),
              ),
            ),
            Expanded(
              child: QuickAction(
                icon: Icons.cloud_upload_outlined,
                label: 'Backup',
                color: const Color(0xFF00796B),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const BackupHomeScreen(),
                  ),
                ),
              ),
            ),
            Expanded(
              child: QuickAction(
                icon: Icons.settings_outlined,
                label: 'Settings',
                color: const Color(0xFF6A1B9A),
                onTap: () => widget.onOpenSettings?.call(),
              ),
            ),
          ],
        ),
        if (favorites.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('Favorites', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          for (final c in favorites) ...[
            CredentialTile(credential: c),
            const SizedBox(height: 8),
          ],
        ],
        if (recent.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('Recent Items', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          for (final c in recent) ...[
            CredentialTile(credential: c),
            const SizedBox(height: 8),
          ],
        ],
        if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 40),
            child: Column(
              children: [
                Icon(Icons.inbox_outlined, size: 56, color: scheme.outline),
                const SizedBox(height: 12),
                Text(
                  'Your vault is empty',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                const Text('Tap Add to store your first credential.'),
              ],
            ),
          ),
      ],
    ];

    return Column(
      children: [
        _header(context),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            children: body,
          ),
        ),
      ],
    );
  }

  List<Widget> _results(List items, data, String query) {
    final matches = sortCredentials([
      for (final c in items)
        if (matchesQuery(c, data, query)) c,
    ], SortMode.name);
    if (matches.isEmpty) {
      return const [
        Padding(
          padding: EdgeInsets.symmetric(vertical: 48),
          child: Center(child: Text('No matches')),
        ),
      ];
    }
    return [
      for (final c in matches) ...[
        CredentialTile(credential: c),
        const SizedBox(height: 8),
      ],
    ];
  }
}
