import 'package:flutter/material.dart';

import '../../core/errors/error_handler.dart';

void showErrorSnack(BuildContext context, Object error) {
  ErrorHandler.log(error);
  final messenger = ScaffoldMessenger.maybeOf(context);
  messenger?.hideCurrentSnackBar();
  messenger?.showSnackBar(SnackBar(
    content: Text(ErrorHandler.message(error)),
    backgroundColor: Theme.of(context).colorScheme.error,
    showCloseIcon: true,
    closeIconColor: Theme.of(context).colorScheme.onError,
  ));
}

void showInfoSnack(BuildContext context, String message, {Duration duration = const Duration(seconds: 4)}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  messenger?.hideCurrentSnackBar();
  messenger?.showSnackBar(SnackBar(content: Text(message), duration: duration, showCloseIcon: true));
}

/// Diálogo de confirmación. Devuelve `true` si el usuario confirma.
Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Eliminar',
  bool destructive = true,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      final scheme = Theme.of(ctx).colorScheme;
      return AlertDialog(
        icon: Icon(destructive ? Icons.warning_amber_rounded : Icons.help_outline),
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancelar')),
          FilledButton(
            style: destructive
                ? FilledButton.styleFrom(
                    backgroundColor: scheme.error,
                    foregroundColor: scheme.onError,
                    minimumSize: const Size(64, 44),
                  )
                : FilledButton.styleFrom(minimumSize: const Size(64, 44)),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(confirmLabel),
          ),
        ],
      );
    },
  );
  return result ?? false;
}

/// Ejecuta [action] mostrando un indicador modal de carga.
Future<T?> runWithProgress<T>(BuildContext context, Future<T> Function() action, {String? message}) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(children: [
          const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 3)),
          const SizedBox(width: 20),
          Expanded(child: Text(message ?? 'Procesando…')),
        ]),
      ),
    ),
  );
  try {
    return await action();
  } finally {
    navigator.pop();
  }
}
