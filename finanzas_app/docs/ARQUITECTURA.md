# Mis Finanzas — Arquitectura

## 1. Visión general

App móvil **Flutter** (Android/iOS) con enfoque **offline‑first**:

- La base de datos local **SQLite** (`sqflite`) es la fuente de verdad en el dispositivo. Toda pantalla lee y escribe localmente, por eso la app funciona sin Internet.
- **Supabase** (Auth + PostgreSQL + Storage) es el backend en la nube. Un `SyncService` sube los cambios pendientes y descarga los remotos cuando hay conexión (last‑write‑wins por `updated_at`).
- Si no se configuran credenciales de Supabase, la app funciona en **modo local** (cuentas guardadas en el dispositivo con contraseña PBKDF2‑SHA256 y código de recuperación).

```
┌──────────────────────── Presentación (features/*) ────────────────────────┐
│  Screens + widgets reutilizables (shared/widgets)  ·  go_router           │
└──────────────▲────────────────────────────────────────────────────────────┘
               │ Riverpod (providers.dart)
┌──────────────┴──────────── Dominio / servicios (data/services) ───────────┐
│ TransactionService · BudgetAlertService · RecurringService · SessionService│
│ FinanceCalculator (core/finance) – cálculos puros y testeables            │
└──────────────▲────────────────────────────────────────────────────────────┘
               │
┌──────────────┴──────────── Datos (data/repositories) ─────────────────────┐
│ Repositorios SQLite  ·  AuthRepository (Local | Supabase)  ·  SyncService │
└──────────────▲───────────────────────────────▲────────────────────────────┘
          SQLite local                    Supabase (RLS por usuario)
```

### Decisiones clave

| Tema | Decisión |
|---|---|
| Dinero | Clase `Money` con **centavos enteros** (aritmética exacta, sin `double`). En Supabase: `numeric(14,2)`. En SQLite: `INTEGER` (centavos). |
| Estado | `flutter_riverpod` (providers + `dataRevisionProvider` que refresca vistas tras cada cambio). |
| Navegación | `go_router` con `StatefulShellRoute` y barra inferior: Inicio · Movimientos · **Agregar** · Reportes · Configuración. |
| Seguridad | RLS en todas las tablas (`user_id = auth.uid()`), bucket privado `receipts/{uid}/…`, sesión en `flutter_secure_storage`, bloqueo biométrico opcional. |
| Errores | `AppException` + `ErrorHandler.message()` traduce excepciones (Auth, red, BD) a mensajes en español; `runZonedGuarded` captura errores no controlados. |
| Offline | Columnas `sync_status` y `deleted_at` (borrado lógico) en local; sincronización al iniciar sesión, al recuperar conexión, al volver a la app y tras cada cambio (con debounce). |

## 2. Estructura de carpetas

```
lib/
  main.dart                 Punto de entrada (bootstrap)
  app.dart                  MaterialApp.router, tema, ciclo de vida
  router.dart               Rutas y redirecciones por estado de sesión
  providers.dart            Inyección de dependencias (Riverpod)
  core/
    config/                 AppConfig (credenciales Supabase)
    errors/                 AppException, ErrorHandler
    money/                  Money, CurrencyInfo
    finance/                FinanceCalculator, alertas de presupuesto
    utils/                  DateRange/periodos, recurrencia, validadores, formateadores
    theme/                  Tema claro/oscuro, iconos de categorías
    db/                     LocalDatabase (esquema SQLite)
    security/               PasswordHasher, almacenamiento seguro
    services/               Notificaciones, biometría, conectividad
  data/
    models/                 AppUser, Category, FinTransaction, Budget, RecurringTransaction
    repositories/           CRUD SQLite + Auth (local/Supabase)
    services/               Lógica de negocio (transacciones, presupuestos, recurrentes, sesión)
    sync/                   SyncService (Supabase ↔ SQLite)
    seed/                   Categorías predeterminadas y datos de prueba
    io/                     Exportación CSV/PDF y copias JSON
  features/
    auth/ dashboard/ transactions/ categories/ budgets/ recurring/ reports/ settings/
  shared/widgets/           Componentes reutilizables
supabase/migrations/        SQL: tablas, RLS, triggers, storage
supabase/seed.sql           Datos de prueba para la nube
test/                       Unitarias (cálculos) + integración (repositorios/flujos con SQLite en memoria)
integration_test/           Flujo E2E en emulador/dispositivo
tool/patch_platforms.dart   Configura permisos/Android/iOS tras `flutter create`
.github/workflows/          CI que compila el APK
```

## 3. Modelo de datos

Todas las entidades tienen `created_at` y `updated_at` (y `deleted_at` para borrado lógico sincronizable).

| Entidad | Campos principales |
|---|---|
| **users** | id (= auth.users.id), email, display_name, currency (`PEN`), theme_mode, notifications_enabled, budget_alerts_enabled, recurring_reminders_enabled, biometric_enabled |
| **categories** | id, user_id, name, type (`income`/`expense`), color (ARGB), icon, is_default |
| **transactions** | id, user_id, type, **amount numeric(14,2) > 0**, category_id, date, description, payment_method, receipt_path, recurring_id |
| **budgets** | id, user_id, category_id, **limit_amount numeric(14,2)**, month, year, alert_80_sent, alert_100_sent · único por (usuario, categoría, mes, año) |
| **recurring_transactions** | id, user_id, type, amount, category_id, description, payment_method, **frequency**, start_date, **next_date**, end_date, **status** (`active`/`paused`/`finished`) |

Relaciones: `users 1─N categories 1─N transactions`, `categories 1─N budgets`, `recurring_transactions 1─N transactions`.

Métodos de pago: `cash`, `debit_card`, `credit_card`, `transfer`, `digital_wallet` (Yape/Plin), `other`.
Frecuencias: `daily`, `weekly`, `biweekly`, `monthly`, `yearly`.

## 4. Flujo de navegación

```
Splash ──► (sin sesión) Login ◄─► Registro
             │   └─► Recuperar contraseña
             ▼
   (sesión + biometría) Bloqueo biométrico
             ▼
┌──────────── Barra inferior ─────────────────────────────────────┐
│ Inicio │ Movimientos │ [ + Agregar ] │ Reportes │ Configuración │
└────────────────────────────────────────────────────────────────┘
 Inicio ─► Detalle/edición de movimiento
 Movimientos ─► Filtros · Editar · Eliminar (confirmación)
 Agregar ─► Formulario (tipo, monto, categoría, fecha, método, foto, recurrencia)
 Reportes ─► Filtros · Exportar CSV/PDF
 Configuración ─► Categorías ─► Formulario / Reasignar al eliminar
               ─► Presupuestos ─► Formulario
               ─► Recurrentes ─► Formulario
               ─► Moneda · Tema · Notificaciones · Biometría
               ─► Supabase/Sincronizar · Exportar/Importar/Eliminar datos · Cerrar sesión
```
