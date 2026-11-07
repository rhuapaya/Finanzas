import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Estructura con navegación inferior:
/// Inicio · Movimientos · Agregar · Reportes · Configuración.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  // Las ramas del shell son 4 (Agregar abre una pantalla completa).
  int get _selectedDestination => switch (shell.currentIndex) {
        0 => 0,
        1 => 1,
        2 => 3,
        3 => 4,
        _ => 0,
      };

  void _onSelected(BuildContext context, int destination) {
    if (destination == 2) {
      context.push('/transaction/new');
      return;
    }
    final branch = destination < 2 ? destination : destination - 1;
    shell.goBranch(branch, initialLocation: branch == shell.currentIndex);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: shell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedDestination,
        onDestinationSelected: (i) => _onSelected(context, i),
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Inicio',
          ),
          const NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long),
            label: 'Movimientos',
          ),
          NavigationDestination(
            key: const Key('nav_add'),
            icon: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(color: scheme.primary, shape: BoxShape.circle),
              child: Icon(Icons.add, color: scheme.onPrimary, size: 26),
            ),
            label: 'Agregar',
            tooltip: 'Agregar movimiento',
          ),
          const NavigationDestination(
            icon: Icon(Icons.bar_chart_outlined),
            selectedIcon: Icon(Icons.bar_chart),
            label: 'Reportes',
          ),
          const NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Configuración',
          ),
        ],
      ),
    );
  }
}
