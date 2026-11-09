import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme.dart';
import '../widgets/app_logo.dart';
import '../widgets/credential_list_view.dart';
import '../widgets/glass.dart';
import 'categories_screen.dart';
import 'credential_form_screen.dart';
import 'home_tab.dart';
import 'settings_screen.dart';

class ShellScreen extends ConsumerStatefulWidget {
  const ShellScreen({super.key});

  @override
  ConsumerState<ShellScreen> createState() => _ShellScreenState();
}

class _ShellScreenState extends ConsumerState<ShellScreen> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final titles = ['SecureVault', 'Categories', 'Favorites', 'Settings'];
    return AppBackdrop(
      child: Scaffold(
        backgroundColor: dark ? Colors.transparent : null,
        appBar: _index == 0
            ? null
            : AppBar(
                title: Text(titles[_index]),
                backgroundColor: dark ? Colors.transparent : null,
              ),
        body: SafeArea(
          top: false,
          child: IndexedStack(
            index: _index,
            children: [
              HomeTab(onOpenSettings: () => setState(() => _index = 3)),
              const CategoriesTab(),
              const CredentialListView(
                favoritesOnly: true,
                emptyTitle: 'No favorites yet',
                emptyMessage: 'Star a credential to find it here quickly.',
              ),
              const SettingsTab(),
            ],
          ),
        ),
        floatingActionButton: (_index == 0 || _index == 2)
            ? DecoratedBox(
                decoration: BoxDecoration(
                  gradient: dark ? brandGradient : splashGradient,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x665B7CF5),
                      blurRadius: 18,
                      offset: Offset(0, 6),
                    ),
                  ],
                ),
                child: FloatingActionButton.extended(
                  heroTag: null,
                  elevation: 0,
                  focusElevation: 0,
                  hoverElevation: 0,
                  highlightElevation: 0,
                  backgroundColor: Colors.transparent,
                  foregroundColor: Colors.white,
                  onPressed: () => pickCategoryAndAdd(context, ref),
                  icon: const Icon(Icons.add),
                  label: const Text('Add'),
                ),
              )
            : null,
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (i) => setState(() => _index = i),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home),
              label: 'Home',
            ),
            NavigationDestination(
              icon: Icon(Icons.grid_view_outlined),
              selectedIcon: Icon(Icons.grid_view),
              label: 'Categories',
            ),
            NavigationDestination(
              icon: Icon(Icons.star_outline),
              selectedIcon: Icon(Icons.star),
              label: 'Favorites',
            ),
            NavigationDestination(
              icon: Icon(Icons.settings_outlined),
              selectedIcon: Icon(Icons.settings),
              label: 'Settings',
            ),
          ],
        ),
      ),
    );
  }
}
