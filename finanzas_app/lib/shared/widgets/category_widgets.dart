import 'package:flutter/material.dart';

import '../../core/theme/category_icons.dart';
import '../../data/models/category.dart';

/// Círculo con el icono y color de la categoría.
class CategoryAvatar extends StatelessWidget {
  const CategoryAvatar({super.key, required this.category, this.size = 44});

  final Category? category;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = category == null ? scheme.outline : Color(category!.color);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color.withAlpha(38), shape: BoxShape.circle),
      child: Icon(
        category == null ? Icons.help_outline : CategoryIcons.of(category!.icon),
        color: color,
        size: size * 0.52,
        semanticLabel: category?.name,
      ),
    );
  }
}

/// Selector visual de categorías (cuadrícula de chips con icono y color).
class CategoryPicker extends StatelessWidget {
  const CategoryPicker({
    super.key,
    required this.categories,
    required this.selectedId,
    required this.onSelected,
    this.onAddCategory,
  });

  final List<Category> categories;
  final String? selectedId;
  final ValueChanged<Category> onSelected;
  final VoidCallback? onAddCategory;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final c in categories)
          Semantics(
            selected: c.id == selectedId,
            button: true,
            child: ChoiceChip(
              key: ValueKey('category_${c.id}'),
              avatar: Icon(CategoryIcons.of(c.icon), size: 20, color: Color(c.color)),
              label: Text(c.name),
              selected: c.id == selectedId,
              showCheckmark: false,
              selectedColor: Color(c.color).withAlpha(56),
              side: BorderSide(color: c.id == selectedId ? Color(c.color) : scheme.outlineVariant),
              materialTapTargetSize: MaterialTapTargetSize.padded,
              onSelected: (_) => onSelected(c),
            ),
          ),
        if (onAddCategory != null)
          ActionChip(
            avatar: const Icon(Icons.add, size: 20),
            label: const Text('Nueva'),
            onPressed: onAddCategory,
          ),
      ],
    );
  }
}
