import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers.dart';
import 'auth_widgets.dart';

/// Pantalla de bloqueo biométrico al abrir la app con sesión activa.
class LockScreen extends ConsumerStatefulWidget {
  const LockScreen({super.key});

  @override
  ConsumerState<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<LockScreen> {
  bool _busy = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _unlock());
  }

  Future<void> _unlock() async {
    if (_busy) return;
    setState(() => _busy = true);
    final ok = await ref.read(authControllerProvider).unlockWithBiometrics();
    if (mounted) {
      setState(() {
        _busy = false;
        _failed = !ok;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              AuthHeader(
                title: 'Hola${user == null ? '' : ', ${user.greetingName}'}',
                subtitle: 'Desbloquea con tu huella, rostro o PIN del dispositivo',
              ),
              const SizedBox(height: 32),
              if (_failed)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text('No se pudo verificar tu identidad.',
                      textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ),
              FilledButton.icon(
                onPressed: _busy ? null : _unlock,
                icon: const Icon(Icons.fingerprint),
                label: const Text('Desbloquear'),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: _busy ? null : () => ref.read(authControllerProvider).signOut(),
                child: const Text('Usar correo y contraseña'),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.account_balance_wallet, size: 72, color: scheme.primary),
          const SizedBox(height: 16),
          Text('Mis Finanzas', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 24),
          const CircularProgressIndicator(),
        ]),
      ),
    );
  }
}
