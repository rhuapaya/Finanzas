import 'package:flutter/material.dart';

/// Iconos disponibles para categorías (clave persistida → icono).
abstract final class CategoryIcons {
  static const Map<String, IconData> all = {
    'salary': Icons.payments,
    'sales': Icons.storefront,
    'investments': Icons.trending_up,
    'bonus': Icons.card_giftcard,
    'other_income': Icons.attach_money,
    'food': Icons.restaurant,
    'home': Icons.home,
    'transport': Icons.directions_bus,
    'health': Icons.local_hospital,
    'education': Icons.school,
    'entertainment': Icons.movie,
    'services': Icons.lightbulb,
    'debts': Icons.credit_card,
    'other_expense': Icons.more_horiz,
    'shopping': Icons.shopping_bag,
    'groceries': Icons.local_grocery_store,
    'coffee': Icons.local_cafe,
    'car': Icons.directions_car,
    'fuel': Icons.local_gas_station,
    'travel': Icons.flight,
    'pets': Icons.pets,
    'gym': Icons.fitness_center,
    'phone': Icons.smartphone,
    'wifi': Icons.wifi,
    'clothes': Icons.checkroom,
    'kids': Icons.child_care,
    'beauty': Icons.spa,
    'gift': Icons.redeem,
    'savings': Icons.savings,
    'work': Icons.work,
    'tax': Icons.receipt_long,
    'insurance': Icons.shield,
    'music': Icons.music_note,
    'games': Icons.sports_esports,
    'books': Icons.menu_book,
    'other': Icons.category,
  };

  static IconData of(String key) => all[key] ?? Icons.category;

  /// Paleta accesible para categorías.
  static const List<int> palette = [
    0xFF2E7D32, 0xFF00897B, 0xFF00838F, 0xFF0277BD,
    0xFF1565C0, 0xFF283593, 0xFF6A1B9A, 0xFFAD1457,
    0xFFC62828, 0xFFEF6C00, 0xFFF9A825, 0xFF9E9D24,
    0xFF5D4037, 0xFF4E342E, 0xFF546E7A, 0xFF616161,
  ];
}
