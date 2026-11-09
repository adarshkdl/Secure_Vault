import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers.dart';
import '../../domain/credential.dart';
import '../../domain/field_def.dart';
import '../helpers.dart';
import '../theme.dart';
import '../widgets/provider_icon.dart';
import 'credential_form_screen.dart';
import 'share_screen.dart';

class CredentialDetailScreen extends ConsumerStatefulWidget {
  const CredentialDetailScreen({super.key, required this.id});
  final String id;

  @override
  ConsumerState<CredentialDetailScreen> createState() => _DetailState();
}

class _DetailState extends ConsumerState<CredentialDetailScreen> {
  final _revealed = <String>{};

  @override
  void initState() {
    super.initState();
    Future.microtask(
      () => ref.read(vaultProvider.notifier).markAccessed(widget.id),
    );
  }

  Credential? _find() {
    final data = ref.watch(vaultProvider.select((s) => s.data));
    return data?.credentials.where((c) => c.id == widget.id).firstOrNull;
  }

  Future<void> _toggleReveal(FieldDef f) async {
    if (_revealed.contains(f.key)) {
      setState(() => _revealed.remove(f.key));
      return;
    }
    if (ref.read(settingsProvider).requireAuthForSecrets) {
      if (!await reauthenticate(
        context,
        ref,
        reason: 'Authenticate to reveal ${f.label}',
      )) {
        return;
      }
    }
    if (mounted) setState(() => _revealed.add(f.key));
  }

  Future<void> _delete(Credential c) async {
    final ok = await confirmDialog(
      context,
      title: 'Delete "${c.title}"?',
      message:
          'It moves to Recently Deleted and is permanently removed after ${VaultController.recentlyDeletedRetention.inDays} days.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!ok || !mounted) return;
    await ref.read(vaultProvider.notifier).softDelete(c.id);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final c = _find();
    final data = ref.watch(vaultProvider.select((s) => s.data));
    if (c == null || data == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Record not found')),
      );
    }
    final cat = data.category(c.categoryId);
    final defs = fieldsFor(cat, c);
    final color = colorFor(cat?.colorKey ?? 'grey');

    return Scaffold(
      appBar: AppBar(
        title: Text(c.title, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: c.isFavorite
                ? 'Remove from favorites'
                : 'Add to favorites',
            icon: Icon(
              c.isFavorite ? Icons.star : Icons.star_outline,
              color: c.isFavorite ? Colors.amber : null,
            ),
            onPressed: () =>
                ref.read(vaultProvider.notifier).toggleFavorite(c.id),
          ),
          IconButton(
            tooltip: 'Edit',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) =>
                    CredentialFormScreen(categoryId: c.categoryId, existing: c),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Share',
            icon: const Icon(Icons.share_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => ShareScreen(credentialId: c.id),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Delete',
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _delete(c),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                if (cat?.id == 'email')
                  ProviderIcon(c.values['provider'] ?? 'Other', size: 40)
                else
                  CircleAvatar(
                    backgroundColor: color.withValues(alpha: 0.15),
                    child: Icon(
                      iconFor(cat?.iconKey ?? 'folder'),
                      color: color,
                    ),
                  ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    cat?.name ?? 'Unknown category',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            for (final f in defs)
              if ((c.values[f.key] ?? '').isNotEmpty &&
                  f.type == FieldType.phoneList) ...[
                // One row (with its own copy button) per phone number.
                for (final (i, n)
                    in c.values[f.key]!
                        .split('\n')
                        .where((s) => s.trim().isNotEmpty)
                        .indexed) ...[
                  _FieldRow(
                    def: FieldDef(
                      key: '${f.key}_$i',
                      label: 'Mobile number ${i + 1}',
                      type: FieldType.phone,
                    ),
                    value: n.trim(),
                    revealed: true,
                    onToggle: () {},
                  ),
                  const SizedBox(height: 8),
                ],
              ] else if ((c.values[f.key] ?? '').isNotEmpty) ...[
                _FieldRow(
                  def: f,
                  value: c.values[f.key]!,
                  revealed: _revealed.contains(f.key),
                  onToggle: () => _toggleReveal(f),
                ),
                const SizedBox(height: 8),
              ],
            if (c.notes.isNotEmpty) ...[
              _FieldRow(
                def: const FieldDef(
                  key: '_notes',
                  label: 'Notes',
                  type: FieldType.longText,
                ),
                value: c.notes,
                revealed: true,
                onToggle: () {},
              ),
              const SizedBox(height: 8),
            ],
            if (c.tags.isNotEmpty)
              Wrap(
                spacing: 8,
                children: [for (final t in c.tags) Chip(label: Text(t))],
              ),
            const SizedBox(height: 16),
            Text(
              'Created ${formatDateTime(c.createdAt)}\nUpdated ${formatDateTime(c.updatedAt)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _FieldRow extends ConsumerWidget {
  const _FieldRow({
    required this.def,
    required this.value,
    required this.revealed,
    required this.onToggle,
  });
  final FieldDef def;
  final String value;
  final bool revealed;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sensitive = def.sensitive;
    final show = !sensitive || revealed;
    final shown = def.type == FieldType.boolean
        ? (value == 'true' ? 'Yes' : 'No')
        : value;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
        child: Row(
          children: [
            Expanded(
              // Hidden secrets are not announced to screen readers.
              child: Semantics(
                label: def.label,
                value: show ? shown : 'Hidden',
                excludeSemantics: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      def.label,
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                    const SizedBox(height: 2),
                    show
                        ? SelectableText(
                            shown,
                            style: Theme.of(context).textTheme.bodyLarge,
                          )
                        : Text(
                            '••••••••••',
                            style: Theme.of(context).textTheme.bodyLarge,
                          ),
                  ],
                ),
              ),
            ),
            if (sensitive)
              IconButton(
                tooltip: revealed ? 'Hide ${def.label}' : 'Reveal ${def.label}',
                icon: Icon(revealed ? Icons.visibility_off : Icons.visibility),
                onPressed: onToggle,
              ),
            if (def.type != FieldType.boolean)
              IconButton(
                tooltip: 'Copy ${def.label}',
                icon: const Icon(Icons.copy),
                onPressed: () => copyValue(
                  context,
                  ref,
                  label: def.label,
                  value: value,
                  sensitive: sensitive,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
