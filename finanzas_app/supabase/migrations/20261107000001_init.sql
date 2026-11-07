-- =====================================================================
-- Mis Finanzas · Migración inicial
-- Tablas, restricciones, triggers de auditoría, RLS y storage.
-- Dinero: numeric(14,2) (nunca float).
-- =====================================================================

create extension if not exists "pgcrypto";

-- ---------------------------------------------------------------------
-- Función genérica: updated_at siempre lo asigna el servidor
-- ---------------------------------------------------------------------
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  if tg_op = 'INSERT' and new.created_at is null then
    new.created_at := now();
  end if;
  return new;
end;
$$;

-- ---------------------------------------------------------------------
-- users: perfil y preferencias
-- ---------------------------------------------------------------------
create table if not exists public.users (
  id                          uuid primary key references auth.users (id) on delete cascade,
  email                       text not null,
  display_name                text,
  currency                    char(3) not null default 'PEN',
  theme_mode                  text not null default 'system'
                                check (theme_mode in ('light', 'dark', 'system')),
  notifications_enabled       boolean not null default true,
  budget_alerts_enabled       boolean not null default true,
  recurring_reminders_enabled boolean not null default true,
  biometric_enabled           boolean not null default false,
  created_at                  timestamptz not null default now(),
  updated_at                  timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- categories
-- ---------------------------------------------------------------------
create table if not exists public.categories (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references public.users (id) on delete cascade,
  name        text not null check (char_length(btrim(name)) between 1 and 40),
  type        text not null check (type in ('income', 'expense')),
  color       bigint not null,
  icon        text not null,
  is_default  boolean not null default false,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  deleted_at  timestamptz
);
create index if not exists categories_user_idx on public.categories (user_id, updated_at);

-- ---------------------------------------------------------------------
-- recurring_transactions
-- ---------------------------------------------------------------------
create table if not exists public.recurring_transactions (
  id                uuid primary key default gen_random_uuid(),
  user_id           uuid not null references public.users (id) on delete cascade,
  type              text not null check (type in ('income', 'expense')),
  amount            numeric(14, 2) not null check (amount > 0),
  category_id       uuid not null references public.categories (id),
  description       text check (description is null or char_length(description) <= 200),
  payment_method    text not null default 'cash'
                      check (payment_method in ('cash','debit_card','credit_card','transfer','digital_wallet','other')),
  frequency         text not null
                      check (frequency in ('daily','weekly','biweekly','monthly','yearly')),
  start_date        date not null,
  next_date         date not null,
  end_date          date,
  status            text not null default 'active'
                      check (status in ('active','paused','finished')),
  last_generated_at timestamptz,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  deleted_at        timestamptz,
  constraint recurring_dates_chk check (end_date is null or end_date >= start_date)
);
create index if not exists recurring_user_idx on public.recurring_transactions (user_id, updated_at);

-- ---------------------------------------------------------------------
-- transactions
-- ---------------------------------------------------------------------
create table if not exists public.transactions (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null references public.users (id) on delete cascade,
  type            text not null check (type in ('income', 'expense')),
  amount          numeric(14, 2) not null check (amount > 0),
  category_id     uuid not null references public.categories (id),
  date            date not null,
  description     text check (description is null or char_length(description) <= 200),
  payment_method  text not null default 'cash'
                    check (payment_method in ('cash','debit_card','credit_card','transfer','digital_wallet','other')),
  receipt_path    text,
  recurring_id    uuid references public.recurring_transactions (id) on delete set null,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  deleted_at      timestamptz
);
create index if not exists transactions_user_date_idx on public.transactions (user_id, date desc);
create index if not exists transactions_user_updated_idx on public.transactions (user_id, updated_at);
create index if not exists transactions_category_idx on public.transactions (category_id);

-- ---------------------------------------------------------------------
-- budgets
-- ---------------------------------------------------------------------
create table if not exists public.budgets (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null references public.users (id) on delete cascade,
  category_id     uuid not null references public.categories (id),
  limit_amount    numeric(14, 2) not null check (limit_amount > 0),
  month           smallint not null check (month between 1 and 12),
  year            smallint not null check (year between 2000 and 2100),
  alert_80_sent   boolean not null default false,
  alert_100_sent  boolean not null default false,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  deleted_at      timestamptz
);
create unique index if not exists budgets_unique_active
  on public.budgets (user_id, category_id, year, month)
  where deleted_at is null;
create index if not exists budgets_user_idx on public.budgets (user_id, updated_at);

-- ---------------------------------------------------------------------
-- Triggers de auditoría
-- ---------------------------------------------------------------------
do $$
declare t text;
begin
  foreach t in array array['users','categories','recurring_transactions','transactions','budgets'] loop
    execute format('drop trigger if exists trg_%1$s_updated_at on public.%1$s', t);
    execute format(
      'create trigger trg_%1$s_updated_at before insert or update on public.%1$s
         for each row execute function public.set_updated_at()', t);
  end loop;
end;
$$;

-- ---------------------------------------------------------------------
-- Categorías predeterminadas
-- ---------------------------------------------------------------------
create or replace function public.seed_default_categories(p_user uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.categories (user_id, name, type, color, icon, is_default) values
    (p_user, 'Salario',         'income',  4281236786, 'salary',        true),
    (p_user, 'Ventas',          'income',  4278225275, 'sales',         true),
    (p_user, 'Inversiones',     'income',  4279592384, 'investments',   true),
    (p_user, 'Bonificaciones',  'income',  4285143962, 'bonus',         true),
    (p_user, 'Otros',           'income',  4283723386, 'other_income',  true),
    (p_user, 'Alimentación',    'expense', 4293880832, 'food',          true),
    (p_user, 'Vivienda',        'expense', 4284301367, 'home',          true),
    (p_user, 'Transporte',      'expense', 4278351805, 'transport',     true),
    (p_user, 'Salud',           'expense', 4291176488, 'health',        true),
    (p_user, 'Educación',       'expense', 4280825235, 'education',     true),
    (p_user, 'Entretenimiento', 'expense', 4289533015, 'entertainment', true),
    (p_user, 'Servicios',       'expense', 4278223759, 'services',      true),
    (p_user, 'Deudas',          'expense', 4283315246, 'debts',         true),
    (p_user, 'Otros',           'expense', 4284572001, 'other_expense', true);
end;
$$;

-- Crea el perfil y las categorías al registrarse un usuario
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.users (id, email, display_name)
  values (new.id, new.email, new.raw_user_meta_data ->> 'display_name')
  on conflict (id) do nothing;
  perform public.seed_default_categories(new.id);
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- Elimina (lógicamente) todos los datos del usuario y restaura categorías
create or replace function public.delete_my_data()
returns void
language plpgsql
security invoker
set search_path = public
as $$
declare uid uuid := auth.uid();
begin
  if uid is null then
    raise exception 'No autenticado';
  end if;
  update public.budgets set deleted_at = now() where user_id = uid and deleted_at is null;
  update public.transactions set deleted_at = now() where user_id = uid and deleted_at is null;
  update public.recurring_transactions set deleted_at = now() where user_id = uid and deleted_at is null;
  update public.categories set deleted_at = now() where user_id = uid and deleted_at is null;
  perform public.seed_default_categories(uid);
end;
$$;

-- ---------------------------------------------------------------------
-- Row Level Security: cada usuario solo accede a sus registros
-- ---------------------------------------------------------------------
alter table public.users                  enable row level security;
alter table public.categories             enable row level security;
alter table public.recurring_transactions enable row level security;
alter table public.transactions           enable row level security;
alter table public.budgets                enable row level security;

create policy users_select_own on public.users for select to authenticated using (id = auth.uid());
create policy users_insert_own on public.users for insert to authenticated with check (id = auth.uid());
create policy users_update_own on public.users for update to authenticated using (id = auth.uid()) with check (id = auth.uid());

create policy categories_select_own on public.categories for select to authenticated using (user_id = auth.uid());
create policy categories_insert_own on public.categories for insert to authenticated with check (user_id = auth.uid());
create policy categories_update_own on public.categories for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy categories_delete_own on public.categories for delete to authenticated using (user_id = auth.uid());

-- La categoría referenciada también debe pertenecer al usuario
create or replace function public.owns_category(p_category uuid)
returns boolean
language sql
stable
security invoker
set search_path = public
as $$
  select exists (select 1 from public.categories c where c.id = p_category and c.user_id = auth.uid());
$$;

create policy recurring_select_own on public.recurring_transactions for select to authenticated using (user_id = auth.uid());
create policy recurring_insert_own on public.recurring_transactions for insert to authenticated
  with check (user_id = auth.uid() and public.owns_category(category_id));
create policy recurring_update_own on public.recurring_transactions for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid() and public.owns_category(category_id));
create policy recurring_delete_own on public.recurring_transactions for delete to authenticated using (user_id = auth.uid());

create policy transactions_select_own on public.transactions for select to authenticated using (user_id = auth.uid());
create policy transactions_insert_own on public.transactions for insert to authenticated
  with check (user_id = auth.uid() and public.owns_category(category_id));
create policy transactions_update_own on public.transactions for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid() and public.owns_category(category_id));
create policy transactions_delete_own on public.transactions for delete to authenticated using (user_id = auth.uid());

create policy budgets_select_own on public.budgets for select to authenticated using (user_id = auth.uid());
create policy budgets_insert_own on public.budgets for insert to authenticated
  with check (user_id = auth.uid() and public.owns_category(category_id));
create policy budgets_update_own on public.budgets for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid() and public.owns_category(category_id));
create policy budgets_delete_own on public.budgets for delete to authenticated using (user_id = auth.uid());

grant execute on function public.delete_my_data() to authenticated;

-- ---------------------------------------------------------------------
-- Storage: bucket privado de comprobantes  receipts/{user_id}/{tx_id}.jpg
-- ---------------------------------------------------------------------
insert into storage.buckets (id, name, public)
values ('receipts', 'receipts', false)
on conflict (id) do nothing;

create policy receipts_select_own on storage.objects for select to authenticated
  using (bucket_id = 'receipts' and (storage.foldername(name))[1] = auth.uid()::text);
create policy receipts_insert_own on storage.objects for insert to authenticated
  with check (bucket_id = 'receipts' and (storage.foldername(name))[1] = auth.uid()::text);
create policy receipts_update_own on storage.objects for update to authenticated
  using (bucket_id = 'receipts' and (storage.foldername(name))[1] = auth.uid()::text);
create policy receipts_delete_own on storage.objects for delete to authenticated
  using (bucket_id = 'receipts' and (storage.foldername(name))[1] = auth.uid()::text);
