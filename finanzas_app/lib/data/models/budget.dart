import 'package:flutter/foundation.dart';

import '../../core/money/money.dart';

/// Presupuesto mensual de una categoría de egresos.
@immutable
class Budget {
  const Budget({
    required this.id,
    required this.userId,
    required this.categoryId,
    required this.limit,
    required this.month,
    required this.year,
    this.alert80Sent = false,
    this.alert100Sent = false,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  final String id;
  final String userId;
  final String categoryId;
  final Money limit;
  final int month;
  final int year;
  final bool alert80Sent;
  final bool alert100Sent;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  Budget copyWith({
    String? categoryId,
    Money? limit,
    int? month,
    int? year,
    bool? alert80Sent,
    bool? alert100Sent,
    DateTime? updatedAt,
  }) =>
      Budget(
        id: id,
        userId: userId,
        categoryId: categoryId ?? this.categoryId,
        limit: limit ?? this.limit,
        month: month ?? this.month,
        year: year ?? this.year,
        alert80Sent: alert80Sent ?? this.alert80Sent,
        alert100Sent: alert100Sent ?? this.alert100Sent,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        deletedAt: deletedAt,
      );

  Map<String, Object?> toDb() => {
        'id': id,
        'user_id': userId,
        'category_id': categoryId,
        'limit_cents': limit.cents,
        'month': month,
        'year': year,
        'alert_80_sent': alert80Sent ? 1 : 0,
        'alert_100_sent': alert100Sent ? 1 : 0,
        'created_at': createdAt.toUtc().toIso8601String(),
        'updated_at': updatedAt.toUtc().toIso8601String(),
        'deleted_at': deletedAt?.toUtc().toIso8601String(),
      };

  factory Budget.fromDb(Map<String, Object?> row) => Budget(
        id: row['id']! as String,
        userId: row['user_id']! as String,
        categoryId: row['category_id']! as String,
        limit: Money((row['limit_cents']! as num).toInt()),
        month: (row['month']! as num).toInt(),
        year: (row['year']! as num).toInt(),
        alert80Sent: (row['alert_80_sent'] as int? ?? 0) == 1,
        alert100Sent: (row['alert_100_sent'] as int? ?? 0) == 1,
        createdAt: DateTime.parse(row['created_at']! as String),
        updatedAt: DateTime.parse(row['updated_at']! as String),
        deletedAt: row['deleted_at'] == null ? null : DateTime.parse(row['deleted_at']! as String),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'category_id': categoryId,
        'limit_amount': limit.toDecimalString(),
        'month': month,
        'year': year,
        'created_at': createdAt.toUtc().toIso8601String(),
        'updated_at': updatedAt.toUtc().toIso8601String(),
      };

  factory Budget.fromJson(Map<String, dynamic> json, String userId) => Budget(
        id: json['id'] as String,
        userId: userId,
        categoryId: json['category_id'] as String,
        limit: Money.fromDecimal(json['limit_amount']),
        month: (json['month'] as num).toInt(),
        year: (json['year'] as num).toInt(),
        createdAt: DateTime.parse(json['created_at'] as String),
        updatedAt: DateTime.parse(json['updated_at'] as String),
      );
}
