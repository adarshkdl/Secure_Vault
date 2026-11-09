import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secure_vault/application/providers.dart';
import 'package:secure_vault/core/crypto/vault_crypto.dart';
import 'package:secure_vault/data/vault_repository.dart';
import 'package:secure_vault/presentation/app.dart';
import 'package:secure_vault/presentation/widgets/provider_icon.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('email form: no title/username/advanced; mail type, provider '
      'icon and several mobile numbers', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final dir = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('sv_email'),
    ))!;
    addTearDown(() {
      try {
        dir.deleteSync(recursive: true);
      } on FileSystemException {
        // Windows may still hold the file for a moment; it is only a temp dir.
      }
    });
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
    Future<void> settle() => tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 400)),
    );
    Future<void> pumpUntil(bool Function() done) async {
      for (var i = 0; i < 40 && !done(); i++) {
        await settle();
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    await settle();
    await tester.pump();
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

    await tester.tap(find.widgetWithText(FloatingActionButton, 'Add'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Email account').last);
    await tester.pumpAndSettle();

    // Removed fields are gone.
    expect(find.text('Title *'), findsNothing);
    expect(find.text('Username'), findsNothing);
    expect(find.text('Display name / provider'), findsNothing);
    expect(find.text('Advanced'), findsNothing);
    expect(find.text('IMAP server'), findsNothing);
    // Mail type defaults to Personal.
    expect(find.text('Personal'), findsWidgets);

    // Choose mail type Office and provider Gmail (shown with its icon).
    await tester.tap(find.byType(DropdownButtonFormField<String>).at(0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Office').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<String>).at(1));
    await tester.pumpAndSettle();
    expect(find.byType(ProviderIcon), findsWidgets);
    await tester.tap(find.text('Gmail').last);
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Email address'),
      'demo@example.test',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Password'),
      'Synthetic-Mail-Pass-1!',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Mobile number 1'),
      '+91 98765 43210',
    );
    await tester.tap(find.text('Add another number'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Mobile number 2'),
      '+91 91234 56789',
    );

    await tester.tap(find.text('Save').first);
    await tester.pump();
    await pumpUntil(() => find.text('Mobile number 1').evaluate().isEmpty);
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(MaterialApp)),
    );
    final c = container.read(vaultProvider).data!.credentials.single;
    expect(c.title, 'demo@example.test'); // title comes from the address
    expect(c.values['mail_type'], 'Office');
    expect(c.values['provider'], 'Gmail');
    expect(c.values['recovery_phone'], '+91 98765 43210\n+91 91234 56789');

    // The list shows provider name + mail type and the provider icon.
    expect(find.text('demo@example.test'), findsWidgets);
    expect(find.text('Gmail · Office'), findsWidgets);
    expect(find.byType(ProviderIcon), findsWidgets);

    // Detail shows each number on its own row.
    await tester.tap(find.text('demo@example.test').first);
    await tester.pumpAndSettle();
    expect(find.text('Mobile number 1'), findsOneWidget);
    expect(find.text('+91 91234 56789'), findsOneWidget);
  });
}
