import 'package:flutter/material.dart';

class InfoScreen extends StatelessWidget {
  const InfoScreen({super.key});

  @override
  Widget build(BuildContext context) {
    Widget h(String t) => Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 6),
      child: Text(t, style: Theme.of(context).textTheme.titleMedium),
    );
    return Scaffold(
      appBar: AppBar(title: const Text('Security & privacy')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            h('How your data is protected'),
            const Text(
              '- The whole vault (titles, fields, notes) is encrypted with AES-256-GCM.\n'
              '- The encryption key is random and is protected by a key derived from your master password with Argon2id.\n'
              '- Your master password is never stored.\n'
              '- Biometric unlock keeps the vault key in the Android Keystore / iOS Keychain, released only after a successful biometric check.\n'
              '- Wrong password attempts are slowed down progressively.',
            ),
            h('Privacy'),
            const Text(
              '- No account, no cloud, no analytics, no ads.\n'
              '- Nothing leaves the device unless you share or export it.\n'
              '- Search runs in memory after unlock; no plaintext search index is written to disk.\n'
              '- Android blocks screenshots and hides the app-switcher preview.',
            ),
            h('Limits you should know'),
            const Text(
              '- If you forget the master password and have no backup, data cannot be recovered.\n'
              '- Clipboard clearing only works while the app is running, and other apps may read the clipboard before it clears.\n'
              '- Once you share something, the recipient can copy or photograph it.\n'
              '- A device that is rooted, jailbroken or infected with malware may defeat these protections.\n'
              '- Backups are snapshots. There is no live sync between devices.',
            ),
            h('Not yet verified'),
            const Text(
              'This app has not had an independent security review. Do not rely on it for high-value secrets until it has.',
            ),
          ],
        ),
      ),
    );
  }
}
