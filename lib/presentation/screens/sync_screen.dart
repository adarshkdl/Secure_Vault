import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/sync_controller.dart';
import '../helpers.dart';
import '../widgets/dialog_controllers.dart';
import '../widgets/password_widgets.dart';

/// Cloud sync (Firebase). The server only ever stores ciphertext.
class SyncScreen extends ConsumerStatefulWidget {
  const SyncScreen({super.key});

  @override
  ConsumerState<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends ConsumerState<SyncScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final s = ref.read(syncControllerProvider);
      if (s.phase == SyncPhase.checking) {
        ref.read(syncControllerProvider.notifier).checkCloud();
      }
    });
  }

  Future<String?> _askPassword({
    required String title,
    required String message,
    required String confirmLabel,
  }) async {
    final r = await showDialog<String>(
      context: context,
      builder: (ctx) => DialogControllers(
        builder: (ctx, cs) => _passwordDialog(
          ctx,
          cs[0],
          title: title,
          message: message,
          confirmLabel: confirmLabel,
        ),
      ),
    );
    return (r == null || r.isEmpty) ? null : r;
  }

  Widget _passwordDialog(
    BuildContext ctx,
    TextEditingController c, {
    required String title,
    required String message,
    required String confirmLabel,
  }) {
    return AlertDialog(
      title: Text(title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message),
            const SizedBox(height: 12),
            SecretTextField(
              controller: c,
              label: 'Master password',
              autofocus: true,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => Navigator.pop(ctx, c.text),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(88, 44)),
          onPressed: () => Navigator.pop(ctx, c.text),
          child: Text(confirmLabel),
        ),
      ],
    );
  }

  Future<void> _create() async {
    final pw = await _askPassword(
      title: 'Create cloud vault',
      message:
          'Your records are encrypted on this device before upload. Enter your master password to continue. '
          'A long, unique master password matters more now: the encrypted key header will be stored in your Google account.',
      confirmLabel: 'Create',
    );
    if (pw == null || !mounted) return;
    final err = await ref
        .read(syncControllerProvider.notifier)
        .createCloudVault(pw);
    if (err != null && mounted) showSnack(context, err);
  }

  Future<void> _join() async {
    final ok = await confirmDialog(
      context,
      title: 'Join the cloud vault?',
      message:
          'This device will start using the master password of the cloud vault. '
          'Records already on this device are kept and uploaded. '
          'Face/fingerprint unlock is turned off and can be enabled again in Settings.',
      confirmLabel: 'Continue',
    );
    if (!ok || !mounted) return;
    final pw = await _askPassword(
      title: 'Cloud vault password',
      message: 'Enter the master password you use for this vault on your other device.',
      confirmLabel: 'Join',
    );
    if (pw == null || !mounted) return;
    final err = await ref
        .read(syncControllerProvider.notifier)
        .joinCloudVault(pw);
    if (!mounted) return;
    showSnack(context, err ?? 'Joined. Your vaults are now in sync.');
  }

  Future<void> _turnOff() async {
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Turn off cloud sync?'),
        content: const Text(
          'This device stops syncing and signs out. Your records on this device are not touched.\n\n'
          'You can also erase the encrypted cloud copy. Other devices keep their own local data.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'keep'),
            child: const Text('Turn off, keep cloud copy'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              minimumSize: const Size(88, 44),
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, 'delete'),
            child: const Text('Turn off and erase cloud copy'),
          ),
        ],
      ),
    );
    if (choice == null || !mounted) return;
    final err = await ref
        .read(syncControllerProvider.notifier)
        .disable(deleteCloud: choice == 'delete');
    if (mounted) showSnack(context, err ?? 'Cloud sync is off.');
  }

  String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inSeconds < 60) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes} min ago';
    if (d.inHours < 24) return '${d.inHours} h ago';
    return '${d.inDays} d ago';
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(syncControllerProvider);
    final ctl = ref.read(syncControllerProvider.notifier);
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    Widget body;
    switch (s.phase) {
      case SyncPhase.unavailable:
        body = const _Panel(
          icon: Icons.cloud_off_outlined,
          title: 'Cloud sync is not set up in this build',
          text:
              'It needs your own Firebase project. Add android/app/google-services.json '
              'and rebuild. Step-by-step: docs/FIREBASE_SETUP.md in the project. '
              'Until then the app works fully offline.',
        );
      case SyncPhase.signedOut:
        body = _Panel(
          icon: Icons.cloud_outlined,
          title: 'Use your vault on more than one device',
          text:
              'Sign in with Google to keep an encrypted copy in the cloud. '
              'Google only identifies your account; your master password '
              'still unlocks everything.',
          action: FilledButton.icon(
            onPressed: ctl.signIn,
            icon: const Icon(Icons.login),
            label: const Text('Sign in with Google'),
          ),
        );
      case SyncPhase.checking:
        body = const Padding(
          padding: EdgeInsets.all(32),
          child: Center(child: CircularProgressIndicator()),
        );
      case SyncPhase.needsSetup:
        body = _Panel(
          icon: Icons.cloud_upload_outlined,
          title: 'No cloud vault yet',
          text:
              'Signed in as ${s.email ?? 'your Google account'}. Upload this device\'s vault, encrypted, to start syncing.',
          action: FilledButton.icon(
            onPressed: _create,
            icon: const Icon(Icons.lock_outline),
            label: const Text('Create cloud vault'),
          ),
        );
      case SyncPhase.needsJoin:
        body = _Panel(
          icon: Icons.cloud_download_outlined,
          title: 'This account already has a cloud vault',
          text:
              'Join it with the master password from your other device. '
              'Records on this device are kept and merged in.',
          action: FilledButton.icon(
            onPressed: _join,
            icon: const Icon(Icons.link),
            label: const Text('Join cloud vault'),
          ),
        );
      case SyncPhase.ready:
      case SyncPhase.syncing:
        final syncing = s.phase == SyncPhase.syncing;
        final r = s.lastReport;
        body = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: ListTile(
                leading: Icon(
                  syncing ? Icons.sync : Icons.cloud_done_outlined,
                  color: scheme.primary,
                ),
                title: Text(syncing ? 'Syncing...' : 'Sync is on'),
                subtitle: Text(
                  '${s.email ?? 'Google account'}\n'
                  '${s.lastSync == null ? 'Not synced yet' : 'Last sync ${_ago(s.lastSync!)}'}'
                  '${r == null ? '' : ' - received ${r.applied}, sent ${r.pushed}'}',
                ),
                isThreeLine: true,
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: syncing ? null : ctl.syncNow,
              icon: const Icon(Icons.sync),
              label: const Text('Sync now'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: syncing ? null : _turnOff,
              child: const Text('Turn off sync'),
            ),
          ],
        );
      case SyncPhase.error:
        body = _Panel(
          icon: Icons.error_outline,
          title: 'Sync problem',
          text: s.message ?? 'Something went wrong.',
          action: FilledButton(
            onPressed: () => ctl.syncNow().then((_) {
              if (ref.read(syncControllerProvider).phase == SyncPhase.error) {
                ctl.checkCloud();
              }
            }),
            child: const Text('Try again'),
          ),
        );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Cloud sync')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            body,
            if (s.message != null && s.phase != SyncPhase.error) ...[
              const SizedBox(height: 12),
              Text(s.message!, style: TextStyle(color: scheme.error)),
            ],
            const SizedBox(height: 20),
            Text('How it protects you', style: text.titleMedium),
            const SizedBox(height: 8),
            const _Bullet(
              'Records are encrypted on this device (AES-256-GCM) before upload. '
              'Firebase never sees titles, usernames, passwords, notes or categories.',
            ),
            const _Bullet(
              'The server can see: your Google account, random record IDs, edit '
              'times, whether a record was deleted, and roughly how big each one is.',
            ),
            const _Bullet(
              'Your master password is never uploaded. The encrypted key header '
              'is, so use a long, unique master password: anyone with access to '
              'your Google/Firebase data could try to guess it offline.',
            ),
            const _Bullet(
              'If two devices edit the same record, the newer edit wins. '
              'Permanent deletes are remembered so they do not come back.',
            ),
            const _Bullet(
              'Changing the master password on one device does not change it on '
              'the others; new devices join with the newest one. Sync is not a '
              'backup: keep encrypted backups too.',
            ),
          ],
        ),
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({
    required this.icon,
    required this.title,
    required this.text,
    this.action,
  });
  final IconData icon;
  final String title;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 36, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 8),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(text),
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('•  '),
        Expanded(child: Text(text)),
      ],
    ),
  );
}
