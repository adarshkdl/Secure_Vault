import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers.dart';
import '../../application/sync_controller.dart';
import '../helpers.dart';
import '../widgets/password_widgets.dart';
import 'restore_cloud_screen.dart';

class SetupScreen extends ConsumerStatefulWidget {
  const SetupScreen({super.key});

  @override
  ConsumerState<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends ConsumerState<SetupScreen> {
  final _form = GlobalKey<FormState>();
  final _pw = TextEditingController();
  final _confirm = TextEditingController();
  bool _understood = false;
  bool _busy = false;

  @override
  void dispose() {
    _pw.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (!_form.currentState!.validate()) return;
    if (!_understood) {
      showSnack(context, 'Please confirm you understand the warning.');
      return;
    }
    setState(() => _busy = true);
    final vault = ref.read(vaultProvider.notifier);
    await vault.createVault(_pw.text);
    if (!mounted) return;
    // Offer biometrics only after the master password exists.
    if (await vault.biometricsAvailable() && mounted) {
      final enable = await confirmDialog(
        context,
        title: 'Enable biometric unlock?',
        message: 'You can unlock with your fingerprint or face. Your master password will still be required as a fallback.',
        confirmLabel: 'Enable',
      );
      if (enable) await ref.read(lockGuardProvider).run(vault.enableBiometric);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final cloudAvailable = ref.watch(firebaseReadyProvider);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Form(
                key: _form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(
                      Icons.shield_outlined,
                      size: 72,
                      color: scheme.primary,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Welcome to SecureVault',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      cloudAvailable
                          ? 'Your credentials are encrypted and stored on this device. No account is needed; encrypted cloud sync is optional.'
                          : 'Your credentials are encrypted and stored only on this device. There is no account and no cloud sync.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                    const SizedBox(height: 24),
                    Card(
                      color: scheme.errorContainer,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.warning_amber,
                              color: scheme.onErrorContainer,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'If you forget your master password, your vault cannot be recovered. Only an encrypted backup (with its own passphrase) can restore your data.',
                                style: TextStyle(
                                  color: scheme.onErrorContainer,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    SecretTextField(
                      controller: _pw,
                      label: 'Master password',
                      textInputAction: TextInputAction.next,
                      onChanged: (_) => setState(() {}),
                      validator: (v) => validateNewSecret(v, name: 'password'),
                      helperText: 'At least 10 characters. A long passphrase works well.',
                    ),
                    StrengthMeter(password: _pw.text),
                    const SizedBox(height: 16),
                    SecretTextField(
                      controller: _confirm,
                      label: 'Confirm master password',
                      validator: (v) =>
                          v == _pw.text ? null : 'Passwords do not match',
                      onSubmitted: (_) => _create(),
                    ),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      value: _understood,
                      onChanged: (v) =>
                          setState(() => _understood = v ?? false),
                      title: const Text(
                        'I understand the vault cannot be recovered without my master password or a valid backup.',
                      ),
                    ),
                    const SizedBox(height: 8),
                    FilledButton(
                      onPressed: _busy ? null : _create,
                      child: _busy
                          ? const SizedBox(
                              height: 22,
                              width: 22,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Create vault'),
                    ),
                    if (cloudAvailable) ...[
                      const SizedBox(height: 24),
                      const Divider(),
                      const SizedBox(height: 12),
                      Text(
                        'Reinstalled the app or using a new phone? If you turned on cloud sync before, get your vault back.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: _busy
                            ? null
                            : () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => const RestoreCloudScreen(),
                                ),
                              ),
                        icon: const Icon(Icons.cloud_download_outlined),
                        label: const Text('Restore from cloud'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
