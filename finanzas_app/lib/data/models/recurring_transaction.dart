import 'package:flutter/foundation.dart';

import '../../core/money/money.dart';
import '../../core/utils/dates.dart';
import 'enums.dart';

/// Regla de movimiento recurrente (p. ej. sueldo mensual, alquiler).
@immutable
class RecurringTransaction {
  const RecurringTransaction({
    required this.id,
    required this.userId,
    required this.type,
    required this.amount,
    required this.categoryId,
    this.description,
    this.paymentMethod = PaymentMethod.cash,
    required this.frequency,
    required this.startDate,
    required this.nextDate,
    this.endDate,
    this.status = RecurringStatus.active,
    this.lastGeneratedAt,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  final String id;
  final String userId;
  final TxType type;
  final Money amount;
  final String categoryId;
  final String? description;
  final PaymentMethod paymentMethod;
  final Frequency frequency;
  final DateTime startDate;
  final DateTime nextDate;
  final DateTime? endDate;
  final RecurringStatus status;
  final DateTime? lastGeneratedAt;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  /// Día del mes original (para mensual/anual).
  int get anchorDay => startDate.day;

  RecurringTransaction copyWith({
    TxType? type,
    Money? amount,
    String? categoryId,
    String? description,
    PaymentMethod? paymentMethod,
    Frequency? frequency,
    DateTime? startDate,
    DateTime? nextDate,
    DateTime? endDate,
    bool clearEndDate = false,
    RecurringStatus? status,
    DateTime? lastGeneratedAt,
    DateTime? updatedAt,
  }) =>
      RecurringTransaction(
        id: id,
        userId: userId,
        type: type ?? this.type,
        amount: amount ?? this.amount,
        categoryId: categoryId ?? this.categoryId,
        description: description ?? this.description,
        paymentMethod: paymentMethod ?? this.paymentMethod,
        frequency: frequency ?? this.frequency,
        startDate: startDate ?? this.startDate,
        nextDate: nextDate ?? this.nextDate,
        endDate: clearEndDate ? null : (endDate ?? this.endDate),
        status: status ?? this.status,
        lastGeneratedAt: lastGeneratedAt ?? this.lastGeneratedAt,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        deletedAt: deletedAt,
      );

  Map<String, Object?> toDb() => {
        'id': id,
        'user_id': userId,
        'type': type.code,
        'amount_cents': amount.cents,
        'category_id': categoryId,
        'description': description,
        'payment_method': paymentMethod.code,
        'frequency': frequency.code,
        'start_date': Dates.toIsoDate(startDate),
        'next_date': Dates.toIsoDate(nextDate),
        'end_date': endDate == null ? null : Dates.toIsoDate(endDate!),
        'status': status.code,
        'last_generated_at': lastGeneratedAt?.toUtc().toIso8601String(),
        'created_at': createdAt.toUtc().toIso8601String(),
        'updated_at': updatedAt.toUtc().toIso8601String(),
        'deleted_at': deletedAt?.toUtc().toIso8601String(),
      };

  factory RecurringTransaction.fromDb(Map<String, Object?> row) => RecurringTransaction(
        id: row['id']! as String,
        userId: row['user_id']! as String,
        type: TxType.fromCode(row['type'] as String?),
        amount: Money((row['amount_cents']! as num).toInt()),
        categoryId: row['category_id']! as String,
        description: row['description'] as String?,
        paymentMethod: PaymentMethod.fromCode(row['payment_method'] as String?),
        frequency: Frequency.fromCode(row['frequency'] as String?),
        startDate: Dates.parseIsoDate(row['start_date']! as String),
        nextDate: Dates.parseIsoDate(row['next_date']! as String),
        endDate: row['end_date'] == null ? null : Dates.parseIsoDate(row['end_date']! as String),
        status: RecurringStatus.fromCode(row['status'] as String?),
        lastGeneratedAt: row['last_generated_at'] == null
            ? null
            : DateTime.parse(row['last_generated_at']! as String),
        createdAt: DateTime.parse(row['created_at']! as String),
        updatedAt: DateTime.parse(row['updated_at']! as String),
        deletedAt: row['deleted_at'] == null ? null : DateTime.parse(row['deleted_at']! as String),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.code,
        'amount': amount.toDecimalString(),
        'category_id': categoryId,
        'description': description,
        'payment_method': paymentMethod.code,
        'frequency': frequency.code,
        'start_date': Dates.toIsoDate(startDate),
        'next_date': Dates.toIsoDate(nextDate),
        'end_date': endDate == null ? null : Dates.toIsoDate(endDate!),
        'status': status.code,
        'created_at': createdAt.toUtc().toIso8601String(),
        'updated_at': updatedAt.toUtc().toIso8601String(),
      };

  factory RecurringTransaction.fromJson(Map<String, dynamic> json, String userId) =>
      RecurringTransaction(
        id: json['id'] as String,
        userId: userId,
        type: TxType.fromCode(json['type'] as String?),
        amount: Money.fromDecimal(json['amount']),
        categoryId: json['category_id'] as String,
        description: json['description'] as String?,
        paymentMethod: PaymentMethod.fromCode(json['payment_method'] as String?),
        frequency: Frequency.fromCode(json['frequency'] as String?),
        startDate: Dates.parseIsoDate(json['start_date'] as String),
        nextDate: Dates.parseIsoDate(json['next_date'] as String),
        endDate: json['end_date'] == null ? null : Dates.parseIsoDate(json['end_date'] as String),
        status: RecurringStatus.fromCode(json['status'] as String?),
        createdAt: DateTime.parse(json['created_at'] as String),
        updatedAt: DateTime.parse(json['updated_at'] as String),
      );
}
