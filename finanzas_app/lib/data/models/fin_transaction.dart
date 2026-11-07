import 'package:flutter/foundation.dart';

import '../../core/money/money.dart';
import '../../core/utils/dates.dart';
import 'enums.dart';

/// Movimiento (ingreso o egreso).
@immutable
class FinTransaction {
  const FinTransaction({
    required this.id,
    required this.userId,
    required this.type,
    required this.amount,
    required this.categoryId,
    required this.date,
    this.description,
    this.paymentMethod = PaymentMethod.cash,
    this.receiptLocalPath,
    this.receiptRemotePath,
    this.recurringId,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  final String id;
  final String userId;
  final TxType type;
  final Money amount;
  final String categoryId;
  final DateTime date;
  final String? description;
  final PaymentMethod paymentMethod;

  /// Ruta del comprobante en el dispositivo.
  final String? receiptLocalPath;

  /// Ruta del comprobante en Supabase Storage (`{uid}/{id}.jpg`).
  final String? receiptRemotePath;
  final String? recurringId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  bool get hasReceipt => receiptLocalPath != null || receiptRemotePath != null;

  /// Importe con signo: positivo para ingresos, negativo para egresos.
  Money get signedAmount => type == TxType.income ? amount : -amount;

  FinTransaction copyWith({
    TxType? type,
    Money? amount,
    String? categoryId,
    DateTime? date,
    String? description,
    PaymentMethod? paymentMethod,
    String? receiptLocalPath,
    String? receiptRemotePath,
    bool clearReceipt = false,
    String? recurringId,
    DateTime? updatedAt,
  }) =>
      FinTransaction(
        id: id,
        userId: userId,
        type: type ?? this.type,
        amount: amount ?? this.amount,
        categoryId: categoryId ?? this.categoryId,
        date: date ?? this.date,
        description: description ?? this.description,
        paymentMethod: paymentMethod ?? this.paymentMethod,
        receiptLocalPath: clearReceipt ? null : (receiptLocalPath ?? this.receiptLocalPath),
        receiptRemotePath: clearReceipt ? null : (receiptRemotePath ?? this.receiptRemotePath),
        recurringId: recurringId ?? this.recurringId,
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
        'date': Dates.toIsoDate(date),
        'description': description,
        'payment_method': paymentMethod.code,
        'receipt_local_path': receiptLocalPath,
        'receipt_remote_path': receiptRemotePath,
        'recurring_id': recurringId,
        'created_at': createdAt.toUtc().toIso8601String(),
        'updated_at': updatedAt.toUtc().toIso8601String(),
        'deleted_at': deletedAt?.toUtc().toIso8601String(),
      };

  factory FinTransaction.fromDb(Map<String, Object?> row) => FinTransaction(
        id: row['id']! as String,
        userId: row['user_id']! as String,
        type: TxType.fromCode(row['type'] as String?),
        amount: Money((row['amount_cents']! as num).toInt()),
        categoryId: row['category_id']! as String,
        date: Dates.parseIsoDate(row['date']! as String),
        description: row['description'] as String?,
        paymentMethod: PaymentMethod.fromCode(row['payment_method'] as String?),
        receiptLocalPath: row['receipt_local_path'] as String?,
        receiptRemotePath: row['receipt_remote_path'] as String?,
        recurringId: row['recurring_id'] as String?,
        createdAt: DateTime.parse(row['created_at']! as String),
        updatedAt: DateTime.parse(row['updated_at']! as String),
        deletedAt: row['deleted_at'] == null ? null : DateTime.parse(row['deleted_at']! as String),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.code,
        'amount': amount.toDecimalString(),
        'category_id': categoryId,
        'date': Dates.toIsoDate(date),
        'description': description,
        'payment_method': paymentMethod.code,
        'recurring_id': recurringId,
        'created_at': createdAt.toUtc().toIso8601String(),
        'updated_at': updatedAt.toUtc().toIso8601String(),
      };

  factory FinTransaction.fromJson(Map<String, dynamic> json, String userId) => FinTransaction(
        id: json['id'] as String,
        userId: userId,
        type: TxType.fromCode(json['type'] as String?),
        amount: Money.fromDecimal(json['amount']),
        categoryId: json['category_id'] as String,
        date: Dates.parseIsoDate(json['date'] as String),
        description: json['description'] as String?,
        paymentMethod: PaymentMethod.fromCode(json['payment_method'] as String?),
        recurringId: json['recurring_id'] as String?,
        createdAt: DateTime.parse(json['created_at'] as String),
        updatedAt: DateTime.parse(json['updated_at'] as String),
      );
}
