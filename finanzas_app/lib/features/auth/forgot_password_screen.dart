import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/utils/validators.dart';
import '../../providers.dart';
import '../../shared/widgets/feedback.dart';
import 'auth_widgets.dart';

/// Recuperación de contraseña.
/// - Supabase: envía un enlace por correo.
/// - Modo local: código de recuperación + nueva contraseña.
class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _code = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;
  bool _sent = false;

  @override
  void dispose() {
    _email.dispose();
    _code.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _loading = true);
    final auth = ref.read(authControllerProvider);
    try {
      if (auth.isRemoteMode) {
        await auth.sendPasswordReset(_email.text);
        if (mounted) setState(() => _sent = true);
      } else {
        await auth.resetWithRecoveryCode(
          email: _email.text,
          recoveryCode: _code.text,
          newPassword: _password.text,
        );
        if (!mounted) return;
        showInfoSnack(context, 'Contraseña actualizada. Ya puedes iniciar sesión.');
        context.go('/login');
      }
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final remote = ref.watch(authControllerProvider).isRemoteMode;
    return Scaffold(
      appBar: AppBar(title: const Text('Recuperar contraseña')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: _sent
                  ? Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      const AuthHeader(
                        title: 'Revisa tu correo',
                        subtitle: 'Si el correo está registrado, recibirás un enlace para crear una nueva contraseña.',
                      ),
                      const SizedBox(height: 24),
                      FilledButton(onPressed: () => context.go('/login'), child: const Text('Volver al inicio')),
                    ])
                  : Form(
                      key: _formKey,
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        AuthHeader(
                          title: '¿Olvidaste tu contraseña?',
                          subtitle: remote
                              ? 'Ingresa tu correo y te enviaremos un enlace de recuperación.'
                              : 'Ingresa tu correo, el código de recuperación que guardaste al registrarte y tu nueva contraseña.',
                        ),
                        const SizedBox(height: 24),
                        TextFormField(
                          controller: _email,
                          keyboardType: TextInputType.emailAddress,
                          decoration: const InputDecoration(
                            labelText: 'Correo electrónico',
                            prefixIcon: Icon(Icons.email_outlined),
                          ),
                          validator: Validators.email,
                        ),
                        if (!remote) ...[
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _code,
                            textCapitalization: TextCapitalization.characters,
                            decoration: const InputDecoration(
                              labelText: 'Código de recuperación',
                              hintText: 'XXXX-XXXX',
                              prefixIcon: Icon(Icons.key),
                            ),
                            validator: (v) => Validators.requiredField(v, 'El código'),
                          ),
                          const SizedBox(height: 16),
                          PasswordField(
                            controller: _password,
                            label: 'Nueva contraseña',
                            autofillHints: const [AutofillHints.newPassword],
                            validator: Validators.password,
                          ),
                        ],
                        const SizedBox(height: 24),
                        LoadingButton(
                          label: remote ? 'Enviar enlace' : 'Restablecer contraseña',
                          loading: _loading,
                          onPressed: _submit,
                        ),
                      ]),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
