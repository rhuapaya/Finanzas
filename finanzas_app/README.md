# Mis Finanzas 💰

Aplicación móvil de finanzas personales para **Android e iOS** hecha con **Flutter** y **Supabase**.
Registra, organiza y analiza ingresos y egresos por categorías, con presupuestos, movimientos
recurrentes, reportes y funcionamiento sin conexión.

> La arquitectura, el modelo de datos y el flujo de navegación están en [`docs/ARQUITECTURA.md`](docs/ARQUITECTURA.md).

## Funcionalidades

| Módulo | Qué incluye |
|---|---|
| Autenticación | Registro, inicio de sesión, recuperación de contraseña (correo en Supabase / código en modo local), sesión persistente cifrada, cierre de sesión, bloqueo biométrico |
| Inicio | Saldo actual, ingresos/egresos/balance del periodo, dona de gastos por categoría, presupuestos en alerta, movimientos recientes, selector Día/Semana/Mes/Año/Rango |
| Movimientos | Crear, editar y eliminar (con confirmación); tipo, monto (> 0), categoría, fecha, descripción, método de pago, foto del comprobante, recurrencia; búsqueda y filtros |
| Categorías | 14 predeterminadas; crear/editar con nombre, color e icono; al eliminar con registros asociados se exige reasignarlos |
| Presupuestos | Límite mensual por categoría, consumido/disponible, alertas al 80 % y 100 % (notificación + aviso en pantalla) |
| Recurrentes | Diario, semanal, quincenal, mensual, anual; pausar/reanudar, fecha de fin; se generan automáticamente al abrir la app |
| Reportes | Comparación con el periodo anterior, barras ingresos vs egresos, tendencia de 12 meses, desglose por categoría, filtros, exportación **CSV** y **PDF** |
| Configuración | Moneda (PEN por defecto), tema claro/oscuro/automático, notificaciones, biometría, Supabase y sincronización, exportar/importar/eliminar datos, datos de prueba |

## Opción A — Obtener el APK sin instalar nada (GitHub Actions) ✅ recomendado

1. Crea un repositorio en GitHub y sube el contenido de esta carpeta.
2. (Opcional, para la nube) En **Settings › Secrets and variables › Actions** agrega
   `SUPABASE_URL` y `SUPABASE_ANON_KEY`. Si no los agregas, el APK funciona en modo local.
3. Ve a la pestaña **Actions › Compilar APK** (se ejecuta solo al hacer push, o con *Run workflow*).
4. Al terminar (~8–12 min), descarga el artefacto **MisFinanzas-apk** → `MisFinanzas.apk`.
5. Copia el APK al teléfono Android y ábrelo (activa *Instalar apps de origen desconocido* si lo pide).

Si creas un tag `v1.0.0`, el APK también se adjunta automáticamente al *Release*.

## Opción B — Compilar en tu PC

**Requisitos:** [Flutter 3.27+](https://docs.flutter.dev/get-started/install) y Android Studio (Android SDK).
Verifica con `flutter doctor`.

```bash
# Windows
build_apk.bat

# Linux / macOS
chmod +x build_apk.sh && ./build_apk.sh
```

El script ejecuta `flutter create` (genera las carpetas `android/` e `ios/`), aplica la configuración
nativa con `tool/patch_platforms.dart`, descarga dependencias y crea `MisFinanzas.apk`.

Manual, paso a paso:

```bash
flutter create --org com.fiamaster --project-name finanzas_app --platforms android,ios .
dart run tool/patch_platforms.dart
flutter pub get
flutter run                       # en emulador o teléfono conectado
flutter build apk --release       # instalador en build/app/outputs/flutter-apk/
```

Para iOS: `flutter build ipa` en una Mac con Xcode y una cuenta de Apple Developer.

> El APK de release se firma con la clave de depuración, suficiente para instalarlo directamente.
> Para publicarlo en Google Play crea tu propio keystore
> ([guía oficial](https://docs.flutter.dev/deployment/android#signing-the-app)).

## Configurar Supabase (nube y sincronización)

1. Crea un proyecto en [supabase.com](https://supabase.com).
2. En **SQL Editor** ejecuta `supabase/migrations/20261107000001_init.sql`
   (o con la CLI: `supabase link` + `supabase db push`). Crea las tablas, RLS, triggers y el bucket `receipts`.
3. En **Project Settings › API** copia la *Project URL* y la *anon public key*.
4. Úsalas de una de estas formas:
   - Al compilar: `--dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...` (o secretos de GitHub).
   - Desde la app: **Configuración › Configurar Supabase**, y reinicia la app.
5. (Opcional) En **Authentication › Providers › Email** puedes desactivar *Confirm email* para pruebas.
6. Datos de prueba en la nube: regístrate en la app y ejecuta `supabase/seed.sql` cambiando el correo.

Sin credenciales la app funciona en **modo local**: las cuentas y datos se guardan cifrados en el
dispositivo (al registrarte recibes un código para recuperar la contraseña).

## Datos de prueba

**Configuración › Cargar datos de prueba** genera 6 meses de movimientos, 3 presupuestos del mes
actual y 2 recurrentes (sueldo y alquiler).

## Pruebas

```bash
flutter test                                   # unitarias + integración (SQLite en memoria)
flutter test integration_test/app_flow_test.dart   # E2E en emulador/dispositivo
```

- `test/core/` – cálculos financieros, dinero exacto, presupuestos/alertas, fechas, recurrencias, validadores, PBKDF2.
- `test/data/flows_test.dart` – flujos completos sobre SQLite real: auth local, CRUD, reasignación de categorías, alertas 80/100 %, recurrentes, copias de seguridad y aislamiento por usuario.
- `test/widget_test.dart` – redirecciones del router, formateo de montos, validación del login.
- `integration_test/` – registro → agregar egreso → saldo en el panel.

En Linux, las pruebas con SQLite requieren `libsqlite3-dev` (`sudo apt install libsqlite3-dev`).

## Estructura

```
lib/
  core/        dinero, cálculos, utilidades, tema, BD local, seguridad, servicios
  data/        modelos, repositorios, servicios de negocio, sync, seed, exportación
  features/    auth, dashboard, transactions, categories, budgets, recurring, reports, settings
  shared/      widgets reutilizables
supabase/      migraciones SQL y seed
test/ integration_test/ tool/ .github/workflows/
```

## Seguridad

- Row Level Security: cada usuario solo lee/escribe filas con `user_id = auth.uid()`; además se valida
  que la categoría referenciada sea del mismo usuario.
- Comprobantes en bucket privado `receipts/{user_id}/…` con URLs firmadas temporales.
- Sesión de Supabase guardada en Keychain / EncryptedSharedPreferences.
- Contraseñas locales con PBKDF2-HMAC-SHA256 (10 000 iteraciones) y sal aleatoria.
- Dinero como `numeric(14,2)` en la nube y centavos enteros en el dispositivo (nunca `float`).
