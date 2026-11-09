import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers.dart';
import '../../domain/category.dart';
import '../../domain/field_def.dart';
import '../helpers.dart';
import '../theme.dart';

class CategoryEditorScreen extends ConsumerStatefulWidget {
  const CategoryEditorScreen({super.key, this.existing});
  final Category? existing;

  @override
  ConsumerState<CategoryEditorScreen> createState() => _CategoryEditorState();
}

class _CategoryEditorState extends ConsumerState<CategoryEditorScreen> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name;
  late String _icon;
  late String _color;
  late List<FieldDef> _fields;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    _icon = e?.iconKey ?? 'folder';
    _color = e?.colorKey ?? 'blue';
    _fields = [...?e?.fields];
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _editField([int? index]) async {
    final existing = index == null ? null : _fields[index];
    final label = TextEditingController(text: existing?.label ?? '');
    var type = existing?.type ?? FieldType.text;
    var sensitive = existing?.sensitive ?? false;
    var required = existing?.required ?? false;
    final result = await showDialog<FieldDef>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Text(existing == null ? 'Add field' : 'Edit field'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: label,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Field name'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<FieldType>(
                  initialValue: type.userSelectable ? type : FieldType.text,
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
                  title: const Text('Sensitive (masked, never previewed)'),
                  value: sensitive || type == FieldType.password,
                  onChanged: type == FieldType.password
                      ? null
                      : (v) => setS(() => sensitive = v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Required'),
                  value: required,
                  onChanged: (v) => setS(() => required = v),
                ),
              ],
            ),
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
                    key: existing?.key ?? 'f_${newId()}',
                    label: label.text.trim(),
                    type: type,
                    sensitive: sensitive || type == FieldType.password,
                    required: required,
                  ),
                );
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    label.dispose();
    if (result == null) return;
    setState(() {
      if (index == null) {
        _fields.add(result);
      } else {
        _fields[index] = result;
      }
    });
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final e = widget.existing;
    // First non-sensitive text-like field becomes the list subtitle.
    final sub = _fields
        .where(
          (f) =>
              !f.sensitive &&
              f.type != FieldType.longText &&
              f.type != FieldType.boolean,
        )
        .firstOrNull
        ?.key;
    final cat = Category(
      id: e?.id ?? 'c_${newId()}',
      name: _name.text.trim(),
      iconKey: _icon,
      colorKey: _color,
      fields: _fields,
      sortOrder: e?.sortOrder ?? 100,
      subtitleKey: sub,
    );
    await ref.read(vaultProvider.notifier).saveCategory(cat);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existing == null ? 'New category' : 'Edit category'),
        actions: [TextButton(onPressed: _save, child: const Text('Save'))],
      ),
      body: SafeArea(
        child: Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Category name *'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Name is required' : null,
              ),
              const SizedBox(height: 20),
              Text('Icon', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final e in categoryIcons.entries)
                    ChoiceChip(
                      label: Icon(e.value, size: 22),
                      tooltip: e.key,
                      selected: _icon == e.key,
                      onSelected: (_) => setState(() => _icon = e.key),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              Text('Color', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  for (final e in categoryColors.entries)
                    Semantics(
                      label: e.key,
                      selected: _color == e.key,
                      button: true,
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () => setState(() => _color = e.key),
                        child: CircleAvatar(
                          radius: 20,
                          backgroundColor: e.value,
                          child: _color == e.key
                              ? const Icon(Icons.check, color: Colors.white)
                              : null,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Fields',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => _editField(),
                    icon: const Icon(Icons.add),
                    label: const Text('Add field'),
                  ),
                ],
              ),
              if (_fields.isEmpty)
                const Text(
                  'No fields yet. Every record still has a title, notes and tags.',
                ),
              for (var i = 0; i < _fields.length; i++)
                Card(
                  child: ListTile(
                    leading: Icon(
                      _fields[i].sensitive
                          ? Icons.lock_outline
                          : Icons.short_text,
                    ),
                    title: Text(
                      _fields[i].label + (_fields[i].required ? ' *' : ''),
                    ),
                    subtitle: Text(
                      _fields[i].type.label +
                          (_fields[i].sensitive ? '  -  sensitive' : ''),
                    ),
                    onTap: () => _editField(i),
                    trailing: IconButton(
                      tooltip: 'Remove ${_fields[i].label}',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () async {
                        final ok = await confirmDialog(
                          context,
                          title: 'Remove field?',
                          message:
                              'Existing records keep any saved value but it will no longer be shown.',
                          confirmLabel: 'Remove',
                          destructive: true,
                        );
                        if (ok) setState(() => _fields.removeAt(i));
                      },
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
