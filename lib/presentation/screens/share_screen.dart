import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../application/providers.dart';
import '../../core/crypto/qr_transfer.dart';
import '../../core/qr_payload.dart';
import 'qr/qr_send_screen.dart';
import '../../domain/field_def.dart';
import '../helpers.dart';

/// Field-level sharing. Secrets start unchecked, the exact payload is shown
/// before and again in a final confirmation, and nothing is sent silently.
class ShareScreen extends ConsumerStatefulWidget {
  const ShareScreen({super.key, required this.credentialId});
  final String credentialId;

  @override
  ConsumerState<ShareScreen> createState() => _ShareScreenState();
}

class _ShareScreenState extends ConsumerState<ShareScreen> {
  final _selected = <String>{};
  bool _init = false;

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(vaultProvider.select((s) => s.data));
    final c = data?.credentials
        .where((x) => x.id == widget.credentialId)
        .firstOrNull;
    if (data == null || c == null) {
      return Scaffold(appBar: AppBar(), body: const SizedBox());
    }
    final cat = data.category(c.categoryId);
    final defs = fieldsFor(cat, c)
        .where(
          (f) =>
              (c.values[f.key] ?? '').isNotEmpty && f.type != FieldType.boolean,
        )
        .toList();

    if (!_init) {
      _init = true;
      _selected
        ..add('_title')
        ..addAll(defs.where((f) => !f.sensitive).map((f) => f.key));
    }

    String payload() {
      final lines = <String>[];
      if (_selected.contains('_title')) lines.add(c.title);
      for (final f in defs) {
        if (_selected.contains(f.key)) {
          lines.add('${f.label}: ${c.values[f.key]}');
        }
      }
      if (c.notes.isNotEmpty && _selected.contains('_notes')) {
        lines.add('Notes: ${c.notes}');
      }
      return lines.join('\n');
    }

    final text = payload();
    final hasSecret = defs.any((f) => f.sensitive && _selected.contains(f.key));

    Future<void> send() async {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Share these fields?'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Destination: your device share sheet (WhatsApp, email, messages, or any installed app you pick next).',
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(ctx).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SelectableText(
                    text,
                    style: const TextStyle(fontFamily: 'monospace'),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  hasSecret
                      ? 'This includes secret values. The receiving app and the recipient may keep, copy or forward them, and cannot be forced to delete them.'
                      : 'The receiving app and the recipient may keep this information.',
                  style: TextStyle(color: Theme.of(ctx).colorScheme.error),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(88, 44)),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Share'),
            ),
          ],
        ),
      );
      if (ok != true || !context.mounted) return;
      if (hasSecret &&
          !await reauthenticate(
            context,
            ref,
            reason: 'Authenticate to share secret values',
          )) {
        return;
      }
      await ref
          .read(lockGuardProvider)
          .run(() => SharePlus.instance.share(ShareParams(text: text)));
    }

    Future<void> sendQr() async {
      final fields = [
        for (final f in defs)
          if (_selected.contains(f.key))
            QrField(f.label, c.values[f.key]!, sensitive: f.sensitive),
      ];
      final record = QrRecord(
        title: _selected.contains('_title') ? c.title : 'Shared item',
        fields: fields,
        notes: _selected.contains('_notes') ? c.notes : '',
      );
      if (record.encode().length > QrTransfer.maxPayloadBytes) {
        showSnack(
          context,
          'Too much data for a QR code. Select fewer fields or use the share sheet.',
        );
        return;
      }
      final ok = await confirmDialog(
        context,
        title: 'Send these fields by QR?',
        message:
            'Destination: the device that scans your screen next.\n\n$text\n\n'
            'Only the receiving device can decrypt it, once, within 2 minutes. '
            'It can still keep, copy or forward what it receives.',
        confirmLabel: 'Continue',
      );
      if (!ok || !context.mounted) return;
      if (hasSecret &&
          !await reauthenticate(
            context,
            ref,
            reason: 'Authenticate to send secret values',
          )) {
        return;
      }
      if (!context.mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => QrSendScreen(record: record)),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Share selected fields')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'Choose exactly what to share. Secret fields are unchecked by default.',
            ),
            const SizedBox(height: 8),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Title'),
              subtitle: Text(c.title),
              value: _selected.contains('_title'),
              onChanged: (v) => setState(
                () => v! ? _selected.add('_title') : _selected.remove('_title'),
              ),
            ),
            for (final f in defs)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                secondary: f.sensitive ? const Icon(Icons.lock_outline) : null,
                title: Text(f.label),
                subtitle: Text(
                  f.sensitive ? 'Secret (hidden)' : c.values[f.key]!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                value: _selected.contains(f.key),
                onChanged: (v) => setState(
                  () => v! ? _selected.add(f.key) : _selected.remove(f.key),
                ),
              ),
            if (c.notes.isNotEmpty)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Notes'),
                value: _selected.contains('_notes'),
                onChanged: (v) => setState(
                  () =>
                      v! ? _selected.add('_notes') : _selected.remove('_notes'),
                ),
              ),
            const SizedBox(height: 12),
            Text('Preview', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  text.isEmpty ? 'Nothing selected' : text,
                  style: const TextStyle(fontFamily: 'monospace'),
                ),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: text.isEmpty ? null : send,
              icon: const Icon(Icons.share),
              label: const Text('Review and share'),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: text.isEmpty ? null : sendQr,
              icon: const Icon(Icons.qr_code_2),
              label: const Text('Send by QR (encrypted, one-time)'),
            ),
            const SizedBox(height: 4),
            Text(
              'Encrypted for one device you pair with right now. Expires in 2 minutes and works once. Both devices must be in front of each other.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Text(
              'No app can stop a recipient from photographing, copying or forwarding what you share. For a full encrypted transfer, use Settings > Backup & Restore.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
