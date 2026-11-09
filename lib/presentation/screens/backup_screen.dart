import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../application/providers.dart';
import '../../core/crypto/vault_crypto.dart';
import '../../data/backup_service.dart';
import '../helpers.dart';
import '../widgets/password_widgets.dart';

class BackupHomeScreen extends StatelessWidget {
  const BackupHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Backup & restore')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'Backups are encrypted files you move between devices yourself (WhatsApp, USB, AirDrop, a cloud drive...). SecureVault never uploads anything and does not sync automatically.',
            ),
            const SizedBox(height: 16),
            Card(
              child: ListTile(
                leading: const Icon(Icons.upload_file),
                title: const Text('Create encrypted backup'),
                subtitle: const Text(
                  'Protected by a separate backup passphrase',
                ),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const BackupCreateScreen(),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Card(
              child: ListTile(
                leading: const Icon(Icons.restore),
                title: const Text('Restore from backup'),
                subtitle: const Text(
                  'Replaces this device\'s vault after confirmation',
                ),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const RestoreScreen(),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'A backup is a snapshot, not live sync. Restoring an older backup replaces newer changes on this device. If you lose both the backup passphrase and the vault, the data cannot be recovered.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class BackupCreateScreen extends ConsumerStatefulWidget {
  const BackupCreateScreen({super.key});

  @override
  ConsumerState<BackupCreateScreen> createState() => _BackupCreateState();
}

class _BackupCreateState extends ConsumerState<BackupCreateScreen> {
  final _form = GlobalKey<FormState>();
  final _pp = TextEditingController();
  final _cf = TextEditingController();
  bool _busy = false;
  String _status = '';

  @override
  void dispose() {
    _pp.dispose();
    _cf.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (!_form.currentState!.validate()) return;
    if (!await reauthenticate(
      context,
      ref,
      reason: 'Authenticate to export your vault',
    )) {
      return;
    }
    if (!mounted) return;
    setState(() {
      _busy = true;
      _status = 'Encrypting...';
    });
    File? file;
    try {
      final data = ref.read(vaultProvider).data!;
      final bytes = await BackupService.create(data, _pp.text);

      setState(() => _status = 'Verifying backup...');
      BackupService.inspect(bytes);
      final check = await BackupService.decrypt(bytes, _pp.text);
      if (check.credentials.length != data.credentials.length) {
        throw const BackupFormatException('Verification failed.');
      }

      final dir = await getTemporaryDirectory();
      final stamp = DateTime.now()
          .toIso8601String()
          .substring(0, 16)
          .replaceAll(RegExp('[:T]'), '-');
      file = File(
        '${dir.path}/securevault-$stamp.${BackupService.fileExtension}',
      );
      await file.writeAsBytes(bytes, flush: true); // already encrypted

      if (!mounted) return;
      setState(() => _status = 'Opening share sheet...');
      await ref
          .read(lockGuardProvider)
          .run(
            () => SharePlus.instance.share(
              ShareParams(
                files: [XFile(file!.path)],
                subject: 'SecureVault encrypted backup',
              ),
            ),
          );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.key),
          title: const Text('Keep the passphrase separate'),
          content: const Text(
            'Send the backup passphrase through a different channel than the file (for example a phone call or a different app). Never send both together.',
          ),
          actions: [
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(88, 44)),
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Got it'),
            ),
          ],
        ),
      );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        showSnack(
          context,
          'Backup failed: ${e is FileSystemException ? 'could not write the file (storage full?)' : e}',
        );
      }
    } finally {
      // Remove the temporary encrypted copy.
      try {
        if (file != null && await file.exists()) await file.delete();
      } catch (_) {}
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create backup')),
      body: SafeArea(
        child: Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                'Your backup contains sensitive data. It is encrypted on this device before it is written anywhere, using a passphrase you choose now. Use a different passphrase from your master password.',
              ),
              const SizedBox(height: 16),
              SecretTextField(
                controller: _pp,
                label: 'Backup passphrase',
                onChanged: (_) => setState(() {}),
                validator: (v) {
                  final base = validateNewSecret(v, name: 'passphrase');
                  if (base != null) return base;
                  return null;
                },
                helperText:
                    'At least 10 characters. Write it down somewhere safe.',
              ),
              StrengthMeter(password: _pp.text),
              const SizedBox(height: 16),
              SecretTextField(
                controller: _cf,
                label: 'Confirm passphrase',
                validator: (v) =>
                    v == _pp.text ? null : 'Passphrases do not match',
              ),
              const SizedBox(height: 16),
              Text(
                'Without this passphrase the backup cannot be opened by anyone, including us.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _busy ? null : _create,
                icon: const Icon(Icons.lock),
                label: Text(_busy ? _status : 'Encrypt and share'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _Step { pick, passphrase, review }

class RestoreScreen extends ConsumerStatefulWidget {
  const RestoreScreen({super.key});

  @override
  ConsumerState<RestoreScreen> createState() => _RestoreScreenState();
}

class _RestoreScreenState extends ConsumerState<RestoreScreen> {
  _Step _step = _Step.pick;
  Uint8List? _bytes;
  BackupHeader? _header;
  final _pp = TextEditingController();
  bool _busy = false;
  String? _error;
  dynamic _staged; // VaultData held in memory only until confirmed

  @override
  void dispose() {
    _pp.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    setState(() => _error = null);
    try {
      final files = await ref
          .read(lockGuardProvider)
          .run(() => FilePicker.pickFiles());
      if (files.isEmpty) return;
      final f = files.first;
      final Uint8List bytes = await f.readAsBytes();
      final header = BackupService.inspect(bytes);
      setState(() {
        _bytes = bytes;
        _header = header;
        _step = _Step.passphrase;
      });
    } on BackupFormatException catch (e) {
      setState(() => _error = e.message);
    } on FileSystemException {
      setState(
        () => _error =
            'The file could not be read. The transfer may be incomplete.',
      );
    }
  }

  Future<void> _decrypt() async {
    if (_pp.text.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final data = await BackupService.decrypt(_bytes!, _pp.text);
      setState(() {
        _staged = data;
        _step = _Step.review;
      });
    } on DecryptionFailure {
      setState(
        () => _error = 'Wrong passphrase, or the file was modified or damaged.',
      );
    } on BackupFormatException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _commit() async {
    final ok = await confirmDialog(
      context,
      title: 'Replace this vault?',
      message:
          'All records on this device will be replaced by the backup. Changes made after the backup was created will be lost. Create a fresh backup of the current vault first if unsure.',
      confirmLabel: 'Replace',
      destructive: true,
    );
    if (!ok || !mounted) return;
    if (!await reauthenticate(
      context,
      ref,
      passwordOnly: true,
      reason: 'Enter your master password to replace the vault',
    )) {
      return;
    }
    try {
      await ref.read(vaultProvider.notifier).replaceWithBackup(_staged);
      if (!mounted) return;
      showSnack(
        context,
        'Backup restored. Your master password on this device is unchanged.',
      );
      Navigator.of(context).popUntil((r) => r.isFirst);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Restore failed. Your existing vault was not changed.',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final h = _header;
    return Scaffold(
      appBar: AppBar(title: const Text('Restore backup')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_step == _Step.pick) ...[
              const Text(
                'Choose a SecureVault backup file (.svbackup) from your device.',
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _pick,
                icon: const Icon(Icons.folder_open),
                label: const Text('Choose backup file'),
              ),
            ],
            if (_step == _Step.passphrase && h != null) ...[
              Card(
                child: ListTile(
                  leading: const Icon(Icons.description_outlined),
                  title: Text('Backup from ${formatDateTime(h.createdAt)}'),
                  subtitle: Text(
                    '${h.recordCount} record(s)  -  format v${h.version}',
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SecretTextField(
                controller: _pp,
                label: 'Backup passphrase',
                autofocus: true,
                onSubmitted: (_) => _decrypt(),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _busy ? null : _decrypt,
                child: Text(_busy ? 'Decrypting...' : 'Verify and open'),
              ),
            ],
            if (_step == _Step.review && h != null) ...[
              Card(
                child: ListTile(
                  leading: const Icon(Icons.verified_outlined),
                  title: const Text('Backup verified'),
                  subtitle: Text(
                    'Created ${formatDateTime(h.createdAt)}\n${h.recordCount} record(s). Nothing has been changed yet.',
                  ),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _commit,
                child: const Text('Replace this vault with the backup'),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
