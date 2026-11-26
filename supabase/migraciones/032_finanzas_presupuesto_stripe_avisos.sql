-- Bitácora Tiempo de Dios · migración 032: Finanzas (aviso de gastos, presupuesto, Stripe) y notificaciones al celular
-- 1) Cada solicitud de gasto nueva avisa por correo a las personas de Finanzas (función «crm», acción aviso_gasto).
-- 2) presupuestos: lo que se planea gastar cada mes (por concepto, categoría y área). Lo definen Finanzas, la PM
--    y el desarrollador; todos lo ven. Se compara contra ingresos y egresos del mes.
-- 3) Stripe: cada depósito (payout) queda como un ingreso de Finanzas con data.stripe_id; el índice evita duplicados.
-- 4) Notificaciones al celular: perfiles.notif ({una_hora, resumen}), push_suscripciones (un celular o navegador por fila)
--    y un cron cada 15 minutos que llama a la función «crm» (acción push).
-- Ejecútala una vez en Supabase → SQL Editor → Run. Se puede volver a correr sin error.

-- ============ 1) Aviso a Finanzas al pedir un gasto ============
create or replace function public.gasto_nuevo_aviso()
returns trigger language plpgsql security definer set search_path = public, extensions as $$
begin
  perform net.http_post(
    url := 'https://zhzqvetehynndfjbrzti.supabase.co/functions/v1/crm',
    headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InpoenF2ZXRlaHlubmRmamJyenRpIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTM3Mjc3NjgsImV4cCI6MjEwOTMwMzc2OH0.ZhsazISy5Azt7i14qFeHKjcSPNQzXJeeAGcPAoEzjqw'),
    body := jsonb_build_object('accion', 'aviso_gasto', 'id', new.id),
    timeout_milliseconds := 30000);
  return new;
exception when others then
  return new;  -- si el aviso falla, la solicitud igual se guarda
end $$;
drop trigger if exists gastos_aviso on public.gastos;
create trigger gastos_aviso after insert on public.gastos for each row execute function public.gasto_nuevo_aviso();

-- ============ 2) Presupuesto mensual ============
create table if not exists public.presupuestos (
  id uuid primary key default gen_random_uuid(),
  concepto text not null check (char_length(concepto) between 1 and 160),
  categoria text not null default 'Otro' check (char_length(categoria) <= 60),
  area text not null default 'general',
  monto numeric(12,2) not null check (monto >= 0),
  desde text not null check (desde ~ '^\d{4}-\d{2}$'),          -- primer mes en que aplica (YYYY-MM)
  hasta text check (hasta is null or hasta ~ '^\d{4}-\d{2}$'),  -- último mes; vacío = cada mes sin fin
  notas text not null default '' check (char_length(notas) <= 1000),
  creado timestamptz not null default now(),
  actualizado timestamptz not null default now(),
  actualizado_por uuid default auth.uid()
);
drop trigger if exists presupuestos_actualizado on public.presupuestos;
create trigger presupuestos_actualizado before update on public.presupuestos for each row execute function public.marcar_actualizado();
alter table public.presupuestos enable row level security;
drop policy if exists presupuestos_ver on public.presupuestos;
create policy presupuestos_ver on public.presupuestos for select to authenticated using (true);
drop policy if exists presupuestos_finanzas on public.presupuestos;
create policy presupuestos_finanzas on public.presupuestos for all to authenticated
  using (public.puede_finanzas() or public.es_pm()) with check (public.puede_finanzas() or public.es_pm());
do $$ begin alter publication supabase_realtime add table public.presupuestos; exception when duplicate_object then null; end $$;

-- ============ 3) Depósitos de Stripe sin duplicar ============
create unique index if not exists ingresos_stripe on public.ingresos ((data->>'stripe_id')) where data ? 'stripe_id';

-- ============ 4) Notificaciones al celular ============
alter table public.perfiles add column if not exists notif jsonb not null default '{}'::jsonb;
create table if not exists public.push_suscripciones (
  id uuid primary key default gen_random_uuid(),
  usuario uuid not null default auth.uid() references public.perfiles(id) on delete cascade,
  endpoint text not null unique,
  p256dh text not null,
  auth text not null,
  agente text not null default '' check (char_length(agente) <= 300),
  creado timestamptz not null default now()
);
alter table public.push_suscripciones enable row level security;
drop policy if exists push_mias on public.push_suscripciones;
create policy push_mias on public.push_suscripciones for all to authenticated
  using (usuario = auth.uid()) with check (usuario = auth.uid());

select cron.unschedule('bitacora-push') where exists (select 1 from cron.job where jobname = 'bitacora-push');
select cron.schedule(
  'bitacora-push',
  '*/15 * * * *',
  $$
  select net.http_post(
    url := 'https://zhzqvetehynndfjbrzti.supabase.co/functions/v1/crm',
    headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InpoenF2ZXRlaHlubmRmamJyenRpIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTM3Mjc3NjgsImV4cCI6MjEwOTMwMzc2OH0.ZhsazISy5Azt7i14qFeHKjcSPNQzXJeeAGcPAoEzjqw'),
    body := '{"accion":"push"}'::jsonb,
    timeout_milliseconds := 60000
  );
  $$
);

insert into public.migraciones_aplicadas (nombre) values ('032_finanzas_presupuesto_stripe_avisos') on conflict (nombre) do nothing;
