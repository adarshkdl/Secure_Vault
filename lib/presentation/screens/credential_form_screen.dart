import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers.dart';
import '../../core/validators.dart';
import '../../domain/category.dart';
import '../../domain/credential.dart';
import '../../domain/field_def.dart';
import '../helpers.dart';
import '../theme.dart';
import '../widgets/password_generator.dart';
import '../widgets/password_widgets.dart';
import '../widgets/provider_icon.dart';
import '../../domain/builtin_categories.dart' show emailProviderNames;

/// Bottom sheet: choose a category, then open the add form.
Future<void> pickCategoryAndAdd(BuildContext context, WidgetRef ref) async {
  final data = ref.read(vaultProvider).data;
  if (data == null) return;
  final id = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              'Choose a category',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
          ),
          for (final c in data.allCategories)
            ListTile(
              leading: Icon(iconFor(c.iconKey), color: colorFor(c.colorKey)),
              title: Text(c.name),
              onTap: () => Navigator.pop(ctx, c.id),
            ),
        ],
      ),
    ),
  );
  if (id == null || !context.mounted) return;
  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => CredentialFormScreen(categoryId: id),
    ),
  );
}

class CredentialFormScreen extends ConsumerStatefulWidget {
  const CredentialFormScreen({
    super.key,
    required this.categoryId,
    this.existing,
  });
  final String categoryId;
  final Credential? existing;

  @override
  ConsumerState<CredentialFormScreen> createState() =>
      _CredentialFormScreenState();
}

class _CredentialFormScreenState extends ConsumerState<CredentialFormScreen> {
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _notes = TextEditingController();
  final _tags = TextEditingController();
  final _ctrls = <String, TextEditingController>{};
  final _bools = <String, bool>{};
  final _phoneCtrls = <String, List<TextEditingController>>{};
  late List<FieldDef> _extras;
  bool _dirty = false;
  bool _saving = false;

