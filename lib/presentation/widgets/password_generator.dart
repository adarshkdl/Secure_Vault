import 'package:flutter/material.dart';

import '../../core/password_tools.dart';
import 'password_widgets.dart';

/// Bottom sheet that returns a generated password, or null if dismissed.
Future<String?> showPasswordGenerator(BuildContext context) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => const _GeneratorSheet(),
  );
}

class _GeneratorSheet extends StatefulWidget {
  const _GeneratorSheet();

  @override
  State<_GeneratorSheet> createState() => _GeneratorSheetState();
}

class _GeneratorSheetState extends State<_GeneratorSheet> {
  double _length = 20;
  bool _lower = true, _upper = true, _digits = true, _symbols = true;
  late String _value;

  @override
  void initState() {
    super.initState();
    _value = _make();
  }

  String _make() => PasswordTools.generate(
    length: _length.round(),
    lower: _lower,
    upper: _upper,
    digits: _digits,
    symbols: _symbols,
  );

  void _regen() => setState(() => _value = _make());

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          16,
          0,
          16,
          16 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Password generator',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Expanded(
                      child: SelectableText(
                        _value,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 18,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Generate another',
                      icon: const Icon(Icons.refresh),
                      onPressed: _regen,
                    ),
                  ],
                ),
              ),
            ),
            StrengthMeter(password: _value),
            const SizedBox(height: 8),
            Text('Length: ${_length.round()}'),
            Slider(
              value: _length,
              min: 8,
              max: 64,
              divisions: 56,
              label: _length.round().toString(),
              onChanged: (v) {
                _length = v;
                _regen();
              },
            ),
            Wrap(
              spacing: 8,
              children: [
                FilterChip(
                  label: const Text('a-z'),
                  selected: _lower,
                  onSelected: (v) {
                    _lower = v;
                    _regen();
                  },
                ),
                FilterChip(
                  label: const Text('A-Z'),
                  selected: _upper,
                  onSelected: (v) {
                    _upper = v;
                    _regen();
                  },
                ),
                FilterChip(
                  label: const Text('0-9'),
                  selected: _digits,
                  onSelected: (v) {
                    _digits = v;
                    _regen();
                  },
                ),
                FilterChip(
                  label: const Text('Symbols'),
                  selected: _symbols,
                  onSelected: (v) {
                    _symbols = v;
                    _regen();
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => Navigator.pop(context, _value),
              child: const Text('Use this password'),
            ),
          ],
        ),
      ),
    );
  }
}
