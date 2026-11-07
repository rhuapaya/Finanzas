#!/usr/bin/env bash
# Compila el instalador APK de Mis Finanzas (Linux / macOS).
# Requisitos: Flutter 3.27+ y Android SDK (Android Studio) instalados.
# Opcional: exporta SUPABASE_URL y SUPABASE_ANON_KEY para incluir la nube.
set -euo pipefail
cd "$(dirname "$0")"

if [ ! -d android ]; then
  echo "» Generando proyecto Android/iOS…"
  flutter create --org com.fiamaster --project-name finanzas_app --platforms android,ios .
fi

echo "» Configurando permisos y Gradle…"
dart run tool/patch_platforms.dart

echo "» Descargando dependencias…"
flutter pub get

echo "» Ejecutando pruebas…"
flutter test || echo "Advertencia: hay pruebas fallidas (se continúa con la compilación)."

echo "» Compilando APK…"
flutter build apk --release \
  --dart-define=SUPABASE_URL="${SUPABASE_URL:-}" \
  --dart-define=SUPABASE_ANON_KEY="${SUPABASE_ANON_KEY:-}"

cp build/app/outputs/flutter-apk/app-release.apk MisFinanzas.apk
echo ""
echo "✔ Listo: $(pwd)/MisFinanzas.apk"
