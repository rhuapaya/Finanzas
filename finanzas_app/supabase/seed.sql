-- =====================================================================
-- Datos de prueba para Supabase.
-- 1) Regístrate en la app con el correo indicado abajo.
-- 2) Ejecuta este script en el SQL Editor de Supabase.
-- Genera 6 meses de movimientos, presupuestos del mes actual y 2 recurrentes.
-- =====================================================================
do $$
declare
  v_email   text := 'demo@misfinanzas.app';   -- <-- cambia por tu correo
  v_uid     uuid;
  m         int;
  d         date;
  cat       record;
  c_salary  uuid; c_sales uuid; c_food uuid; c_home uuid; c_transport uuid;
  c_services uuid; c_fun uuid; c_health uuid; c_edu uuid;
  v_rec_salary uuid; v_rec_rent uuid;
begin
  select id into v_uid from auth.users where email = v_email;
  if v_uid is null then
    raise exception 'No existe el usuario %, regístrate primero en la app', v_email;
  end if;

  select id into c_salary    from public.categories where user_id = v_uid and icon = 'salary'        and deleted_at is null limit 1;
  select id into c_sales     from public.categories where user_id = v_uid and icon = 'sales'         and deleted_at is null limit 1;
  select id into c_food      from public.categories where user_id = v_uid and icon = 'food'          and deleted_at is null limit 1;
  select id into c_home      from public.categories where user_id = v_uid and icon = 'home'          and deleted_at is null limit 1;
  select id into c_transport from public.categories where user_id = v_uid and icon = 'transport'     and deleted_at is null limit 1;
  select id into c_services  from public.categories where user_id = v_uid and icon = 'services'      and deleted_at is null limit 1;
  select id into c_fun       from public.categories where user_id = v_uid and icon = 'entertainment' and deleted_at is null limit 1;
  select id into c_health    from public.categories where user_id = v_uid and icon = 'health'        and deleted_at is null limit 1;
  select id into c_edu       from public.categories where user_id = v_uid and icon = 'education'     and deleted_at is null limit 1;

  insert into public.recurring_transactions
    (user_id, type, amount, category_id, description, payment_method, frequency, start_date, next_date, status)
  values
    (v_uid, 'income', 4500.00, c_salary, 'Sueldo mensual', 'transfer', 'monthly',
       (date_trunc('month', current_date) - interval '5 months')::date,
       (date_trunc('month', current_date) + interval '1 month')::date, 'active')
  returning id into v_rec_salary;

  insert into public.recurring_transactions
    (user_id, type, amount, category_id, description, payment_method, frequency, start_date, next_date, status)
  values
    (v_uid, 'expense', 1200.00, c_home, 'Alquiler departamento', 'transfer', 'monthly',
       (date_trunc('month', current_date) - interval '5 months' + interval '4 days')::date,
       (date_trunc('month', current_date) + interval '1 month' + interval '4 days')::date, 'active')
  returning id into v_rec_rent;

  for m in 0..5 loop
    d := (date_trunc('month', current_date) - make_interval(months => m))::date;

    insert into public.transactions (user_id, type, amount, category_id, date, description, payment_method, recurring_id) values
      (v_uid, 'income',  4500.00, c_salary,    d,                   'Sueldo mensual',        'transfer',       v_rec_salary),
      (v_uid, 'income',   350.00 + m * 40, c_sales, d + 14,         'Venta de artículos',    'digital_wallet', null),
      (v_uid, 'expense', 1200.00, c_home,      d + 4,               'Alquiler departamento', 'transfer',       v_rec_rent),
      (v_uid, 'expense',  185.50, c_services,  d + 9,               'Luz, agua e Internet',  'debit_card',     null),
      (v_uid, 'expense',  210.40 + m * 7, c_food, d + 2,            'Supermercado',          'debit_card',     null),
      (v_uid, 'expense',  176.90, c_food,      d + 16,              'Mercado',               'cash',           null),
      (v_uid, 'expense',   95.00, c_transport, d + 6,               'Recarga de transporte', 'digital_wallet', null),
      (v_uid, 'expense',   64.00, c_fun,       d + 20,              'Cine y cena',           'credit_card',    null),
      (v_uid, 'expense',  300.00, c_edu,       d + 11,              'Curso en línea',        'credit_card',    null);

    if m % 2 = 0 then
      insert into public.transactions (user_id, type, amount, category_id, date, description, payment_method)
      values (v_uid, 'expense', 120.00, c_health, d + 18, 'Consulta médica', 'cash');
    end if;
  end loop;

  -- Evita fechas futuras en el mes actual
  update public.transactions set date = current_date
   where user_id = v_uid and date > current_date and deleted_at is null;

  insert into public.budgets (user_id, category_id, limit_amount, month, year) values
    (v_uid, c_food,      500.00, extract(month from current_date)::smallint, extract(year from current_date)::smallint),
    (v_uid, c_transport, 120.00, extract(month from current_date)::smallint, extract(year from current_date)::smallint),
    (v_uid, c_fun,       150.00, extract(month from current_date)::smallint, extract(year from current_date)::smallint)
  on conflict do nothing;
end;
$$;
