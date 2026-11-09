import 'package:flutter/material.dart';

/// Brand blues taken from the design mockup.
const brandDeepBlue = Color(0xFF0B3C9E);
const brandBlue = Color(0xFF1558D6);

/// Blue background gradient used by the splash screen and app icon.
const splashGradient = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [Color(0xFF0B3C9E), Color(0xFF1558D6)],
);

/// Shield with a padlock. Drawn in code so it stays sharp at any size and is
/// also used to render the launcher-icon PNGs (see tool/gen_icons_test.dart).
///
/// [onDark] = white shield with a blue lock (for blue backgrounds); otherwise
/// a blue shield with a white lock (for light backgrounds).
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 96, this.onDark = false});
  final double size;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: CustomPaint(
        size: Size.square(size),
        painter: _LogoPainter(onDark),
      ),
    );
  }
}

class _LogoPainter extends CustomPainter {
  _LogoPainter(this.onDark);
  final bool onDark;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 100;
    Offset p(double x, double y) => Offset(x * s, y * s);

    final shield = Path()
      ..moveTo(50 * s, 5 * s)
      ..lineTo(88 * s, 19 * s)
      ..lineTo(88 * s, 48 * s)
      ..cubicTo(88 * s, 72 * s, 70 * s, 88 * s, 50 * s, 96 * s)
      ..cubicTo(30 * s, 88 * s, 12 * s, 72 * s, 12 * s, 48 * s)
      ..lineTo(12 * s, 19 * s)
      ..close();

    final fill = Paint()
      ..shader = onDark
          ? const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.white, Color(0xFFDCE7FF)],
            ).createShader(Offset.zero & size)
          : const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF2F6FE8), Color(0xFF0B3C9E)],
            ).createShader(Offset.zero & size);
    canvas.drawPath(shield, fill);

    final lockColor = onDark ? brandDeepBlue : Colors.white;
    final lock = Paint()..color = lockColor;
    // Body
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromPoints(p(33, 46), p(67, 73)),
        Radius.circular(5 * s),
      ),
      lock,
    );
    // Shackle
    final shackle = Paint()
      ..color = lockColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5.5 * s
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(
      Path()
        ..moveTo(41 * s, 46 * s)
        ..lineTo(41 * s, 38 * s)
        ..arcTo(
          Rect.fromCircle(center: p(50, 38), radius: 9 * s),
          3.14159,
          3.14159,
          false,
        )
        ..lineTo(59 * s, 46 * s),
      shackle,
    );
    // Keyhole
    final hole = Paint()
      ..color = onDark ? Colors.white : const Color(0xFF0B3C9E);
    canvas.drawCircle(p(50, 57), 3.6 * s, hole);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromPoints(p(48.4, 58), p(51.6, 66)),
        Radius.circular(1.2 * s),
      ),
      hole,
    );
  }

  @override
  bool shouldRepaint(_LogoPainter old) => old.onDark != onDark;
}
