import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/import_mapper.dart';
import '../../application/providers.dart';
import '../../core/password_import.dart';
import '../helpers.dart';

enum _Step { intro, review, done }

/// Imports logins from another password manager's plaintext export. The file
/// is read into memory, parsed, and never copied elsewhere by the app.
class ImportScreen extends ConsumerStatefulWidget {
  const ImportScreen({super.key});

  @override
  ConsumerState<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends ConsumerState<ImportScreen> {
  _Step _step = _Step.intro;
  ImportResult? _result;
  ImportPlan? _plan;
  String? _error;
  int _imported = 0;
  bool _busy = false;

  @override
  void dispose() {
    // Drop the picker's cached copy of the plaintext export, if any.
    FilePicker.clearTemporaryFiles().catchError((_) => null);
    super.dispose();
  }

  Future<void> _pick() async {
    setState(() => _error = null);
    try {
      final files = await ref
          .read(lockGuardProvider)
          .run(() => FilePicker.pickFiles());
      if (files.isEmpty) return;
      final bytes = await files.first.readAsBytes();
      final result = PasswordImport.parse(bytes);
      final data = ref.read(vaultProvider).data!;
      if (!mounted) return;
      setState(() {
        _result = result;
        _plan = planImport(data, result.logins);
        _step = _Step.review;
      });
    } on ImportException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on Object {
      if (mounted) setState(() => _error = 'The file could not be read.');
    }
  }

  Future<void> _import() async {
    final plan = _plan!;
    if (plan.toAdd.isEmpty) return;
    if (!await reauthenticate(
      context,
      ref,
      reason: 'Authenticate to import passwords',
    )) {
      return;
    }
    setState(() => _busy = true);
    try {
      final creds = toCredentials(plan.toAdd, newId: newId);
      await ref.read(vaultProvider.notifier).addCredentials(creds);
      if (!mounted) return;
      setState(() {
        _imported = creds.length;
        _step = _Step.done;
        _busy = false;
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Import failed. Your vault was not changed.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final children = <Widget>[];
    switch (_step) {
      case _Step.intro:
        children.addAll([
          const Text(
            'Import logins from Bitwarden (JSON or CSV), 1Password, LastPass, Chrome, Edge, Firefox or any CSV with name, url, username and password columns.',
          ),
          const SizedBox(height: 12),
          Card(
            color: scheme.errorContainer,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                'Exports from other apps are NOT encrypted. Anyone who can open the file can read every password in it. Delete it (and empty the trash) as soon as the import is done, and do not send it to anyone.',
                style: TextStyle(color: scheme.onErrorContainer),
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Existing records are never changed. Entries that match an existing website login (same name and username) are skipped.',
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: scheme.error)),
          ],
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _pick,
            icon: const Icon(Icons.file_open_outlined),
            label: const Text('Choose export file'),
          ),
        ]);
      case _Step.review:
        final r = _result!, p = _plan!;
        children.addAll([
          Text('Detected: ${r.source}'),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.download_done_outlined),
            title: Text('${p.toAdd.length} login(s) will be added'),
            subtitle: const Text('As Website logins tagged "imported"'),
          ),
          if (p.duplicates.isNotEmpty)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.copy_all_outlined),
              title: Text('${p.duplicates.length} duplicate(s) skipped'),
            ),
          if (r.skipped > 0)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.block_outlined),
              title: Text('${r.skipped} non-login or empty item(s) skipped'),
              subtitle: const Text('Cards, identities and secure notes'),
            ),
          const SizedBox(height: 8),
          for (final l in p.toAdd.take(5))
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(l.name),
              subtitle: Text(l.username.isEmpty ? l.url : l.username),
            ),
          if (p.toAdd.length > 5) Text('...and ${p.toAdd.length - 5} more'),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: scheme.error)),
          ],
          const SizedBox(height: 16),
          FilledButton(
            onPressed: p.toAdd.isEmpty || _busy ? null : _import,
            child: Text(_busy ? 'Importing...' : 'Import ${p.toAdd.length}'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
        ]);
      case _Step.done:
        children.addAll([
          Icon(Icons.check_circle_outline, size: 56, color: scheme.primary),
          const SizedBox(height: 12),
          Text(
            'Imported $_imported login(s).',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          Card(
            color: scheme.errorContainer,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                'Now delete the export file from your device, your downloads folder and the trash, and remove the passwords from the old app if you no longer use it.',
                style: TextStyle(color: scheme.onErrorContainer),
              ),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Done'),
          ),
        ]);
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Import passwords')),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.all(16), children: children),
      ),
    );
  }
}
