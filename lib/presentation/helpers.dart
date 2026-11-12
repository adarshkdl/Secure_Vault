import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/providers.dart';
import '../domain/category.dart';
import '../domain/credential.dart';
import '../domain/field_def.dart';
import '../domain/vault_data.dart';

/// Lets the app suspend auto-lock while it deliberately hands control to the
/// OS (file picker, share sheet, biometric prompt) so those do not lock the
/// vault mid-flow.
class LockGuard {
  int _depth = 0;
  DateTime? _until;
  bool get active =>
      _depth > 0 || (_until != null && DateTime.now().isBefore(_until!));

  /// Manual hold for long-lived system UI such as the camera permission
  /// prompt. Always pair with [release].
  void hold() => _depth++;

  void release() {
    if (_depth > 0) _depth--;
    _until = DateTime.now().add(const Duration(seconds: 2));
  }

  Future<T> run<T>(Future<T> Function() action) async {
    _depth++;
    try {
      return await action();
    } finally {
      _depth--;
      // Grace period: the resume lifecycle event arrives slightly later.
      _until = DateTime.now().add(const Duration(seconds: 2));
    }
  }
}

final lockGuardProvider = Provider((ref) => LockGuard());

void showSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
  bool destructive = false,
}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            minimumSize: const Size(88, 44),
            backgroundColor: destructive
                ? Theme.of(ctx).colorScheme.error
                : null,
            foregroundColor: destructive
                ? Theme.of(ctx).colorScheme.onError
                : null,
          ),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return r ?? false;
}

/// Re-authentication: biometric first when enabled, else master password.
Future<bool> reauthenticate(
  BuildContext context,
  WidgetRef ref, {
  String reason = 'Confirm it is you',
  bool passwordOnly = false,
}) async {
  final vault = ref.read(vaultProvider.notifier);
  final guard = ref.read(lockGuardProvider);
  if (!passwordOnly && ref.read(settingsProvider).biometricEnabled) {
    final ok = await guard.run(vault.verifyBiometric);
    if (ok) return true;
  }
  if (!context.mounted) return false;
  final password = await showDialog<String>(
    context: context,
    builder: (ctx) => _PasswordPrompt(reason: reason),
  );
  if (password == null || password.isEmpty) return false;
  final ok = await vault.verifyMasterPassword(password);
  if (!ok && context.mounted) showSnack(context, 'Incorrect master password');
  return ok;
}

class _PasswordPrompt extends StatefulWidget {
  const _PasswordPrompt({required this.reason});
  final String reason;

  @override
  State<_PasswordPrompt> createState() => _PasswordPromptState();
}

class _PasswordPromptState extends State<_PasswordPrompt> {
  bool _obscure = true;

  // Owned here so it is disposed only after the dialog's closing animation.
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Master password'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.reason),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            autofocus: true,
            obscureText: _obscure,
            enableSuggestions: false,
            autocorrect: false,
            decoration: InputDecoration(
              labelText: 'Master password',
              suffixIcon: IconButton(
                tooltip: _obscure ? 'Show password' : 'Hide password',
                icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
            onSubmitted: (v) => Navigator.pop(context, v),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(88, 44)),
          onPressed: () => Navigator.pop(context, _controller.text),
          child: const Text('Verify'),
        ),
      ],
    );
  }
}

/// Copies exactly one value, honouring the re-auth and clipboard settings.
Future<void> copyValue(
  BuildContext context,
  WidgetRef ref, {
  required String label,
  required String value,
  required bool sensitive,
}) async {
  final settings = ref.read(settingsProvider);
  if (sensitive && settings.requireAuthForSecrets) {
    if (!await reauthenticate(
      context,
      ref,
      reason: 'Authenticate to copy $label',
    )) {
      return;
    }
  }
  await ref
      .read(clipboardProvider)
      .copy(value, clearAfterSeconds: settings.clipboardClearSeconds);
  if (!context.mounted) return;
  final secs = settings.clipboardClearSeconds;
  showSnack(
    context,
    secs > 0
        ? '$label copied. Clipboard clears in ${secs}s. Other apps may read the clipboard until then.'
        : '$label copied. Other apps may be able to read the clipboard.',
  );
}

/// Every field definition for a record: category fields then its own extras.
List<FieldDef> fieldsFor(Category? cat, Credential c) => [
  ...?cat?.fields,
  ...c.extraFields,
];

/// Non-sensitive text shown under the title in lists. Never a secret.
String subtitleFor(Credential c, VaultData data) {
  final cat = data.category(c.categoryId);
  if (cat?.id == 'email') {
    // "Gmail · Office": provider name and mail type, never a secret.
    final parts = [
      c.values['provider'],
      c.values['mail_type'],
    ].whereType<String>().where((s) => s.isNotEmpty);
    if (parts.isNotEmpty) return parts.join(' · ');
  }
  final key = cat?.subtitleKey;
  if (key != null) {
    final def = cat!.fields.where((f) => f.key == key).firstOrNull;
    final v = c.values[key];
    if (def != null && !def.sensitive && v != null && v.isNotEmpty) return v;
  }
  return cat?.name ?? 'Unknown category';
}

String formatDateTime(DateTime d) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
}