  Category get _cat =>
      ref.read(vaultProvider).data!.category(widget.categoryId)!;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _extras = [...?e?.extraFields];
    if (e != null) {
      _title.text = e.title;
      _notes.text = e.notes;
      _tags.text = e.tags.join(', ');
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Controllers need the category, available after first frame.
    });
  }

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    _tags.dispose();
    for (final c in _ctrls.values) {
      c.dispose();
    }
    for (final l in _phoneCtrls.values) {
      for (final c in l) {
        c.dispose();
      }
    }
    super.dispose();
  }

  TextEditingController _ctrl(FieldDef f) => _ctrls.putIfAbsent(
    f.key,
    () => TextEditingController(
      text:
          widget.existing?.values[f.key] ??
          (widget.existing == null ? f.initial : null) ??
          '',
    ),
  );

  /// One controller per phone number; always at least one (empty) box.
  List<TextEditingController> _phones(FieldDef f) =>
      _phoneCtrls.putIfAbsent(f.key, () {
        final saved = (widget.existing?.values[f.key] ?? '')
            .split('\n')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty);
        final l = [for (final s in saved) TextEditingController(text: s)];
        return l.isEmpty ? [TextEditingController()] : l;
      });

  String _phoneValue(FieldDef f) =>
      _phones(f)
          .map((c) => c.text.trim())
          .where((s) => s.isNotEmpty)
          .join('\n');

  bool _bool(FieldDef f) =>
      _bools.putIfAbsent(f.key, () => widget.existing?.values[f.key] == 'true');

  void _touch() {
    if (!_dirty) setState(() => _dirty = true);
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) {
      showSnack(context, 'Please fix the highlighted fields.');
      return;
    }
    final cat = _cat;
    final defs = [...cat.fields, ..._extras];
    final now = DateTime.now();
    final old = widget.existing;

    // Start from existing values so fields not shown in this form survive.
    final values = <String, String>{...?old?.values};
    for (final f in defs) {
      final String v = switch (f.type) {
        FieldType.boolean => _bool(f) ? 'true' : '',
        FieldType.phoneList => _phoneValue(f),
        _ => _ctrl(f).text.trim(),
      };
      if (v.isEmpty) {
        values.remove(f.key);
      } else {
        values[f.key] = v;
      }
    }
    // Drop values of removed custom fields.
    final liveKeys = defs.map((f) => f.key).toSet();
    for (final f in old?.extraFields ?? const <FieldDef>[]) {
      if (!liveKeys.contains(f.key)) values.remove(f.key);
    }

    final cred = Credential(
      id: old?.id ?? newId(),
      categoryId: cat.id,
      title: cat.autoTitleKey != null
          ? (values[cat.autoTitleKey] ?? '')
          : _title.text.trim(),
      values: values,
      extraFields: _extras,
      notes: _notes.text.trim(),
      tags: _tags.text
          .split(',')
          .map((t) => t.trim())
          .where((t) => t.isNotEmpty)
          .toList(),
      isFavorite: old?.isFavorite ?? false,
      createdAt: old?.createdAt ?? now,
      updatedAt: now,
      lastAccessedAt: old?.lastAccessedAt,
    );

    final data = ref.read(vaultProvider).data!;
    final dup = findDuplicate(data, cred);
    if (dup != null) {
      final go = await confirmDialog(
        context,
        title: 'Possible duplicate',
        message:
            'A similar record already exists: "${dup.title}". Save this one anyway?',
        confirmLabel: 'Save anyway',
      );
      if (!go) return;
    }

    setState(() => _saving = true);
    await ref.read(vaultProvider.notifier).saveCredential(cred);
    if (!mounted) return;
    _dirty = false;
    Navigator.of(context).pop();
  }

  Future<void> _addCustomField() async {
    final label = TextEditingController();
    var type = FieldType.text;
    var sensitive = false;
    final result = await showDialog<FieldDef>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('Add custom field'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: label,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Field name'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<FieldType>(
                initialValue: type,
                decoration: const InputDecoration(labelText: 'Type'),
                items: [
                  for (final t in FieldType.values.where(
                    (t) => t.userSelectable,
                  ))
                    DropdownMenuItem(value: t, child: Text(t.label)),
                ],
                onChanged: (v) => setS(() {
                  type = v ?? FieldType.text;
                  if (type == FieldType.password) sensitive = true;
                }),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Sensitive (masked)'),
                value: sensitive || type == FieldType.password,
                onChanged: type == FieldType.password
                    ? null
                    : (v) => setS(() => sensitive = v),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(88, 44)),
              onPressed: () {
                if (label.text.trim().isEmpty) return;
                Navigator.pop(
                  ctx,
                  FieldDef(
                    key: 'x_${newId()}',
                    label: label.text.trim(),
                    type: type,
                    sensitive: sensitive || type == FieldType.password,
                  ),
                );
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
    label.dispose();
    if (result != null) {
      setState(() {
        _extras = [..._extras, result];
        _dirty = true;
      });
    }
  }

  Widget _fieldWidget(FieldDef f, {VoidCallback? onRemove}) {
    final remove = onRemove == null
        ? null
        : IconButton(
            tooltip: 'Remove ${f.label}',
            icon: const Icon(Icons.remove_circle_outline),
            onPressed: onRemove,
          );
    final Widget w;
    switch (f.type) {
      case FieldType.boolean:
        w = SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(f.label),
          value: _bool(f),
          onChanged: (v) => setState(() {
            _bools[f.key] = v;
            _dirty = true;
          }),
        );
      case FieldType.phoneList:
        final list = _phones(f);
        w = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(f.label, style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            for (var i = 0; i < list.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: list[i],
                        keyboardType: TextInputType.phone,
                        decoration: InputDecoration(
                          labelText: 'Mobile number ${i + 1}',
                        ),
                        validator: (v) => Validators.validate(
                          f.copyWith(type: FieldType.phone, required: false),
                          v,
                        ),
                      ),
                    ),
                    if (list.length > 1)
                      IconButton(
                        tooltip: 'Remove number ${i + 1}',
                        icon: const Icon(Icons.remove_circle_outline),
                        onPressed: () => setState(() {
                          list.removeAt(i).dispose();
                          _dirty = true;
                        }),
                      ),
                  ],
                ),
              ),
            TextButton.icon(
              onPressed: () => setState(() {
                list.add(TextEditingController());
                _dirty = true;
              }),
              icon: const Icon(Icons.add),
              label: const Text('Add another number'),
            ),
          ],
        );
      case FieldType.choice:
        final c = _ctrl(f);
        final withIcons = identical(f.options, emailProviderNames);
        w = DropdownButtonFormField<String>(
          isExpanded: true,
          initialValue: f.options.contains(c.text) ? c.text : null,
          decoration: InputDecoration(
            labelText: f.required ? '${f.label} *' : f.label,
          ),
          items: [
            for (final o in f.options)
              DropdownMenuItem(
                value: o,
                child: withIcons
                    ? Row(
                        children: [
                          ProviderIcon(o, size: 28),
                          const SizedBox(width: 12),
                          Flexible(
                            child: Text(o, overflow: TextOverflow.ellipsis),
                          ),
                        ],
                      )
                    : Text(o),
              ),
          ],
          validator: (v) => Validators.validate(f, v ?? ''),
          onChanged: (v) {
            c.text = v ?? '';
            _touch();
          },
        );
      case FieldType.date:
        final c = _ctrl(f);
        w = TextFormField(
          controller: c,
          readOnly: true,
          decoration: InputDecoration(
            labelText: f.label,
            suffixIcon: const Icon(Icons.calendar_today_outlined),
          ),
          validator: (v) => Validators.validate(f, v),
          onTap: () async {
            final now = DateTime.now();
            final picked = await showDatePicker(
              context: context,
              initialDate: DateTime.tryParse(c.text) ?? now,
              firstDate: DateTime(1990),
              lastDate: DateTime(2100),
            );
            if (picked != null) {
              c.text = picked.toIso8601String().substring(0, 10);
              _touch();
            }
          },
        );
      default:
        final c = _ctrl(f);
        if (f.sensitive && f.type != FieldType.longText) {
          w = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SecretTextField(
                controller: c,
                label: f.label,
                helperText: f.hint,
                validator: (v) => Validators.validate(f, v),
                onChanged: (_) {
                  _touch();
                  setState(() {});
                },
                extraSuffix: f.type == FieldType.password
                    ? IconButton(
                        tooltip: 'Generate password',
                        icon: const Icon(Icons.auto_fix_high),
                        onPressed: () async {
                          final p = await showPasswordGenerator(context);
                          if (p != null) {
                            c.text = p;
                            _touch();
                            setState(() {});
                          }
                        },
                      )
                    : null,
              ),
              if (f.type == FieldType.password) StrengthMeter(password: c.text),
            ],
          );
        } else {
          w = TextFormField(
            controller: c,
            decoration: InputDecoration(
              labelText: f.label,
              helperText: f.hint,
              helperMaxLines: 3,
              suffixIcon: f.sensitive ? const Icon(Icons.lock_outline) : null,
            ),
            keyboardType: switch (f.type) {
              FieldType.email => TextInputType.emailAddress,
              FieldType.url => TextInputType.url,
              FieldType.phone => TextInputType.phone,
              FieldType.number || FieldType.port => TextInputType.number,
              FieldType.longText => TextInputType.multiline,
              _ => TextInputType.text,
            },
            inputFormatters: f.type == FieldType.port
                ? [FilteringTextInputFormatter.digitsOnly]
                : null,
            minLines: f.type == FieldType.longText ? 3 : 1,
            maxLines: f.type == FieldType.longText ? 8 : 1,
            autocorrect:
                f.type == FieldType.text || f.type == FieldType.longText,
            enableSuggestions: !f.sensitive,
            validator: (v) => Validators.validate(f, v),
          );
        }
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: remove == null
          ? w
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: w),
                remove,
              ],
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cat = _cat;
    final basic = cat.fields.where((f) => !f.advanced);
    final advanced = cat.fields.where((f) => f.advanced).toList();
    final editing = widget.existing != null;

    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final discard = await confirmDialog(
          context,
          title: 'Discard changes?',
          message: 'You have unsaved changes.',
          confirmLabel: 'Discard',
          destructive: true,
        );
        if (discard && context.mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(editing ? 'Edit ${cat.name}' : 'New ${cat.name}'),
          actions: [
            TextButton(
              onPressed: _saving ? null : _save,
              child: const Text('Save'),
            ),
          ],
        ),
        body: SafeArea(
          child: Form(
            key: _form,
            onChanged: _touch,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (cat.autoTitleKey == null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: TextFormField(
                      controller: _title,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(labelText: 'Title *'),
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? 'Title is required'
                          : null,
                    ),
                  ),
                for (final f in basic) _fieldWidget(f),
                if (advanced.isNotEmpty)
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: const Text('Advanced'),
                    initiallyExpanded: advanced.any(
                      (f) => (widget.existing?.values[f.key] ?? '').isNotEmpty,
                    ),
                    children: [
                      const SizedBox(height: 8),
                      for (final f in advanced) _fieldWidget(f),
                    ],
                  ),
                if (_extras.isNotEmpty) ...[
                  Text(
                    'Custom fields',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  for (final f in _extras)
                    _fieldWidget(
                      f,
                      onRemove: () => setState(() {
                        _extras = _extras.where((x) => x.key != f.key).toList();
                        _dirty = true;
                      }),
                    ),
                ],
                if (cat.allowCustomFields)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: _addCustomField,
                      icon: const Icon(Icons.add),
                      label: const Text('Add custom field'),
                    ),
                  ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _notes,
                  minLines: 3,
                  maxLines: 8,
                  decoration: const InputDecoration(
                    labelText: 'Notes',
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _tags,
                  decoration: const InputDecoration(
                    labelText: 'Tags',
                    helperText: 'Separate with commas',
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  child: const Text('Save'),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  child: const Text('Cancel'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
