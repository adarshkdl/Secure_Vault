import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers.dart';
import '../helpers.dart';
import '../widgets/app_logo.dart';
import '../widgets/password_widgets.dart';

class UnlockScreen extends ConsumerStatefulWidget {
  const UnlockScreen({super.key});

  @override
  ConsumerState<UnlockScreen> createState() => _UnlockScreenState();
}

class _UnlockScreenState extends ConsumerState<UnlockScreen> {
  final _pw = TextEditingController();
  Timer? _tick;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted &&
          ref.read(vaultProvider.notifier).lockoutRemaining() != null) {
        setState(() {});
      }
    });
    if (ref.read(settingsProvider).biometricEnabled) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _biometric());
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    _pw.dispose();
    super.dispose();
  }

  Future<void> _biometric() async {
    final vault = ref.read(vaultProvider.notifier);
    final r = await ref.read(lockGuardProvider).run(vault.unlockWithBiometric);
    if (!mounted || r == UnlockResult.ok) return;
    setState(
      () => _error = 'Biometric unlock unavailable. Use your master password.',
    );
  }

  Future<void> _unlock() async {
    if (_pw.text.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final r = await ref.read(vaultProvider.notifier).unlock(_pw.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      switch (r) {
        case UnlockResult.ok:
          break;
        case UnlockResult.wrongPassword:
          _error = 'Incorrect master password.';
          _pw.clear();
        case UnlockResult.lockedOut:
          _error = 'Too many attempts.';
        case UnlockResult.error:
          _error = 'The vault could not be opened. The file may be damaged.';
      }
    });
  }

  String _fmt(Duration d) {
    final m = d.inMinutes, s = d.inSeconds % 60;
    return m > 0 ? '${m}m ${s}s' : '${s}s';
  }

  @override
  Widget build(BuildContext context) {
    final vault = ref.watch(vaultProvider);
    final remaining = ref.read(vaultProvider.notifier).lockoutRemaining();
    final bio = ref.watch(settingsProvider.select((s) => s.biometricEnabled));
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: AppLogo(
                      size: 96,
                      onDark: Theme.of(context).brightness == Brightness.dark,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'SecureVault',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineMedium
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Unlock Your Vault',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 24),
                  SecretTextField(
                    controller: _pw,
                    label: 'Master password',
                    autofocus: !bio,
                    onSubmitted: (_) => _unlock(),
                    textInputAction: TextInputAction.done,
                  ),
                  if (_error != null || remaining != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        remaining != null
                            ? 'Too many failed attempts. Try again in ${_fmt(remaining)}.'
                            : _error!,
                        style: TextStyle(color: scheme.error),
                        textAlign: TextAlign.center,
                      ),
                    )
                  else if (vault.failedAttempts > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        '${vault.failedAttempts} failed attempt(s).',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: (_busy || remaining != null) ? null : _unlock,
                    child: _busy
                        ? const SizedBox(
                            height: 22,
                            width: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Unlock'),
                  ),
                  if (bio) ...[
                    const SizedBox(height: 16),
                    const Row(
                      children: [
                        Expanded(child: Divider()),
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: 12),
                          child: Text('or'),
                        ),
                        Expanded(child: Divider()),
                      ],
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: _biometric,
                      icon: const Icon(Icons.fingerprint),
                      label: const Text('Use Fingerprint / Face'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
