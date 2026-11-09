import 'dart:async';

import 'package:flutter/services.dart';

/// Copies one value and clears the clipboard after a delay, but only if the
/// clipboard still holds what we put there. The timer only runs while the
/// app process is alive; the UI warns about this limitation.
class ClipboardService {
  Timer? _timer;

  Future<void> copy(String value, {required int clearAfterSeconds}) async {
    _timer?.cancel();
    await Clipboard.setData(ClipboardData(text: value));
    if (clearAfterSeconds > 0) {
      _timer = Timer(Duration(seconds: clearAfterSeconds), () => _clear(value));
    }
  }

  Future<void> _clear(String expected) async {
    try {
      final current = await Clipboard.getData(Clipboard.kTextPlain);
      if (current?.text == expected) {
        await Clipboard.setData(const ClipboardData(text: ''));
      }
    } catch (_) {
      // Reading may be denied on newer OS versions; clear anyway.
      await Clipboard.setData(const ClipboardData(text: ''));
    }
  }

  /// Clears immediately (e.g. when the vault locks).
  Future<void> flush() async {
    if (_timer?.isActive ?? false) {
      _timer!.cancel();
      await Clipboard.setData(const ClipboardData(text: ''));
    }
  }
}
