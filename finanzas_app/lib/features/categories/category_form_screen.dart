import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors/app_exception.dart';
import '../../core/theme/category_icons.dart';
import '../../core/utils/validators.dart';
import '../../data/models/category.dart';
import '../../data/models/enums.dart';
import '../../providers.dart';
import '../../shared/widgets/category_widgets.dart';
import '../../shared/widgets/feedback.dart';
import '../../shared/widgets/state_views.dart';

/// Crear o editar una categoría (nombre, tipo, color e icono).
class CategoryFormScreen extends ConsumerStatefulWidget {
  const CategoryFormScreen({super.key, this.categoryId, this.initialType = TxType.expense});

  final String? categoryId;
  final TxType initialType;

  @override
  ConsumerState<CategoryFormScreen> createState() => _CategoryFormScreenState();
}

class _CategoryFormScreenState extends ConsumerState<CategoryFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  late TxType _type = widget.initialType;
  int _color = CategoryIcons.palette.first;
  String _icon = 'other';
  Category? _original;
  bool _loading = false;
  bool _saving = false;
  Object? _error;

  bool get _isEditing => widget.categoryId != null;

  @override
  void initState() {
    super.initState();
    if (_isEditing) _load();
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final c = await ref.read(categoryRepositoryProvider).getById(widget.categoryId!);
      if (c == null || c.deletedAt != null) throw const AppException('La categoría no existe.');
      _original = c;
      _name.text = c.name;
      _type = c.type;
      _color = c.color;
      _icon = c.icon;
    } catch (e) {
      _error = e;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final user = ref.read(currentUserProvider);
    if (user == null) return;
    setState(() => _saving = true);
    final repo = ref.read(categoryRepositoryProvider);
    try {
      final Category saved;
      if (_original != null) {
        saved = await repo.update(_original!.copyWith(name: _name.text, color: _color, icon: _icon));
      } else {
        saved = await repo.create(userId: user.id, name: _name.text, type: _type, color: _color, icon: _icon);
      }
      if (!mounted) return;
      showInfoSnack(context, _isEditing ? 'Categoría actualizada' : 'Categoría creada');
      context.pop(saved);
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = _isEditing ? 'Editar categoría' : 'Nueva categoría';
    if (_loading) return Scaffold(appBar: AppBar(title: Text(title)), body: const LoadingView());
    if (_error != null) return Scaffold(appBar: AppBar(title: Text(title)), body: ErrorView(error: _error!));

    final scheme = Theme.of(context).colorScheme;
    final preview = Category(
      id: 'preview',
      userId: '',
      name: _name.text.isEmpty ? 'Vista previa' : _name.text,
      type: _type,
      color: _color,
      icon: _icon,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(padding: const EdgeInsets.all(16), children: [
            Center(
              child: Column(children: [
                CategoryAvatar(category: preview, size: 72),
                const SizedBox(height: 8),
                Text(preview.name, style: Theme.of(context).textTheme.titleMedium),
              ]),
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: _name,
              maxLength: 40,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Nombre', prefixIcon: Icon(Icons.label_outline)),
              validator: Validators.categoryName,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            Text('Tipo', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            SegmentedButton<TxType>(
              segments: const [
                ButtonSegment(value: TxType.expense, label: Text('Egreso')),
                ButtonSegment(value: TxType.income, label: Text('Ingreso')),
              ],
              selected: {_type},
              onSelectionChanged: _isEditing ? null : (s) => setState(() => _type = s.first),
            ),
            if (_isEditing)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('El tipo no se puede cambiar después de crearla.',
                    style: Theme.of(context).textTheme.bodySmall),
              ),
            const SizedBox(height: 20),
            Text('Color', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(spacing: 10, runSpacing: 10, children: [
              for (final c in CategoryIcons.palette)
                Semantics(
                  label: 'Color',
                  selected: c == _color,
                  button: true,
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () => setState(() => _color = c),
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: Color(c),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: c == _color ? scheme.onSurface : Colors.transparent,
                          width: 3,
                        ),
                      ),
                      child: c == _color ? const Icon(Icons.check, color: Colors.white) : null,
                    ),
                  ),
                ),
            ]),
            const SizedBox(height: 20),
            Text('Icono', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final entry in CategoryIcons.all.entries)
                InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => setState(() => _icon = entry.key),
                  child: Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: entry.key == _icon ? Color(_color).withAlpha(50) : scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: entry.key == _icon ? Color(_color) : Colors.transparent,
                        width: 2,
                      ),
                    ),
                    child: Icon(entry.value, color: entry.key == _icon ? Color(_color) : scheme.onSurfaceVariant),
                  ),
                ),
            ]),
            const SizedBox(height: 28),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: const Icon(Icons.check),
              label: Text(_isEditing ? 'Guardar cambios' : 'Crear categoría'),
            ),
          ]),
        ),
      ),
    );
  }
}
