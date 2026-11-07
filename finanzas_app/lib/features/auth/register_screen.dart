import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/utils/validators.dart';
import '../../providers.dart';
import '../../shared/widgets/feedback.dart';
import 'auth_widgets.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    setState(() => _loading = true);
    final auth = ref.read(authControllerProvider);
    try {
      final result = await auth.signUp(
        email: _email.text,
        password: _password.text,
        displayName: _name.text,
      );
      if (!mounted) return;
      if (result.needsEmailConfirmation) {
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            icon: const Icon(Icons.mark_email_read_outlined),
            title: const Text('Confirma tu correo'),
            content: Text(
                'Te enviamos un enlace a ${_email.text.trim()}. Confírmalo y luego inicia sesión.'),
            actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Entendido'))],
          ),
        );
        if (mounted) context.go('/login');
        return;
      }
      if (result.recoveryCode != null) {
        await _showRecoveryCode(result.recoveryCode!);
      }
      if (result.user != null) auth.completeSignUp(result.user!);
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _showRecoveryCode(String code) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.key),
        title: const Text('Guarda tu código de recuperación'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text(
              'Tu cuenta vive solo en este dispositivo. Si olvidas tu contraseña necesitarás este código. '
              'Anótalo en un lugar seguro: no se volverá a mostrar.'),
          const SizedBox(height: 16),
          SelectableText(
            code,
            key: const Key('recovery_code'),
            style: Theme.of(ctx).textTheme.headlineSmall?.copyWith(letterSpacing: 3, fontWeight: FontWeight.bold),
          ),
        ]),
        actions: [
          TextButton.icon(
            onPressed: () => Clipboard.setData(ClipboardData(text: code)),
            icon: const Icon(Icons.copy),
            label: const Text('Copiar'),
          ),
          FilledButton(
            key: const Key('recovery_ok'),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Ya lo guardé'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Crear cuenta')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Form(
                key: _formKey,
                child: AutofillGroup(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const AuthHeader(title: 'Bienvenido', subtitle: 'Crea tu cuenta para empezar'),
                      const SizedBox(height: 28),
                      TextFormField(
                        key: const Key('register_name'),
                        controller: _name,
                        textCapitalization: TextCapitalization.words,
                        textInputAction: TextInputAction.next,
                        autofillHints: const [AutofillHints.name],
                        decoration: const InputDecoration(
                          labelText: 'Nombre',
                          prefixIcon: Icon(Icons.person_outline),
                        ),
                        validator: (v) => Validators.requiredField(v, 'El nombre'),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        key: const Key('register_email'),
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        autofillHints: const [AutofillHints.email],
                        decoration: const InputDecoration(
                          labelText: 'Correo electrónico',
                          prefixIcon: Icon(Icons.email_outlined),
                        ),
                        validator: Validators.email,
                      ),
                      const SizedBox(height: 16),
                      PasswordField(
                        key: const Key('register_password'),
                        controller: _password,
                        textInputAction: TextInputAction.next,
                        autofillHints: const [AutofillHints.newPassword],
                        validator: Validators.password,
                      ),
                      Padding(
                        padding: const EdgeInsets.only(left: 12, top: 4),
                        child: Text('Mínimo 8 caracteres, con letras y números.',
                            style: Theme.of(context).textTheme.bodySmall),
                      ),
                      const SizedBox(height: 16),
                      PasswordField(
                        key: const Key('register_confirm'),
                        controller: _confirm,
                        label: 'Confirmar contraseña',
                        autofillHints: const [AutofillHints.newPassword],
                        validator: (v) => v != _password.text ? 'Las contraseñas no coinciden' : null,
                        onSubmitted: (_) => _submit(),
                      ),
                      const SizedBox(height: 24),
                      LoadingButton(
                        key: const Key('register_submit'),
                        label: 'Crear cuenta',
                        loading: _loading,
                        onPressed: _submit,
                      ),
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: () => context.canPop() ? context.pop() : context.go('/login'),
                        child: const Text('Ya tengo una cuenta'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
