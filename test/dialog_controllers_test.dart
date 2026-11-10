import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secure_vault/presentation/widgets/dialog_controllers.dart';

/// Regression test for "A TextEditingController was used after being
/// disposed": dialogs used to dispose their controller as soon as
/// `showDialog` returned, while the dialog was still animating out. On a
/// device the keyboard hides at that moment, which rebuilds the closing
/// dialog with the disposed controller and breaks the widget tree (this
/// stopped "Create cloud vault" from completing).
void main() {
  Future<String?> openAndSubmit(
    WidgetTester tester,
    Future<String?> Function(BuildContext) show,
  ) async {
    late BuildContext ctx;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (c) {
            ctx = c;
            return const Scaffold();
          },
        ),
      ),
    );
    // Keyboard is up while typing.
    tester.view.viewInsets = const FakeViewPadding(bottom: 600);
    addTearDown(tester.view.reset);

    final result = show(ctx);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Synthetic-Pass-123!');
    await tester.tap(find.text('OK'));
    await tester.pump(); // pop starts the closing animation

    // Keyboard hides mid-animation -> the closing dialog rebuilds.
    tester.view.viewInsets = FakeViewPadding.zero;
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 30));
    }
    await tester.pumpAndSettle();
    return result;
  }

  Widget dialog(BuildContext ctx, TextEditingController c) => AlertDialog(
    content: TextField(controller: c),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(ctx, c.text),
        child: const Text('OK'),
      ),
    ],
  );

  // The old pattern (create a controller, `await showDialog`, then dispose it)
  // fails this same scenario with "used after being disposed"; that was
  // verified by hand. It is not kept as a test because the framework error
  // cascade leaves the test binding in a broken state.
  testWidgets('DialogControllers keeps the controller alive until closed', (
    tester,
  ) async {
    final r = await openAndSubmit(
      tester,
      (ctx) => showDialog<String>(
        context: ctx,
        builder: (d) => DialogControllers(builder: (d, cs) => dialog(d, cs[0])),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(r, 'Synthetic-Pass-123!');
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('DialogControllers applies initial texts', (tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (c) {
            ctx = c;
            return const Scaffold();
          },
        ),
      ),
    );
    showDialog<void>(
      context: ctx,
      builder: (d) => DialogControllers(
        initialTexts: const ['Field A', ''],
        builder: (d, cs) => AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: cs[0]),
              TextField(controller: cs[1]),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Field A'), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(2));
  });
}
