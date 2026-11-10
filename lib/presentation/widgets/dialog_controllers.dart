import 'package:flutter/widgets.dart';

/// Owns the [TextEditingController]s used inside a dialog.
///
/// Put this at the top of a `showDialog` builder instead of creating
/// controllers in the calling function. The controllers are disposed in
/// [State.dispose], which runs only after the dialog route has finished its
/// closing animation. Disposing them as soon as `showDialog` returns is a bug:
/// the dialog is still on screen animating out and rebuilds with the disposed
/// controller ("A TextEditingController was used after being disposed").
///
/// Return values the caller needs (for example the typed password) through
/// `Navigator.pop`, not by reading a controller after the dialog closes.
class DialogControllers extends StatefulWidget {
  const DialogControllers({
    super.key,
    this.initialTexts = const [''],
    required this.builder,
  });

  /// One controller is created per entry, starting with that text.
  final List<String> initialTexts;

  final Widget Function(
    BuildContext context,
    List<TextEditingController> controllers,
  )
  builder;

  @override
  State<DialogControllers> createState() => _DialogControllersState();
}

class _DialogControllersState extends State<DialogControllers> {
  late final List<TextEditingController> _controllers = [
    for (final t in widget.initialTexts) TextEditingController(text: t),
  ];

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _controllers);
}
