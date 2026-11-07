import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/theme/app_theme.dart';
import 'data/repositories/data_change_bus.dart';
import 'features/auth/auth_controller.dart';
import 'providers.dart';
import 'router.dart';

class FinanzasApp extends ConsumerStatefulWidget {
  const FinanzasApp({super.key});

  @override
  ConsumerState<FinanzasApp> createState() => _FinanzasAppState();
}

class _FinanzasAppState extends ConsumerState<FinanzasApp> with WidgetsBindingObserver {
  late final GoRouter _router;
  StreamSubscription<DataChange>? _busSub;

  @override
  void initState() {
    super.initState();
    final auth = ref.read(authControllerProvider);
    _router = buildRouter(auth);
    WidgetsBinding.instance.addObserver(this);

    // Cada cambio de datos refresca las vistas; las preferencias sincronizadas
    // desde la nube recargan el perfil.
    _busSub = ref.read(dataChangeBusProvider).stream.listen((change) {
      ref.read(dataRevisionProvider.notifier).state++;
      if (change.table == ChangedTable.users && change.fromSync) {
        ref.read(authControllerProvider).reloadUser();
      }
    });

    Future.microtask(auth.init);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    final auth = ref.read(authControllerProvider);
    final user = auth.user;
    if (auth.status == AuthStatus.authenticated && user != null) {
      ref.read(sessionServiceProvider).onResume(user);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _busSub?.cancel();
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    return MaterialApp.router(
      title: 'Mis Finanzas',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: settings.themeMode.flutterMode,
      routerConfig: _router,
      locale: const Locale('es'),
      supportedLocales: const [Locale('es'), Locale('es', 'PE'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
    );
  }
}
