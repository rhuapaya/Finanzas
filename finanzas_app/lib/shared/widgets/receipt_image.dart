import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers.dart';

/// Muestra el comprobante desde el archivo local o, si no existe, desde la nube.
class ReceiptImage extends ConsumerWidget {
  const ReceiptImage({super.key, this.localPath, this.remotePath, this.height = 180});

  final String? localPath;
  final String? remotePath;
  final double height;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    Widget placeholder(IconData icon, String text) => Container(
          height: height,
          alignment: Alignment.center,
          color: scheme.surfaceContainerHighest,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, color: scheme.onSurfaceVariant),
            const SizedBox(height: 6),
            Text(text, style: TextStyle(color: scheme.onSurfaceVariant)),
          ]),
        );

    final local = localPath;
    if (local != null && File(local).existsSync()) {
      return Image.file(File(local), height: height, fit: BoxFit.cover, semanticLabel: 'Comprobante');
    }
    final remote = remotePath;
    if (remote == null) return placeholder(Icons.image_not_supported_outlined, 'Sin comprobante');

    return FutureBuilder<String?>(
      future: ref.read(syncServiceProvider).receiptUrl(remote),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return SizedBox(height: height, child: const Center(child: CircularProgressIndicator()));
        }
        final url = snap.data;
        if (url == null) return placeholder(Icons.cloud_off, 'Comprobante no disponible sin conexión');
        return Image.network(
          url,
          height: height,
          fit: BoxFit.cover,
          semanticLabel: 'Comprobante',
          errorBuilder: (_, __, ___) => placeholder(Icons.broken_image_outlined, 'No se pudo cargar'),
        );
      },
    );
  }
}
