import 'package:flutter/material.dart';

import '../../core/password_tools.dart';

/// Text field with a show/hide toggle. Autocorrect and suggestions are off so
/// secrets are not sent to keyboard dictionaries.
class SecretTextField extends StatefulWidget {
  const SecretTextField({
    super.key,
    required this.controller,
    required this.label,
    this.validator,
    this.onChanged,
    this.onSubmitted,
    this.autofocus = false,
    this.textInputAction,
    this.extraSuffix,
    this.helperText,
  });

  final TextEditingController controller;
  final String label;
  final String? Function(String?)? validator;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool autofocus;
  final TextInputAction? textInputAction;
  final Widget? extraSuffix;
  final String? helperText;

  @override
  State<SecretTextField> createState() => _SecretTextFieldState();
}

class _SecretTextFieldState extends State<SecretTextField> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: widget.controller,
      obscureText: _obscure,
      autofocus: widget.autofocus,
      enableSuggestions: false,
      autocorrect: false,
      keyboardType: TextInputType.visiblePassword,
      textInputAction: widget.textInputAction,
      validator: widget.validator,
      onChanged: widget.onChanged,
      onFieldSubmitted: widget.onSubmitted,
      decoration: InputDecoration(
        labelText: widget.label,
        helperText: widget.helperText,
        helperMaxLines: 3,
        suffixIcon: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ?widget.extraSuffix,
            IconButton(
              tooltip: _obscure
                  ? 'Show ${widget.label}'
                  : 'Hide ${widget.label}',
              icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
          ],
        ),
      ),
    );
  }
}

class StrengthMeter extends StatelessWidget {
  const StrengthMeter({super.key, required this.password});
  final String password;

  @override
  Widget build(BuildContext context) {
    if (password.isEmpty) return const SizedBox.shrink();
    final s = PasswordTools.strength(password);
    final colors = [
      Colors.red,
      Colors.deepOrange,
      Colors.amber.shade700,
      Colors.lightGreen.shade700,
      Colors.green.shade700,
    ];
    final color = colors[s.index];
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Semantics(
        label: 'Password strength: ${PasswordTools.label(s)}',
        excludeSemantics: true,
        child: Row(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: (s.index + 1) / 5,
                  minHeight: 6,
                  color: color,
                  backgroundColor: color.withValues(alpha: 0.15),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              PasswordTools.label(s),
              style: TextStyle(color: color, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

/// Rules shared by master-password and backup-passphrase creation.
String? validateNewSecret(String? v, {String name = 'password'}) {
  if (v == null || v.length < 10) return 'Use at least 10 characters';
  if (PasswordTools.strength(v).index < Strength.fair.index) {
    return 'That $name is too easy to guess. Add length or variety.';
  }
  return null;
}
