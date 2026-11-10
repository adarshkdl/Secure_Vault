import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers.dart';
import '../../application/sync_controller.dart';
import '../helpers.dart';
import '../widgets/password_widgets.dart';
import 'backup_screen.dart';
import 'deleted_screen.dart';
import 'import_screen.dart';
import 'info_screen.dart';
import 'qr/qr_receive_screen.dart';
import 'sync_screen.dart';

class SettingsTab extends ConsumerWidget {
  const SettingsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final ctl = ref.read(settingsProvider.notifier);
    final vault = ref.read(vaultProvider.notifier);

    Widget header(String t) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: Text(
        t,
        style: Theme.of(context).textTheme.titleSmall
            ?.copyWith(color: Theme.of(context).colorScheme.primary),
      ),
    );

    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        header('Security'),
        ListTile(
          leading: const Icon(Icons.password),
          title: const Text('Change master password'),
          onTap: () => _changePassword(context, ref),
        ),
        SwitchListTile(
          secondary: const Icon(Icons.fingerprint),
          title: const Text('Biometric unlock'),
          subtitle: const Text('Master password stays as fallback'),
          value: s.biometricEnabled,
          onChanged: (v) async {
            if (v) {
              if (!await reauthenticate(
                context,
                ref,
                passwordOnly: true,
                reason: 'Enter your master password to enable biometrics',
              )) {
                return;
              }
              final ok = await ref
                  .read(lockGuardProvider)
                  .run(vault.enableBiometric);
              if (!ok && context.mounted) {
                showSnack(
                  context,
                  'Biometrics are not available or were not confirmed.',
                );
              }
            } else {
              await vault.disableBiometric();
            }
          },
        ),
        ListTile(
          leading: const Icon(Icons.timer_outlined),
          title: const Text('Auto-lock after inactivity'),
          trailing: DropdownButton<int>(
            value: [1, 2, 5, 15, 30].contains(s.autoLockMinutes)
                ? s.autoLockMinutes
                : 2,
            underline: const SizedBox(),
            items: [
              for (final m in [1, 2, 5, 15, 30])
                DropdownMenuItem(value: m, child: Text('$m min')),
            ],
            onChanged: (v) => ctl.update(s.copyWith(autoLockMinutes: v)),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.event_outlined),
          title: const Text('Expiry reminders'),
          subtitle: const Text('Shown in the app only, never as notifications'),
          trailing: DropdownButton<int>(
            value: [0, 7, 14, 30, 60, 90].contains(s.expiryLeadDays)
                ? s.expiryLeadDays
                : 30,
            underline: const SizedBox(),
            items: [
              for (final d in [0, 7, 14, 30, 60, 90])
                DropdownMenuItem(
                  value: d,
                  child: Text(d == 0 ? 'Off' : '$d days'),
                ),
            ],
            onChanged: (v) => ctl.update(s.copyWith(expiryLeadDays: v)),
          ),
        ),
        SwitchListTile(
          secondary: const Icon(Icons.phonelink_lock),
          title: const Text('Lock when app is backgrounded'),
          value: s.lockOnBackground,
          onChanged: (v) => ctl.update(s.copyWith(lockOnBackground: v)),
        ),
        SwitchListTile(
          secondary: const Icon(Icons.verified_user_outlined),
          title: const Text('Re-authenticate to reveal or copy secrets'),
          value: s.requireAuthForSecrets,
          onChanged: (v) => ctl.update(s.copyWith(requireAuthForSecrets: v)),
        ),
        ListTile(
          leading: const Icon(Icons.content_paste_off_outlined),
          title: const Text('Clear clipboard after'),
          subtitle: const Text(
            'Other apps may read the clipboard until it clears',
          ),
          trailing: DropdownButton<int>(
            value: [0, 10, 30, 60, 120].contains(s.clipboardClearSeconds)
                ? s.clipboardClearSeconds
                : 30,
            underline: const SizedBox(),
            items: const [
              DropdownMenuItem(value: 0, child: Text('Never')),
              DropdownMenuItem(value: 10, child: Text('10 s')),
              DropdownMenuItem(value: 30, child: Text('30 s')),
              DropdownMenuItem(value: 60, child: Text('1 min')),
              DropdownMenuItem(value: 120, child: Text('2 min')),
            ],
            onChanged: (v) => ctl.update(s.copyWith(clipboardClearSeconds: v)),
          ),
        ),
        header('Appearance'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: SegmentedButton<ThemeMode>(
            segments: const [
              ButtonSegment(
                value: ThemeMode.system,
                label: Text('System'),
                icon: Icon(Icons.brightness_auto),
              ),
              ButtonSegment(
                value: ThemeMode.light,
                label: Text('Light'),
                icon: Icon(Icons.light_mode),
              ),
              ButtonSegment(
                value: ThemeMode.dark,
                label: Text('Dark'),
                icon: Icon(Icons.dark_mode),
              ),
            ],
            selected: {s.themeMode},
            onSelectionChanged: (v) =>
                ctl.update(s.copyWith(themeMode: v.first)),
          ),
        ),
        header('Data'),
        Consumer(
          builder: (context, ref, _) {
            final st = ref.watch(syncControllerProvider);
            final sub = switch (st.phase) {
              SyncPhase.unavailable => 'Not set up in this build',
              SyncPhase.signedOut || SyncPhase.checking => 'Off',
              SyncPhase.needsSetup || SyncPhase.needsJoin => 'Finish setup',
              SyncPhase.error => 'Problem - tap for details',
              SyncPhase.ready || SyncPhase.syncing => 'On - ${st.email ?? ''}',
            };
            return ListTile(
              leading: const Icon(Icons.cloud_sync_outlined),
              title: const Text('Cloud sync'),
              subtitle: Text('Encrypted, via Firebase. $sub'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const SyncScreen()),
              ),
            );
          },
        ),
        ListTile(
          leading: const Icon(Icons.backup_outlined),
          title: const Text('Backup & restore'),
          subtitle: const Text('Encrypted backup file you transfer yourself'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const BackupHomeScreen()),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.upload_file_outlined),
          title: const Text('Import passwords'),
          subtitle: const Text('From Bitwarden, 1Password, Chrome or CSV'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(
            context,
          ).push(MaterialPageRoute<void>(builder: (_) => const ImportScreen())),
        ),
        ListTile(
          leading: const Icon(Icons.qr_code_scanner),
          title: const Text('Receive by QR'),
          subtitle: const Text('Get one item from another device, encrypted'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const QrReceiveScreen()),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.delete_sweep_outlined),
          title: const Text('Recently deleted'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const DeletedScreen()),
          ),
        ),
        header('About'),
        ListTile(
          leading: const Icon(Icons.privacy_tip_outlined),
          title: const Text('Security & privacy'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(
            context,
          ).push(MaterialPageRoute<void>(builder: (_) => const InfoScreen())),
        ),
        const ListTile(
          leading: Icon(Icons.info_outline),
          title: Text('SecureVault'),
          subtitle: Text('Version 1.0.0  -  offline, no account, no analytics'),
        ),
        header('Danger zone'),
        ListTile(
          leading: const Icon(Icons.lock_outline),
          title: const Text('Lock now'),
          onTap: vault.lock,
        ),
        ListTile(
          leading: Icon(
            Icons.delete_forever,
            color: Theme.of(context).colorScheme.error,
          ),
          title: Text(
            'Erase vault and all data',
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
          onTap: () => _wipe(context, ref),
        ),
      ],
    );
  }

  Future<void> _wipe(BuildContext context, WidgetRef ref) async {
    final ok = await confirmDialog(
      context,
      title: 'Erase everything?',
      message: 'This permanently deletes your vault, settings and biometric key from this device. Without a backup there is no way to recover it.',
      confirmLabel: 'Continue',
      destructive: true,
    );
    if (!ok || !context.mounted) return;
    if (!await reauthenticate(
      context,
      ref,
      passwordOnly: true,
      reason: 'Enter your master password to erase the vault',
    )) {
      return;
    }
    if (!context.mounted) return;
    final c = TextEditingController();
    final typed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Final confirmation'),
        content: TextField(
          controller: c,
          decoration: const InputDecoration(labelText: 'Type ERASE to confirm'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              minimumSize: const Size(88, 44),
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, c.text.trim() == 'ERASE'),
            child: const Text('Erase'),
          ),
        ],
      ),
    );
    c.dispose();
    if (typed == true) await ref.read(vaultProvider.notifier).wipeEverything();
  }

  Future<void> _changePassword(BuildContext context, WidgetRef ref) async {
    if (!await reauthenticate(
      context,
      ref,
      passwordOnly: true,
      reason: 'Enter your current master password',
    )) {
      return;
    }
    if (!context.mounted) return;
    final pw = TextEditingController(), cf = TextEditingController();
    final key = GlobalKey<FormState>();
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('New master password'),
          content: Form(
            key: key,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SecretTextField(
                    controller: pw,
                    label: 'New master password',
                    autofocus: true,
                    onChanged: (_) => setS(() {}),
                    validator: (v) => validateNewSecret(v),
                  ),
                  StrengthMeter(password: pw.text),
                  const SizedBox(height: 12),
                  SecretTextField(
                    controller: cf,
                    label: 'Confirm',
                    validator: (v) =>
                        v == pw.text ? null : 'Passwords do not match',
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(88, 44)),
              onPressed: () {
                if (key.currentState!.validate()) Navigator.pop(ctx, true);
              },
              child: const Text('Change'),
            ),
          ],
        ),
      ),
    );
    final newPw = pw.text;
    pw.dispose();
    cf.dispose();
    if (go != true) return;
    final syncOn = ref.read(syncStoreProvider).enabledUid != null;
    await ref
        .read(vaultProvider.notifier)
        .changeMasterPassword(newPw, cloudStrength: syncOn);
    if (syncOn) {
      await ref.read(syncControllerProvider.notifier).onPasswordChanged();
    }
    if (context.mounted) showSnack(context, 'Master password changed.');
  }
}
