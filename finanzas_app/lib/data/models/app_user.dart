import 'package:flutter/foundation.dart';

import 'enums.dart';

/// Preferencias del usuario.
@immutable
class UserSettings {
  const UserSettings({
    this.currency = 'PEN',
    this.themeMode = AppThemeMode.system,
    this.notificationsEnabled = true,
    this.budgetAlertsEnabled = true,
    this.recurringRemindersEnabled = true,
    this.biometricEnabled = false,
  });

  final String currency;
  final AppThemeMode themeMode;
  final bool notificationsEnabled;
  final bool budgetAlertsEnabled;
  final bool recurringRemindersEnabled;
  final bool biometricEnabled;

  UserSettings copyWith({
    String? currency,
    AppThemeMode? themeMode,
    bool? notificationsEnabled,
    bool? budgetAlertsEnabled,
    bool? recurringRemindersEnabled,
    bool? biometricEnabled,
  }) =>
      UserSettings(
        currency: currency ?? this.currency,
        themeMode: themeMode ?? this.themeMode,
        notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
        budgetAlertsEnabled: budgetAlertsEnabled ?? this.budgetAlertsEnabled,
        recurringRemindersEnabled: recurringRemindersEnabled ?? this.recurringRemindersEnabled,
        biometricEnabled: biometricEnabled ?? this.biometricEnabled,
      );

  Map<String, dynamic> toJson() => {
        'currency': currency,
        'theme_mode': themeMode.code,
        'notifications_enabled': notificationsEnabled,
        'budget_alerts_enabled': budgetAlertsEnabled,
        'recurring_reminders_enabled': recurringRemindersEnabled,
        'biometric_enabled': biometricEnabled,
      };

  factory UserSettings.fromJson(Map<String, dynamic> json) => UserSettings(
        currency: (json['currency'] as String?)?.trim() ?? 'PEN',
        themeMode: AppThemeMode.fromCode(json['theme_mode'] as String?),
        notificationsEnabled: json['notifications_enabled'] != false,
        budgetAlertsEnabled: json['budget_alerts_enabled'] != false,
        recurringRemindersEnabled: json['recurring_reminders_enabled'] != false,
        biometricEnabled: json['biometric_enabled'] == true,
      );
}

/// Usuario autenticado (local o Supabase) con su perfil.
@immutable
class AppUser {
  const AppUser({
    required this.id,
    required this.email,
    this.displayName,
    this.isRemote = false,
    this.settings = const UserSettings(),
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String email;
  final String? displayName;

  /// `true` si la cuenta vive en Supabase (sincroniza en la nube).
  final bool isRemote;
  final UserSettings settings;
  final DateTime createdAt;
  final DateTime updatedAt;

  String get greetingName {
    final name = displayName?.trim();
    if (name != null && name.isNotEmpty) return name.split(' ').first;
    return email.split('@').first;
  }

  AppUser copyWith({String? displayName, UserSettings? settings, DateTime? updatedAt}) => AppUser(
        id: id,
        email: email,
        displayName: displayName ?? this.displayName,
        isRemote: isRemote,
        settings: settings ?? this.settings,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  factory AppUser.fromDb(Map<String, Object?> row) => AppUser(
        id: row['id']! as String,
        email: row['email']! as String,
        displayName: row['display_name'] as String?,
        isRemote: (row['is_remote'] as int? ?? 0) == 1,
        settings: UserSettings(
          currency: (row['currency'] as String?) ?? 'PEN',
          themeMode: AppThemeMode.fromCode(row['theme_mode'] as String?),
          notificationsEnabled: (row['notifications_enabled'] as int? ?? 1) == 1,
          budgetAlertsEnabled: (row['budget_alerts_enabled'] as int? ?? 1) == 1,
          recurringRemindersEnabled: (row['recurring_reminders_enabled'] as int? ?? 1) == 1,
          biometricEnabled: (row['biometric_enabled'] as int? ?? 0) == 1,
        ),
        createdAt: DateTime.parse(row['created_at']! as String),
        updatedAt: DateTime.parse(row['updated_at']! as String),
      );
}
