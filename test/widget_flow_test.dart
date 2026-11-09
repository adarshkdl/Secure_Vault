import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secure_vault/application/providers.dart';
import 'package:secure_vault/core/crypto/vault_crypto.dart';
import 'package:secure_vault/data/vault_repository.dart';
import 'package:secure_vault/presentation/app.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('setup -> add credential -> lock -> unlock', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final dir = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('sv_widget'),
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
        ],
        child: const SecureVaultApp(),
      ),
    );
    // Crypto uses isolates, so wait on the real event loop.
    Future<void> settle() => tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 400)),
    );

    await settle();
    Future<void> pumpUntil(bool Function() done) async {
      for (var i = 0; i < 40 && !done(); i++) {
        await settle();
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    await tester.pump();
    expect(find.text('Welcome to SecureVault'), findsOneWidget);

    // Weak password is rejected with an inline error.
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Master password'),
      'short',
    );
    await tester.tap(find.text('Create vault'));
    await tester.pump();
    expect(find.text('Use at least 10 characters'), findsOneWidget);

    const pw = 'Synthetic-Test-Pass-42!';
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Master password'),
      pw,
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Confirm master password'),
      pw,
    );
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump();
    await tester.tap(find.text('Create vault'));
    await tester.pump();
    await pumpUntil(
      () => find.text('Your vault is empty').evaluate().isNotEmpty,
    );
    expect(find.text('Your vault is empty'), findsOneWidget);

    // Add a Wi-Fi record through the UI (no Title box: the SSID is the title).
    await tester.tap(find.widgetWithText(FloatingActionButton, 'Add'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Wi-Fi').last);
    await tester.pumpAndSettle();
    expect(find.text('Title *'), findsNothing);
    expect(find.text('Router / admin URL or IP'), findsNothing);
    expect(find.text('Add custom field'), findsNothing);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Network (SSID)'),
      'OfficeNet',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Password'),
      'Synthetic-Wifi-Pass-1!',
    );
    await tester.tap(find.text('Save').first);
    await tester.pump();
    await pumpUntil(() => find.text('Network (SSID)').evaluate().isEmpty);
    await tester.pumpAndSettle();

    // Title shows in the list; the password never does.
    expect(find.text('OfficeNet'), findsWidgets);
    expect(find.textContaining('Synthetic-Wifi-Pass-1!'), findsNothing);

    // Open detail: secret is masked until revealed.
    await tester.tap(find.text('OfficeNet').first);
    await tester.pumpAndSettle();
    expect(find.text('Synthetic-Wifi-Pass-1!'), findsNothing);
    expect(find.text('••••••••••'), findsOneWidget);
    await tester.tap(find.byTooltip('Reveal Password'));
    await tester.pump();
    expect(find.text('Synthetic-Wifi-Pass-1!'), findsOneWidget);
    await tester.tap(find.byTooltip('Hide Password'));
    await tester.pump();
    expect(find.text('Synthetic-Wifi-Pass-1!'), findsNothing);

    // Locking dismisses pushed screens and shows the lock screen.
    final container = ProviderScope.containerOf(
      tester.element(find.byType(MaterialApp)),
    );
    container.read(vaultProvider.notifier).lock();
    await tester.pumpAndSettle();
    expect(find.text('Unlock Your Vault'), findsOneWidget);
    expect(find.text('OfficeNet'), findsNothing);

    // Wrong password, then the correct one.
    await tester.enterText(find.byType(TextFormField), 'wrong-wrong-wrong');
    await tester.tap(find.text('Unlock'));
    await tester.pump();
    await pumpUntil(
      () => find.text('Incorrect master password.').evaluate().isNotEmpty,
    );
    expect(find.text('Incorrect master password.'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField), pw);
    await tester.tap(find.text('Unlock'));
    await tester.pump();
    await pumpUntil(() => find.text('Unlock Your Vault').evaluate().isEmpty);
    expect(find.text('Unlock Your Vault'), findsNothing);
    expect(find.text('Categories'), findsWidgets);
  });
}
