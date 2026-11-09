import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers.dart';
import '../../domain/credential.dart';
import '../helpers.dart';
import '../screens/credential_detail_screen.dart';
import '../theme.dart';
import 'provider_icon.dart';

/// List row. Shows only title, a non-sensitive subtitle, the category marker
/// and favourite state. Never a secret.
class CredentialTile extends ConsumerWidget {
  const CredentialTile({super.key, required this.credential, this.trailing});
  final Credential credential;
  final Widget? trailing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(vaultProvider.select((s) => s.data))!;
    final cat = data.category(credential.categoryId);
    final color = colorFor(cat?.colorKey ?? 'grey');
    final sub = subtitleFor(credential, data);
    return Card(
      child: ListTile(
        minVerticalPadding: 12,
        leading: cat?.id == 'email'
            ? ProviderIcon(credential.values['provider'] ?? 'Other')
            : CircleAvatar(
                backgroundColor: color.withValues(alpha: 0.15),
                child: Icon(iconFor(cat?.iconKey ?? 'folder'), color: color),
              ),
        title: Text(
          credential.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing:
            trailing ??
            (credential.isFavorite
                ? const Icon(
                    Icons.star,
                    color: Colors.amber,
                    semanticLabel: 'Favorite',
                  )
                : null),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => CredentialDetailScreen(id: credential.id),
          ),
        ),
      ),
    );
  }
}
