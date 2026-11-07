// Configura los proyectos nativos generados por `flutter create`:
//   - Android: permisos, FlutterFragmentActivity (biometría), desugaring
//     (notificaciones), minSdk 23 y nombre visible de la app.
//   - iOS: textos de permisos de cámara, galería y Face ID.
//
// Uso (desde la raíz del proyecto):
//   flutter create --org com.fiamaster --platforms android,ios .
//   dart run tool/patch_platforms.dart
//
// Es idempotente: puede ejecutarse varias veces sin duplicar cambios.
// ignore_for_file: avoid_print
import 'dart:io';

const appLabel = 'Mis Finanzas';

void main() {
  var ok = true;
  ok &= _patchManifest();
  ok &= _patchMainActivity();
  ok &= _patchGradle();
  ok &= _patchInfoPlist();
  if (!ok) {
    stderr.writeln('\nAlgunos archivos no se encontraron. ¿Ejecutaste "flutter create" primero?');
    exit(1);
  }
  print('\nPlataformas configuradas correctamente.');
}

bool _patchManifest() {
  final file = File('android/app/src/main/AndroidManifest.xml');
  if (!file.existsSync()) return _missing(file.path);
  var s = file.readAsStringSync();
  const permissions = [
    'android.permission.INTERNET',
    'android.permission.ACCESS_NETWORK_STATE',
    'android.permission.USE_BIOMETRIC',
    'android.permission.CAMERA',
    'android.permission.POST_NOTIFICATIONS',
  ];
  final missing = permissions.where((p) => !s.contains('"$p"')).toList();
  if (missing.isNotEmpty) {
    final block = missing.map((p) => '    <uses-permission android:name="$p"/>').join('\n');
    final match = RegExp(r'<manifest[^>]*>').firstMatch(s)!;
    s = '${s.substring(0, match.end)}\n$block${s.substring(match.end)}';
  }
  s = s.replaceAll(RegExp(r'android:label="[^"]*"'), 'android:label="$appLabel"');
  file.writeAsStringSync(s);
  print('✔ AndroidManifest.xml');
  return true;
}

bool _patchMainActivity() {
  final dir = Directory('android/app/src/main');
  if (!dir.existsSync()) return _missing(dir.path);
  final candidates = dir
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('MainActivity.kt') || f.path.endsWith('MainActivity.java'))
      .toList();
  if (candidates.isEmpty) return _missing('MainActivity');
  for (final f in candidates) {
    var s = f.readAsStringSync();
    s = s
        .replaceAll('io.flutter.embedding.android.FlutterActivity', 'io.flutter.embedding.android.FlutterFragmentActivity')
        .replaceAll(RegExp(r'\bFlutterActivity\(\)'), 'FlutterFragmentActivity()')
        .replaceAll(RegExp(r'extends FlutterActivity\b'), 'extends FlutterFragmentActivity');
    f.writeAsStringSync(s);
    print('✔ ${f.path}');
  }
  return true;
}

bool _patchGradle() {
  final kts = File('android/app/build.gradle.kts');
  final groovy = File('android/app/build.gradle');
  if (kts.existsSync()) {
    var s = kts.readAsStringSync();
    if (!s.contains('isCoreLibraryDesugaringEnabled')) {
      s = s.replaceFirst('compileOptions {', 'compileOptions {\n        isCoreLibraryDesugaringEnabled = true');
    }
    s = s.replaceAll(RegExp(r'minSdk\s*=\s*flutter\.minSdkVersion'), 'minSdk = maxOf(23, flutter.minSdkVersion)');
    if (!s.contains('desugar_jdk_libs')) {
      s += '\ndependencies {\n    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")\n}\n';
    }
    kts.writeAsStringSync(s);
    print('✔ ${kts.path}');
    return true;
  }
  if (groovy.existsSync()) {
    var s = groovy.readAsStringSync();
    if (!s.contains('coreLibraryDesugaringEnabled')) {
      s = s.replaceFirst('compileOptions {', 'compileOptions {\n        coreLibraryDesugaringEnabled true');
    }
    s = s
        .replaceAll(RegExp(r'minSdkVersion\s+flutter\.minSdkVersion'), 'minSdkVersion Math.max(23, flutter.minSdkVersion)')
        .replaceAll(RegExp(r'minSdk\s*=\s*flutter\.minSdkVersion'), 'minSdk = Math.max(23, flutter.minSdkVersion)');
    if (!s.contains('desugar_jdk_libs')) {
      s += "\ndependencies {\n    coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.1.4'\n}\n";
    }
    groovy.writeAsStringSync(s);
    print('✔ ${groovy.path}');
    return true;
  }
  return _missing('android/app/build.gradle(.kts)');
}

bool _patchInfoPlist() {
  final file = File('ios/Runner/Info.plist');
  if (!file.existsSync()) {
    print('• iOS no generado (se omite Info.plist)');
    return true;
  }
  var s = file.readAsStringSync();
  const entries = {
    'NSCameraUsageDescription': 'Se usa la cámara para fotografiar comprobantes de tus movimientos.',
    'NSPhotoLibraryUsageDescription': 'Se accede a tus fotos para adjuntar comprobantes.',
    'NSFaceIDUsageDescription': 'Se usa Face ID para proteger el acceso a tus finanzas.',
  };
  final buffer = StringBuffer();
  entries.forEach((key, value) {
    if (!s.contains('<key>$key</key>')) {
      buffer.write('\t<key>$key</key>\n\t<string>$value</string>\n');
    }
  });
  if (buffer.isNotEmpty) {
    final idx = s.lastIndexOf('</dict>');
    s = '${s.substring(0, idx)}$buffer${s.substring(idx)}';
  }
  s = s.replaceAllMapped(
    RegExp(r'(<key>CFBundleDisplayName</key>\s*<string>)[^<]*(</string>)'),
    (m) => '${m[1]}$appLabel${m[2]}',
  );
  file.writeAsStringSync(s);
  print('✔ ${file.path}');
  return true;
}

bool _missing(String path) {
  stderr.writeln('✘ No se encontró $path');
  return false;
}
