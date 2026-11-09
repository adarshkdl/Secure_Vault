// Renders the launcher-icon and splash PNGs from the in-code logo.
// Run:  flutter test tool/gen_icons_test.dart
// Then: dart run flutter_launcher_icons && dart run flutter_native_splash:create
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secure_vault/presentation/widgets/app_logo.dart';

Future<void> _render(
  WidgetTester tester,
  String path,
  Widget child,
) async {
  const side = 1024.0;
  tester.view.physicalSize = const Size(side, side);
  tester.view.devicePixelRatio = 1.0;
  final key = GlobalKey();
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: RepaintBoundary(
          key: key,
          child: SizedBox(width: side, height: side, child: child),
        ),
      ),
    ),
  );
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    File(path)
      ..createSync(recursive: true)
      ..writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

void main() {
  testWidgets('render icon PNGs', (tester) async {
    addTearDown(tester.view.reset);
    // Full-bleed legacy / iOS icon: logo on the blue gradient.
    await _render(
      tester,
      'assets/icon/icon.png',
      const DecoratedBox(
        decoration: BoxDecoration(gradient: splashGradient),
        child: Center(child: AppLogo(size: 640, onDark: true)),
      ),
    );
    // Adaptive-icon foreground: transparent, logo inside the safe zone.
    await _render(
      tester,
      'assets/icon/icon_foreground.png',
      const Center(child: AppLogo(size: 560, onDark: true)),
    );
    // Native splash logo: transparent background.
    await _render(
      tester,
      'assets/icon/splash_logo.png',
      const Center(child: AppLogo(size: 600, onDark: true)),
    );
  });
}
