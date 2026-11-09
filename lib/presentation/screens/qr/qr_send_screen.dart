import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/crypto/qr_transfer.dart';
import '../../../core/qr_payload.dart';
import 'qr_widgets.dart';

/// Sender side: scan the receiver's offer, then show the encrypted response QR
/// and the confirmation code. The payload is only held in memory.
class QrSendScreen extends ConsumerStatefulWidget {
  const QrSendScreen({super.key, required this.record});
  final QrRecord record;

  @override
  ConsumerState<QrSendScreen> createState() => _QrSendScreenState();
}

class _QrSendScreenState extends ConsumerState<QrSendScreen>
    with CountdownState {
  QrResponse? _response;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    stopCountdown();
    super.dispose();
  }

  Future<void> _onOffer(String code) async {
    setState(() => _busy = true);
    try {
      final r = await QrTransfer.respond(
        offer: code,
        payload: widget.record.encode(),
      );
      if (!mounted) return;
      startCountdown(r.expiresAt, onExpire: () => setState(() {}));
      setState(() {
        _response = r;
        _busy = false;
      });
    } on QrTransferException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = _response;
    return Scaffold(
      appBar: AppBar(title: const Text('Send by QR')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (r == null) ...[
              const Text(
                'On the other device open Settings > Receive by QR, then scan the code it shows.',
              ),
              const SizedBox(height: 12),
              if (_error != null) ...[
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () => setState(() => _error = null),
                  child: const Text('Scan again'),
                ),
              ] else if (_busy)
                const Center(child: CircularProgressIndicator())
              else
                QrScanView(onCode: _onOffer),
            ] else if (expired) ...[
              const Icon(Icons.timer_off_outlined, size: 48),
              const SizedBox(height: 12),
              const Text(
                'This transfer code expired and is no longer shown. Start again to send.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
            ] else ...[
              Text(
                'Let the other device scan this code. It expires in $remainingText.',
              ),
              const SizedBox(height: 12),
              QrTile(data: r.message),
              const SizedBox(height: 16),
              const Text(
                'Confirmation code - it must match the code on the other device before they save:',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              ConfirmationCode(r.confirmationCode),
              const SizedBox(height: 16),
              Text(
                'Only the device that created the receive code can decrypt this. It works once. If the codes differ, do not continue.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Done'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
