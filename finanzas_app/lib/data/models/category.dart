import 'package:flutter/foundation.dart';

import 'enums.dart';

@immutable
class Category {
  const Category({
    required this.id,
    required this.userId,
    required this.name,
    required this.type,
    required this.color,
    required this.icon,
    this.isDefault = false,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  final String id;
  final String userId;
  final String name;
  final TxType type;

  /// Color ARGB (p. ej. 0xFF2E7D32).
  final int color;

  /// Clave del icono (ver `CategoryIcons`).
  final String icon;
  final bool isDefault;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  Category copyWith({
    String? name,
    TxType? type,
    int? color,
    String? icon,
    bool? isDefault,
    DateTime? updatedAt,
  }) =>
      Category(
        id: id,
        userId: userId,
        name: name ?? this.name,
        type: type ?? this.type,
        color: color ?? this.color,
        icon: icon ?? this.icon,
        isDefault: isDefault ?? this.isDefault,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        deletedAt: deletedAt,
      );

  Map<String, Object?> toDb() => {
        'id': id,
        'user_id': userId,
        'name': name,
        'type': type.code,
        'color': color,
        'icon': icon,
        'is_default': isDefault ? 1 : 0,
        'created_at': createdAt.toUtc().toIso8601String(),
        'updated_at': updatedAt.toUtc().toIso8601String(),
        'deleted_at': deletedAt?.toUtc().toIso8601String(),
      };

  factory Category.fromDb(Map<String, Object?> row) => Category(
        id: row['id']! as String,
        userId: row['user_id']! as String,
        name: row['name']! as String,
        type: TxType.fromCode(row['type'] as String?),
        color: (row['color']! as num).toInt(),
        icon: row['icon']! as String,
        isDefault: (row['is_default'] as int? ?? 0) == 1,
        createdAt: DateTime.parse(row['created_at']! as String),
        updatedAt: DateTime.parse(row['updated_at']! as String),
        deletedAt: row['deleted_at'] == null ? null : DateTime.parse(row['deleted_at']! as String),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type.code,
        'color': color,
        'icon': icon,
        'is_default': isDefault,
        'created_at': createdAt.toUtc().toIso8601String(),
        'updated_at': updatedAt.toUtc().toIso8601String(),
      };

  factory Category.fromJson(Map<String, dynamic> json, String userId) => Category(
        id: json['id'] as String,
        userId: userId,
        name: json['name'] as String,
        type: TxType.fromCode(json['type'] as String?),
        color: (json['color'] as num).toInt(),
        icon: json['icon'] as String,
        isDefault: json['is_default'] == true,
        createdAt: DateTime.parse(json['created_at'] as String),
        updatedAt: DateTime.parse(json['updated_at'] as String),
      );
}
