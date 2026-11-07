import '../models/enums.dart';

class DefaultCategory {
  const DefaultCategory(this.name, this.type, this.color, this.icon);

  final String name;
  final TxType type;
  final int color;
  final String icon;
}

/// Categorías predeterminadas (las mismas que crea Supabase en
/// `seed_default_categories`).
abstract final class DefaultCategories {
  static const List<DefaultCategory> all = [
    DefaultCategory('Salario', TxType.income, 0xFF2E7D32, 'salary'),
    DefaultCategory('Ventas', TxType.income, 0xFF00897B, 'sales'),
    DefaultCategory('Inversiones', TxType.income, 0xFF1565C0, 'investments'),
    DefaultCategory('Bonificaciones', TxType.income, 0xFF6A1B9A, 'bonus'),
    DefaultCategory('Otros', TxType.income, 0xFF546E7A, 'other_income'),
    DefaultCategory('Alimentación', TxType.expense, 0xFFEF6C00, 'food'),
    DefaultCategory('Vivienda', TxType.expense, 0xFF5D4037, 'home'),
    DefaultCategory('Transporte', TxType.expense, 0xFF0277BD, 'transport'),
    DefaultCategory('Salud', TxType.expense, 0xFFC62828, 'health'),
    DefaultCategory('Educación', TxType.expense, 0xFF283593, 'education'),
    DefaultCategory('Entretenimiento', TxType.expense, 0xFFAD1457, 'entertainment'),
    DefaultCategory('Servicios', TxType.expense, 0xFF00838F, 'services'),
    DefaultCategory('Deudas', TxType.expense, 0xFF4E342E, 'debts'),
    DefaultCategory('Otros', TxType.expense, 0xFF616161, 'other_expense'),
  ];
}
