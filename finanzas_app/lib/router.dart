import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'data/models/enums.dart';
import 'features/auth/auth_controller.dart';
import 'features/auth/forgot_password_screen.dart';
import 'features/auth/lock_screen.dart';
import 'features/auth/login_screen.dart';
import 'features/auth/register_screen.dart';
import 'features/budgets/budgets_screen.dart';
import 'features/categories/categories_screen.dart';
import 'features/categories/category_form_screen.dart';
import 'features/dashboard/dashboard_screen.dart';
import 'features/recurring/recurring_form_screen.dart';
import 'features/recurring/recurring_screen.dart';
import 'features/reports/reports_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/transactions/transaction_form_screen.dart';
import 'features/transactions/transactions_screen.dart';
import 'shared/widgets/app_shell.dart';

const _authRoutes = {'/login', '/register', '/forgot-password'};

/// Redirección según el estado de la sesión (separada para poder probarla).
String? authRedirect(AuthStatus status, String location) {
  switch (status) {
    case AuthStatus.unknown:
      return location == '/splash' ? null : '/splash';
    case AuthStatus.unauthenticated:
      return _authRoutes.contains(location) ? null : '/login';
    case AuthStatus.locked:
      return location == '/lock' ? null : '/lock';
    case AuthStatus.authenticated:
      if (_authRoutes.contains(location) || location == '/splash' || location == '/lock') return '/home';
      return null;
  }
}

GoRouter buildRouter(AuthController auth) {
  final rootKey = GlobalKey<NavigatorState>(debugLabel: 'root');

  return GoRouter(
    navigatorKey: rootKey,
    initialLocation: '/splash',
    refreshListenable: auth,
    redirect: (context, state) => authRedirect(auth.status, state.matchedLocation),
    routes: [
      GoRoute(path: '/splash', builder: (_, __) => const SplashScreen()),
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      GoRoute(path: '/register', builder: (_, __) => const RegisterScreen()),
      GoRoute(path: '/forgot-password', builder: (_, __) => const ForgotPasswordScreen()),
      GoRoute(path: '/lock', builder: (_, __) => const LockScreen()),

      // Navegación inferior (Agregar abre /transaction/new como pantalla completa).
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => AppShell(shell: shell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(path: '/home', builder: (_, __) => const DashboardScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/transactions', builder: (_, __) => const TransactionsScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/reports', builder: (_, __) => const ReportsScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/settings', builder: (_, __) => const SettingsScreen()),
          ]),
        ],
      ),

      // Pantallas completas
      GoRoute(
        path: '/transaction/new',
        builder: (_, state) => TransactionFormScreen(
          initialType: TxType.fromCode(state.uri.queryParameters['type'] ?? 'expense'),
        ),
      ),
      GoRoute(
        path: '/transaction/:id',
        builder: (_, state) => TransactionFormScreen(transactionId: state.pathParameters['id']),
      ),
      GoRoute(path: '/categories', builder: (_, __) => const CategoriesScreen()),
      GoRoute(
        path: '/categories/new',
        builder: (_, state) => CategoryFormScreen(
          initialType: TxType.fromCode(state.uri.queryParameters['type'] ?? 'expense'),
        ),
      ),
      GoRoute(
        path: '/categories/:id/edit',
        builder: (_, state) => CategoryFormScreen(categoryId: state.pathParameters['id']),
      ),
      GoRoute(path: '/budgets', builder: (_, __) => const BudgetsScreen()),
      GoRoute(path: '/recurring', builder: (_, __) => const RecurringScreen()),
      GoRoute(path: '/recurring/new', builder: (_, __) => const RecurringFormScreen()),
      GoRoute(
        path: '/recurring/:id',
        builder: (_, state) => RecurringFormScreen(recurringId: state.pathParameters['id']),
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      appBar: AppBar(title: const Text('Página no encontrada')),
      body: Center(
        child: TextButton(onPressed: () => context.go('/home'), child: const Text('Volver al inicio')),
      ),
    ),
  );
}
