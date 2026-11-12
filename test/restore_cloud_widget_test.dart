import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secure_vault/application/providers.dart';
import 'package:secure_vault/application/sync_controller.dart';
import 'package:secure_vault/core/crypto/vault_crypto.dart';
import 'package:secure_vault/data/vault_repository.dart';
import 'package:secure_vault/presentation/app.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'sync_flow_test.dart' show FakeAuth, MemSyncStore, cred, device;
import 'sync_test.dart' show FakeRemote;

// Synthetic data only.
void main() {
  testWidgets('reinstall: restore the vault from the cloud on first launch', (
    tester,
  ) async {
    const pw = 'Synthetic-Pass-Reinstall-7!';
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final remote = FakeRemote();

    // The "old install": a vault with two records, synced to the cloud.
    await tester.runAsync(() async {
      final old = await device(prefs, remote, FakeAuth());
      final v = old.read(vaultProvider.notifier);
      await v.createVault(pw);
      await v.saveCredential(cred('w1', 'Home Mail'));
      await v.saveCredential(cred('w2', 'Office Router'));
      final s = old.read(syncControllerProvider.notifier);
      await s.signIn();
      expect(await s.createCloudVault(pw), isNull);
    });
    expect(remote.items.keys, containsAll(['w1', 'w2']));

    // The "new install": empty app data, same Google account.
    final dir = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('sv_restore'),
    ))!;
    addTearDown(() => dir.deleteSync(recursive: true));
    tester.view.physicalSize = const Size(900, 3000);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPrefsProvider.overrideWithValue(prefs),
          splashMinDurationProvider.overrideWithValue(Duration.zero),
          vaultDirProvider.overrideWithValue(dir),
          repositoryProvider.overrideWith(
            (ref) => VaultRepository(
              dir,
              kdfFactory: () => KdfParams.fresh(memoryKiB: 64, iterations: 1),
            ),
          ),
          firebaseReadyProvider.overrideWithValue(true),
          syncAuthProvider.overrideWithValue(FakeAuth()),
          syncRemoteFactoryProvider.overrideWithValue((_) => remote),
          syncStoreProvider.overrideWithValue(MemSyncStore(prefs)),
        ],
        child: const SecureVaultApp(),
      ),
    );
    Future<void> settle() => tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 400)),
    );
    Future<void> pumpUntil(bool Function() done) async {
      for (var i = 0; i < 60 && !done(); i++) {
        await settle();
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    await settle();
    await tester.pump();
    expect(find.text('Welcome to SecureVault'), findsOneWidget);

    await tester.tap(find.text('Restore from cloud'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sign in with Google'));
    await tester.pump();
    await pumpUntil(() => find.text('Restore vault').evaluate().isNotEmpty);
    expect(find.textContaining('Cloud vault found'), findsOneWidget);

    // Wrong password: an error, and still no vault on the device.
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Master password'),
      'wrong-password-xx',
    );
    await tester.tap(find.text('Restore vault'));
    await tester.pump();
    await pumpUntil(
      () => find
          .text('Wrong master password for the cloud vault.')
          .evaluate()
          .isNotEmpty,
    );
    expect(
      find.text('Wrong master password for the cloud vault.'),
      findsOneWidget,
    );
    expect(
      await tester.runAsync(() => File('${dir.path}/vault.bin').exists()),
      isFalse,
    );

    // Correct password: the records are back on the home screen.
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Master password'),
      pw,
    );
    await tester.tap(find.text('Restore vault'));
    await tester.pump();
    await pumpUntil(() => find.text('Home Mail').evaluate().isNotEmpty);
    await tester.pumpAndSettle();
    expect(find.text('Restore from cloud'), findsNothing);
    expect(find.text('Home Mail'), findsWidgets);
    expect(find.text('Office Router'), findsWidgets);
    // Secrets are never shown in list previews.
    expect(find.textContaining('synthetic-w1'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
