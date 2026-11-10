import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers.dart';
import '../../application/sync_controller.dart';
import '../helpers.dart';
import '../widgets/password_widgets.dart';

enum _Step { signIn, checking, noCloudVault, password, restoring }

/// Fresh install (no vault on this device): sign in with the Google account
/// used for cloud sync and unlock the cloud vault with its master password.
/// The vault is then rebuilt on this device and sync stays on.
class RestoreCloudScreen extends ConsumerStatefulWidget {
  const RestoreCloudScreen({super.key});

  @override
  ConsumerState<RestoreCloudScreen> createState() => _RestoreCloudScreenState();
}

class _RestoreCloudScreenState extends ConsumerState<RestoreCloudScreen> {
  final _pw = TextEditingController();
  _Step _step = _Step.signIn;
  String? _error;

  SyncController get _sync => ref.read(syncControllerProvider.notifier);

  @override
  void initState() {
    super.initState();
    if (ref.read(syncAuthProvider)?.currentUser != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _lookForVault());
    }
  }

  @override
  void dispose() {
    _pw.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    setState(() {
      _step = _Step.checking;
      _error = null;
    });
    await _sync.signIn();
    if (!mounted) return;
    if (ref.read(syncAuthProvider)?.currentUser == null) {
      setState(() {
        _step = _Step.signIn;
        _error = ref.read(syncControllerProvider).message;
      });
      return;
    }
    await _lookForVault();
  }

  Future<void> _lookForVault() async {
    setState(() {
      _step = _Step.checking;
      _error = null;
    });
    try {
      final found = await _sync.hasCloudVault();
      if (!mounted) return;
      setState(() => _step = found ? _Step.password : _Step.noCloudVault);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _step = _Step.signIn;
        _error = _sync.describeError(e);
      });
    }
  }

  Future<void> _restore() async {
    if (_pw.text.isEmpty) {
      setState(() => _error = 'Enter your master password.');
      return;
    }
    setState(() {
      _step = _Step.restoring;
      _error = null;
    });
    final err = await _sync.restoreFromCloud(_pw.text);
    if (!mounted) return;
    if (err != null) {
      setState(() {
        _step = _Step.password;
        _error = err;
      });
      return;
    }
    _pw.clear();
    final count = ref.read(vaultProvider).data?.credentials.length ?? 0;
    final vault = ref.read(vaultProvider.notifier);
    // Same as first-time setup: offer biometrics once a master password exists.
    if (await vault.biometricsAvailable() && mounted) {
      final enable = await confirmDialog(
        context,
        title: 'Enable biometric unlock?',
        message: 'You can unlock with your fingerprint or face. Your master password will still be required as a fallback.',
        confirmLabel: 'Enable',
      );
      if (enable) await ref.read(lockGuardProvider).run(vault.enableBiometric);
    }
    if (!mounted) return;
    showSnack(
      context,
      'Restored $count record${count == 1 ? '' : 's'} from the cloud.',
    );
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  Future<void> _useOtherAccount() async {
    await _sync.disable();
    if (!mounted) return;
    setState(() {
      _step = _Step.signIn;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final email = ref.watch(syncControllerProvider).email;

    final Widget body = switch (_step) {
      _Step.signIn => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Sign in with the Google account you used for cloud sync. '
            'Your records come back encrypted and are unlocked on this phone '
            'with your master password.',
            style: text.bodyLarge,
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _signIn,
            icon: const Icon(Icons.login),
            label: const Text('Sign in with Google'),
          ),
        ],
      ),
      _Step.checking || _Step.restoring => Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(
              _step == _Step.restoring
                  ? 'Unlocking and downloading your vault...'
                  : 'Looking for your cloud vault...',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
      _Step.noCloudVault => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'No cloud vault was found for ${email ?? 'this account'}. '
            'Cloud sync may have been turned on with a different Google account, '
            'or the cloud copy was erased.',
            style: text.bodyLarge,
          ),
          const SizedBox(height: 20),
          OutlinedButton(
            onPressed: _useOtherAccount,
            child: const Text('Use a different Google account'),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Create a new vault instead'),
          ),
        ],
      ),
      _Step.password => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Cloud vault found for ${email ?? 'your account'}.',
            style: text.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Enter the master password of your cloud vault. It becomes the '
            'master password on this phone too.',
            style: text.bodyLarge,
          ),
          const SizedBox(height: 16),
          SecretTextField(
            controller: _pw,
            label: 'Master password',
            autofocus: true,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _restore(),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _restore,
            icon: const Icon(Icons.cloud_download_outlined),
            label: const Text('Restore vault'),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _useOtherAccount,
            child: const Text('Use a different Google account'),
          ),
        ],
      ),
    };

    return Scaffold(
      appBar: AppBar(title: const Text('Restore from cloud')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Icon(
              Icons.cloud_download_outlined,
              size: 64,
              color: scheme.primary,
            ),
            const SizedBox(height: 16),
            body,
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: scheme.error)),
            ],
          ],
        ),
      ),
    );
  }
}
