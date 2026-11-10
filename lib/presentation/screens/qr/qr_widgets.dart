import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../helpers.dart';

/// Camera view that reports the first QR value it sees. Holds the auto-lock
/// guard while mounted so the camera permission prompt does not lock the vault.
class QrScanView extends ConsumerStatefulWidget {
  const QrScanView({super.key, required this.onCode});
  final void Function(String code) onCode;

  @override
  ConsumerState<QrScanView> createState() => _QrScanViewState();
}

class _QrScanViewState extends ConsumerState<QrScanView> {
  final _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  late final LockGuard _guard;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _guard = ref.read(lockGuardProvider)..hold();
  }

  @override
  void dispose() {
    _guard.release();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: AspectRatio(
        aspectRatio: 1,
        child: MobileScanner(
          controller: _controller,
          onDetect: (capture) {
            if (_done) return;
            final v = capture.barcodes
                .map((b) => b.rawValue)
                .whereType<String>()
                .firstOrNull;
            if (v == null) return;
            _done = true;
            widget.onCode(v);
          },
          errorBuilder: (context, error) => Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                error.errorCode == MobileScannerErrorCode.permissionDenied
                    ? 'Camera permission is needed to scan. Enable it in system settings.'
                    : 'The camera could not be started.',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A QR code on a white tile (needed for reliable scanning in dark theme).
class QrTile extends StatelessWidget {
  const QrTile({super.key, required this.data});
  final String data;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        color: Colors.white,
        padding: const EdgeInsets.all(8),
        child: QrImageView(
          data: data,
          size: 300,
          errorCorrectionLevel: QrErrorCorrectLevel.L,
          backgroundColor: Colors.white,
          semanticsLabel: 'Encrypted transfer QR code',
        ),
      ),
    );
  }
}

/// Ticks once a second and exposes the time remaining until [expiresAt].
mixin CountdownState<T extends StatefulWidget> on State<T> {
  Timer? _timer;
  DateTime? _expiresAt;

  Duration get remaining {
    final e = _expiresAt;
    if (e == null) return Duration.zero;
    final d = e.difference(DateTime.now());
    return d.isNegative ? Duration.zero : d;
  }

  bool get expired => _expiresAt != null && remaining == Duration.zero;

  void startCountdown(DateTime expiresAt, {VoidCallback? onExpire}) {
    _timer?.cancel();
    _expiresAt = expiresAt;
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() {});
      if (expired) {
        t.cancel();
        onExpire?.call();
      }
    });
  }

  String get remainingText {
    final r = remaining;
    return '${r.inMinutes}:${(r.inSeconds % 60).toString().padLeft(2, '0')}';
  }

  void stopCountdown() => _timer?.cancel();
}

/// Large, spaced confirmation code both devices must show identically.
class ConfirmationCode extends StatelessWidget {
  const ConfirmationCode(this.code, {super.key});
  final String code;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Confirmation code ${code.split('').join(' ')}',
      child: ExcludeSemantics(
        child: Text(
          '${code.substring(0, 3)} ${code.substring(3)}',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.displaySmall
              ?.copyWith(fontFamily: 'monospace', letterSpacing: 4),
        ),
      ),
    );
  }
}
