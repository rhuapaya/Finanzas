import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

/// Captura y guarda fotografías de comprobantes en el almacenamiento de la app.
class ReceiptStorage {
  ReceiptStorage([ImagePicker? picker]) : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;
  static const _uuid = Uuid();

  /// Abre la cámara o la galería y copia la imagen a `documentos/receipts/`.
  /// Devuelve la ruta local o `null` si el usuario canceló.
  Future<String?> pick({required bool fromCamera}) async {
    final XFile? image = await _picker.pickImage(
      source: fromCamera ? ImageSource.camera : ImageSource.gallery,
      imageQuality: 70,
      maxWidth: 1600,
      maxHeight: 1600,
    );
    if (image == null) return null;
    final dir = await getApplicationDocumentsDirectory();
    final receiptsDir = Directory(p.join(dir.path, 'receipts'));
    if (!await receiptsDir.exists()) await receiptsDir.create(recursive: true);
    final target = p.join(receiptsDir.path, '${_uuid.v4()}.jpg');
    await File(image.path).copy(target);
    return target;
  }

  static Future<void> deleteIfExists(String? path) async {
    if (path == null) return;
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }
}
