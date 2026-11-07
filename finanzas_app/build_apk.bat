@echo off
REM Compila el instalador APK de Mis Finanzas (Windows).
REM Requisitos: Flutter 3.27+ y Android Studio (Android SDK) instalados.
REM Opcional: set SUPABASE_URL=... y set SUPABASE_ANON_KEY=... antes de ejecutar.
setlocal
cd /d "%~dp0"

if not exist android (
  echo ^> Generando proyecto Android/iOS...
  call flutter create --org com.fiamaster --project-name finanzas_app --platforms android,ios .
  if errorlevel 1 goto :error
)

echo ^> Configurando permisos y Gradle...
call dart run tool/patch_platforms.dart
if errorlevel 1 goto :error

echo ^> Descargando dependencias...
call flutter pub get
if errorlevel 1 goto :error

echo ^> Compilando APK...
call flutter build apk --release --dart-define=SUPABASE_URL=%SUPABASE_URL% --dart-define=SUPABASE_ANON_KEY=%SUPABASE_ANON_KEY%
if errorlevel 1 goto :error

copy /Y build\app\outputs\flutter-apk\app-release.apk MisFinanzas.apk >nul
echo.
echo Listo: %CD%\MisFinanzas.apk
pause
exit /b 0

:error
echo.
echo Ocurrio un error. Revisa los mensajes anteriores.
pause
exit /b 1
