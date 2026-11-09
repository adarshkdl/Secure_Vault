import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../application/providers.dart';
import '../../../core/crypto/qr_transfer.dart';
import '../../../core/qr_payload.dart';
import '../../../domain/credential.dart';
import '../../../domain/field_def.dart';
import '../../helpers.dart';
import 'qr_widgets.dart';

enum _Phase { offering, scanning, review, failed }

/// Receiver side: show a short-lived offer QR, scan the sender's encrypted
/// response, show the content and confirmation code, and save only after the
/// user explicitly confirms.
class QrReceiveScreen extends ConsumerStatefulWidget {
  const QrReceiveScreen({super.key});

  @override
  ConsumerState<QrReceiveScreen> createState() => _QrReceiveScreenState();
}

class _QrReceiveScreenState extends ConsumerState<QrReceiveScreen>
    with CountdownState {
  QrReceiveSession? _session;
  String? _offer;
  _Phase _phase = _Phase.offering;
  String? _error;
  QrRecord? _record;
  String? _code;
  final _revealed = <int>{};

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _session?.cancel();
    stopCountdown();
    super.dispose();
  }

  Future<void> _start() async {
    _session?.cancel();
    final s = await QrReceiveSession.start();
    final offer = await s.offer();
    if (!mounted) return;
    startCountdown(s.expiresAt, onExpire: () => setState(() {}));
    setState(() {
      _session = s;
      _offer = offer;
      _phase = _Phase.offering;
      _error = null;
      _record = null;
      _revealed.clear();
    });
  }

  Future<void> _onResponse(String code) async {
    final s = _session!;
    try {
      final got = await s.accept(code);
      final rec = QrRecord.decode(got.payload);
      if (!mounted) return;
      stopCountdown();
      setState(() {
        _record = rec;
        _code = got.confirmationCode;
        _phase = _Phase.review;
      });
    } on QrTransferException catch (e) {
      _fail(e.message);
    } on FormatException {
      _fail('The received content was not in a supported format.');
    }
  }

  void _fail(String msg) {
    if (!mounted) return;
    setState(() {
      _error = msg;
      _phase = _Phase.failed;
    });
  }

  Future<void> _save() async {
    final rec = _record!;
    // 'account' is a built-in category, so it always exists.
    const catId = 'account';
    final now = DateTime.now();
    final extras = <FieldDef>[];
    final values = <String, String>{};
    for (var i = 0; i < rec.fields.length; i++) {
      final f = rec.fields[i];
      final key = 'qr_$i';
      extras.add(
        FieldDef(
          key: key,
          label: f.label,
          type: f.sensitive ? FieldType.password : FieldType.text,
          sensitive: f.sensitive,
        ),
      );
      values[key] = f.value;
    }
    await ref
        .read(vaultProvider.notifier)
        .saveCredential(
          Credential(
            id: newId(),
            categoryId: catId,
            title: rec.title,
            values: values,
            extraFields: extras,
            notes: rec.notes,
            tags: const ['received'],
            createdAt: now,
            updatedAt: now,
          ),
        );
    if (!mounted) return;
    showSnack(context, 'Saved to your vault');
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final error = Theme.of(context).colorScheme.error;
    final children = <Widget>[];
    switch (_phase) {
      case _Phase.offering:
        if (_offer == null) {
          children.add(const Center(child: CircularProgressIndicator()));
        } else if (expired) {
          children
            ..add(const Text('This receive code expired.'))
            ..add(const SizedBox(height: 12))
            ..add(
              FilledButton(
                onPressed: _start,
                child: const Text('Create a new code'),
              ),
            );
        } else {
          children
            ..add(
              Text(
                'Ask the sender to choose Share > Send by QR and scan this code. It expires in $remainingText and works once.',
              ),
            )
            ..add(const SizedBox(height: 12))
            ..add(QrTile(data: _offer!))
            ..add(const SizedBox(height: 16))
            ..add(
              FilledButton.icon(
                onPressed: () => setState(() => _phase = _Phase.scanning),
                icon: const Icon(Icons.qr_code_scanner),
                label: const Text("Scan the sender's code"),
              ),
            );
        }
      case _Phase.scanning:
        children
          ..add(
            Text(
              expired
                  ? 'This receive code expired.'
                  : 'Point the camera at the code on the sender\'s screen. ($remainingText left)',
            ),
          )
          ..add(const SizedBox(height: 12))
          ..add(
            expired
                ? FilledButton(
                    onPressed: _start,
                    child: const Text('Create a new code'),
                  )
                : QrScanView(onCode: _onResponse),
          );
      case _Phase.failed:
        children
          ..add(
            Text(_error ?? 'Transfer failed.', style: TextStyle(color: error)),
          )
          ..add(const SizedBox(height: 12))
          ..add(
            FilledButton(onPressed: _start, child: const Text('Start again')),
          );
      case _Phase.review:
        final rec = _record!;
        children
          ..add(
            const Text(
              'Check that this code matches the sender\'s screen. If it does not, discard - the code may have been swapped.',
            ),
          )
          ..add(const SizedBox(height: 8))
          ..add(ConfirmationCode(_code!))
          ..add(const SizedBox(height: 16))
          ..add(Text(rec.title, style: Theme.of(context).textTheme.titleLarge))
          ..addAll([
            for (var i = 0; i < rec.fields.length; i++)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(rec.fields[i].label),
                subtitle: Text(
                  rec.fields[i].sensitive && !_revealed.contains(i)
                      ? '••••••••'
                      : rec.fields[i].value,
                ),
                trailing: rec.fields[i].sensitive
                    ? IconButton(
                        tooltip: _revealed.contains(i) ? 'Hide' : 'Reveal',
                        icon: Icon(
                          _revealed.contains(i)
                              ? Icons.visibility_off
                              : Icons.visibility,
                        ),
                        onPressed: () => setState(
                          () => _revealed.contains(i)
                              ? _revealed.remove(i)
                              : _revealed.add(i),
                        ),
                      )
                    : null,
              ),
          ])
          ..add(const SizedBox(height: 16))
          ..add(
            FilledButton(
              onPressed: _save,
              child: const Text('Codes match - save to vault'),
            ),
          )
          ..add(const SizedBox(height: 8))
          ..add(
            OutlinedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Discard'),
            ),
          );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Receive by QR')),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.all(16), children: children),
      ),
    );
  }
}
