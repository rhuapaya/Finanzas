import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/app_config.dart';
import '../../core/money/currency.dart';
import '../../core/money/money.dart';
import '../../core/services/notification_service.dart';
import '../../data/models/app_user.dart';
import '../../data/models/enums.dart';
import '../../data/sync/sync_service.dart';
import '../../providers.dart';
import '../../shared/widgets/feedback.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  Future<void> _update(BuildContext context, WidgetRef ref, UserSettings settings) async {
    try {
      await ref.read(authControllerProvider).updateSettings(settings);
    } catch (e) {
      if (context.mounted) showErrorSnack(context, e);
    }
  }

  Future<void> _pickCurrency(BuildContext context, WidgetRef ref, UserSettings s) async {
    final selected = await showDialog<CurrencyInfo>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Moneda'),
        children: [
          for (final c in CurrencyInfo.all)
            ListTile(
              title: Text('${c.name} (${c.code})'),
              subtitle: Text(const Money(123456).format(c)),
              trailing: c.code == s.currency ? const Icon(Icons.check) : null,
              onTap: () => Navigator.pop(ctx, c),
            ),
        ],
      ),
    );
    if (selected != null && context.mounted) {
      await _update(context, ref, s.copyWith(currency: selected.code));
    }
  }

  Future<void> _toggleBiometric(BuildContext context, WidgetRef ref, UserSettings s, bool enable) async {
    final bio = ref.read(biometricServiceProvider);
    if (enable) {
      if (!await bio.isAvailable()) {
        if (context.mounted) {
          showInfoSnack(context, 'Tu dispositivo no tiene biometría configurada.');
        }
        return;
      }
      final ok = await bio.authenticate(reason: 'Confirma para activar el acceso biométrico');
      if (!ok) return;
    }
    if (context.mounted) await _update(context, ref, s.copyWith(biometricEnabled: enable));
  }

  Future<void> _toggleNotifications(BuildContext context, WidgetRef ref, UserSettings s, bool enable) async {
    if (enable) {
      final granted = await NotificationService.instance.requestPermission();
      if (!granted && context.mounted) {
        showInfoSnack(context, 'Activa el permiso de notificaciones en los ajustes del sistema.');
      }
    }
    if (context.mounted) await _update(context, ref, s.copyWith(notificationsEnabled: enable));
  }

  Future<void> _configureSupabase(BuildContext context, WidgetRef ref) async {
    final config = ref.read(appConfigProvider);
    if (config.fromEnvironment) {
      showInfoSnack(context, 'Las credenciales vienen incluidas en esta versión de la app.');
      return;
    }
    final url = TextEditingController(text: config.supabaseUrl ?? '');
    final key = TextEditingController(text: config.supabaseAnonKey ?? '');
    final save = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Conectar con Supabase'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Ingresa la URL y la clave anónima (anon key) de tu proyecto. '
                'Deja ambos campos vacíos para volver al modo local.'),
            const SizedBox(height: 12),
            TextField(
              controller: url,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(labelText: 'URL del proyecto', hintText: 'https://xxxx.supabase.co'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: key,
              decoration: const InputDecoration(labelText: 'Anon key'),
              maxLines: 3,
              minLines: 1,
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Guardar')),
        ],
      ),
    );
    if (save != true) return;
    final u = url.text.trim();
    if (u.isNotEmpty && !u.startsWith('https://')) {
      if (context.mounted) showInfoSnack(context, 'La URL debe comenzar con https://');
      return;
    }
    await AppConfig.saveCredentials(ref.read(sharedPreferencesProvider), url: u, anonKey: key.text.trim());
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.restart_alt),
        title: const Text('Reinicia la app'),
        content: const Text('Cierra y vuelve a abrir Mis Finanzas para aplicar la nueva configuración. '
            'Luego inicia sesión o crea una cuenta en la nube.'),
        actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Entendido'))],
      ),
    );
  }

  Future<void> _exportBackup(BuildContext context, WidgetRef ref, AppUser user) async {
    try {
      final file = await runWithProgress(context, () => ref.read(backupServiceProvider).exportToFile(user),
          message: 'Preparando copia…');
      if (file != null) await ref.read(exportServiceProvider).share(file, subject: 'Copia de Mis Finanzas');
    } catch (e) {
      if (context.mounted) showErrorSnack(context, e);
    }
  }

  Future<void> _importBackup(BuildContext context, WidgetRef ref, AppUser user) async {
    try {
      final picked = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['json']);
      final path = picked?.files.single.path;
      if (path == null || !context.mounted) return;
      final ok = await confirmAction(
        context,
        title: 'Importar copia',
        message: 'Los registros del archivo se agregarán o reemplazarán a los existentes con el mismo identificador.',
        confirmLabel: 'Importar',
        destructive: false,
      );
      if (!ok || !context.mounted) return;
      final summary = await runWithProgress(
        context,
        () => ref.read(backupServiceProvider).importFromFile(user, File(path)),
        message: 'Importando…',
      );
      if (summary != null && context.mounted) {
        showInfoSnack(context,
            'Importados: ${summary.transactions} movimientos, ${summary.categories} categorías, ${summary.budgets} presupuestos y ${summary.recurring} recurrentes.');
      }
    } catch (e) {
      if (context.mounted) showErrorSnack(context, e);
    }
  }

  Future<void> _loadDemo(BuildContext context, WidgetRef ref, AppUser user) async {
    final ok = await confirmAction(
      context,
      title: 'Cargar datos de prueba',
      message: 'Se agregarán 6 meses de movimientos de ejemplo, presupuestos y recurrentes.',
      confirmLabel: 'Cargar',
      destructive: false,
    );
    if (!ok || !context.mounted) return;
    try {
      final count = await runWithProgress(context, () => ref.read(demoDataServiceProvider).generate(user),
          message: 'Generando datos…');
      if (context.mounted) showInfoSnack(context, 'Se crearon $count movimientos de prueba.');
    } catch (e) {
      if (context.mounted) showErrorSnack(context, e);
    }
  }

  Future<void> _deleteData(BuildContext context, WidgetRef ref, AppUser user) async {
    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          icon: const Icon(Icons.delete_forever),
          title: const Text('Eliminar todos los datos'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(user.isRemote
                ? 'Se eliminarán tus movimientos, presupuestos, recurrentes, categorías y comprobantes en este dispositivo y en la nube.'
                : 'Se eliminarán tus movimientos, presupuestos, recurrentes y categorías de este dispositivo.'),
            const SizedBox(height: 8),
            const Text('Esta acción no se puede deshacer. Escribe ELIMINAR para confirmar.'),
            const SizedBox(height: 12),
            TextField(controller: controller, onChanged: (_) => setState(() {})),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
              onPressed: controller.text.trim().toUpperCase() == 'ELIMINAR' ? () => Navigator.pop(ctx, true) : null,
              child: const Text('Eliminar'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await runWithProgress(context, () async {
        if (user.isRemote) await ref.read(syncServiceProvider).deleteRemoteData(user.id);
        await ref.read(backupServiceProvider).deleteAllLocalData(user);
        if (user.isRemote) await ref.read(syncServiceProvider).syncNow();
      }, message: 'Eliminando…');
      if (context.mounted) showInfoSnack(context, 'Datos eliminados.');
    } catch (e) {
      if (context.mounted) showErrorSnack(context, e);
    }
  }

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    final ok = await confirmAction(
      context,
      title: 'Cerrar sesión',
      message: '¿Deseas cerrar sesión?',
      confirmLabel: 'Cerrar sesión',
      destructive: false,
    );
    if (ok) await ref.read(authControllerProvider).signOut();
  }

  Future<void> _editName(BuildContext context, WidgetRef ref, AppUser user) async {
    final controller = TextEditingController(text: user.displayName ?? '');
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tu nombre'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Nombre'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, controller.text), child: const Text('Guardar')),
        ],
      ),
    );
    if (name != null && name.trim().isNotEmpty) {
      await ref.read(authControllerProvider).updateDisplayName(name);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    if (user == null) return const Scaffold(body: SizedBox.shrink());
    final s = user.settings;
    final currency = CurrencyInfo.byCode(s.currency);
    final sync = ref.watch(syncServiceProvider);
    final config = ref.watch(appConfigProvider);
    final scheme = Theme.of(context).colorScheme;

    Widget header(String text) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
          child: Text(text, style: Theme.of(context).textTheme.labelLarge?.copyWith(color: scheme.primary)),
        );

    return Scaffold(
      appBar: AppBar(title: const Text('Configuración')),
      body: ListView(padding: const EdgeInsets.only(bottom: 32), children: [
        ListTile(
          leading: CircleAvatar(
            radius: 26,
            backgroundColor: scheme.primaryContainer,
            child: Text(user.greetingName.isEmpty ? '?' : user.greetingName.characters.first.toUpperCase(),
                style: TextStyle(fontSize: 22, color: scheme.onPrimaryContainer)),
          ),
          title: Text(user.displayName ?? user.greetingName),
          subtitle: Text('${user.email}\n${user.isRemote ? 'Cuenta en la nube' : 'Cuenta local'}'),
          isThreeLine: true,
          trailing: IconButton(
            tooltip: 'Editar nombre',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => _editName(context, ref, user),
          ),
        ),
        header('Finanzas'),
        ListTile(
          leading: const Icon(Icons.category_outlined),
          title: const Text('Categorías'),
          subtitle: const Text('Crear, editar y personalizar'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push('/categories'),
        ),
        ListTile(
          leading: const Icon(Icons.savings_outlined),
          title: const Text('Presupuestos'),
          subtitle: const Text('Límites mensuales y alertas'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push('/budgets'),
        ),
        ListTile(
          leading: const Icon(Icons.event_repeat),
          title: const Text('Movimientos recurrentes'),
          subtitle: const Text('Sueldos, alquileres, suscripciones'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push('/recurring'),
        ),
        header('Preferencias'),
        ListTile(
          leading: const Icon(Icons.payments_outlined),
          title: const Text('Moneda'),
          subtitle: Text('${currency.name} (${currency.code})'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _pickCurrency(context, ref, s),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.brightness_6_outlined),
              const SizedBox(width: 16),
              Text('Tema', style: Theme.of(context).textTheme.bodyLarge),
            ]),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<AppThemeMode>(
                segments: [
                  for (final m in AppThemeMode.values) ButtonSegment(value: m, label: Text(m.label)),
                ],
                selected: {s.themeMode},
                onSelectionChanged: (v) => _update(context, ref, s.copyWith(themeMode: v.first)),
              ),
            ),
          ]),
        ),
        SwitchListTile(
          secondary: const Icon(Icons.notifications_outlined),
          title: const Text('Notificaciones'),
          value: s.notificationsEnabled,
          onChanged: (v) => _toggleNotifications(context, ref, s, v),
        ),
        SwitchListTile(
          secondary: const Icon(Icons.warning_amber_outlined),
          title: const Text('Alertas de presupuesto'),
          subtitle: const Text('Al alcanzar el 80 % y el 100 %'),
          value: s.budgetAlertsEnabled,
          onChanged: s.notificationsEnabled ? (v) => _update(context, ref, s.copyWith(budgetAlertsEnabled: v)) : null,
        ),
        SwitchListTile(
          secondary: const Icon(Icons.repeat),
          title: const Text('Avisos de recurrentes'),
          subtitle: const Text('Cuando se registran automáticamente'),
          value: s.recurringRemindersEnabled,
          onChanged:
              s.notificationsEnabled ? (v) => _update(context, ref, s.copyWith(recurringRemindersEnabled: v)) : null,
        ),
        SwitchListTile(
          secondary: const Icon(Icons.fingerprint),
          title: const Text('Acceso biométrico'),
          subtitle: const Text('Pedir huella o rostro al abrir la app'),
          value: s.biometricEnabled,
          onChanged: (v) => _toggleBiometric(context, ref, s, v),
        ),
        header('Sincronización'),
        ValueListenableBuilder<SyncState>(
          valueListenable: sync.state,
          builder: (context, state, _) => ListTile(
            leading: Icon(user.isRemote ? Icons.cloud_outlined : Icons.phone_android),
            title: Text(user.isRemote ? 'Supabase' : 'Solo en este dispositivo'),
            subtitle: Text(state.lastSyncAt == null
                ? state.label
                : '${state.label}\nÚltima: ${TimeOfDay.fromDateTime(state.lastSyncAt!).format(context)}'),
            trailing: user.isRemote
                ? (state.phase == SyncPhase.syncing
                    ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                    : IconButton(
                        tooltip: 'Sincronizar ahora',
                        icon: const Icon(Icons.sync),
                        onPressed: () async {
                          final ok = await sync.syncNow();
                          if (context.mounted) {
                            showInfoSnack(context, ok ? 'Sincronización completa' : sync.state.value.label);
                          }
                        },
                      ))
                : null,
          ),
        ),
        ListTile(
          leading: const Icon(Icons.settings_ethernet),
          title: const Text('Configurar Supabase'),
          subtitle: Text(config.hasSupabaseCredentials
              ? (config.supabaseReady ? 'Conectado' : 'Credenciales guardadas (no se pudo conectar)')
              : 'No configurado'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _configureSupabase(context, ref),
        ),
        header('Datos'),
        ListTile(
          leading: const Icon(Icons.download_outlined),
          title: const Text('Exportar mis datos'),
          subtitle: const Text('Copia de seguridad en JSON'),
          onTap: () => _exportBackup(context, ref, user),
        ),
        ListTile(
          leading: const Icon(Icons.upload_outlined),
          title: const Text('Importar datos'),
          subtitle: const Text('Desde una copia JSON'),
          onTap: () => _importBackup(context, ref, user),
        ),
        ListTile(
          leading: const Icon(Icons.science_outlined),
          title: const Text('Cargar datos de prueba'),
          onTap: () => _loadDemo(context, ref, user),
        ),
        ListTile(
          leading: Icon(Icons.delete_forever_outlined, color: scheme.error),
          title: Text('Eliminar datos de la cuenta', style: TextStyle(color: scheme.error)),
          onTap: () => _deleteData(context, ref, user),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: OutlinedButton.icon(
            onPressed: () => _signOut(context, ref),
            icon: const Icon(Icons.logout),
            label: const Text('Cerrar sesión'),
          ),
        ),
        const SizedBox(height: 16),
        Center(child: Text('Mis Finanzas v1.0.0', style: Theme.of(context).textTheme.bodySmall)),
      ]),
    );
  }
}
