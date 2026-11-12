-- Bitácora Tiempo de Dios · migración 017: Finanzas (solicitudes de gasto e ingresos)
-- - Cualquier persona del equipo pide un gasto; puede editarlo o cancelarlo mientras está pendiente.
-- - Todo el equipo puede ver las solicitudes y los movimientos.
-- - Solo quien es de Finanzas (perfiles.finanzas, se marca en Equipo) y el desarrollador
--   aprueban, rechazan, marcan "pago realizado" y registran ingresos.
-- - Los gastos pagados y los ingresos forman el registro mensual de ingresos y egresos.
-- - Además: el equipo de Música puede subir los documentos de registro de cada canción (INDAUTOR, splitsheet).
-- Ejecútala una vez en Supabase → SQL Editor → New query → Run. Se puede volver a correr sin error.

-- ============ Quién es de Finanzas ============
alter table public.perfiles add column if not exists finanzas boolean not null default false;

create or replace function public.puede_finanzas()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.perfiles where id = auth.uid() and (finanzas or rol = 'desarrollador'));
$$;

-- Solo la PM o el desarrollador marcan quién es de Finanzas (además de rol y áreas)
create or replace function public.proteger_rol()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is not null and not public.es_pm()
     and (new.rol is distinct from old.rol or new.area is distinct from old.area
          or new.areas is distinct from old.areas or new.finanzas is distinct from old.finanzas) then
    raise exception 'Solo la project manager puede cambiar rol, área o finanzas';
  end if;
  if auth.uid() is not null and auth.uid() <> old.id
     and (new.nombre is distinct from old.nombre or new.usuario is distinct from old.usuario
          or new.foto is distinct from old.foto or new.bio is distinct from old.bio
          or new.portada is distinct from old.portada) then
    raise exception 'Solo puedes editar tu propio perfil';
  end if;
  return new;
end $$;

-- ============ Solicitudes de gasto ============
create table if not exists public.gastos (
  id uuid primary key default gen_random_uuid(),
  creado timestamptz not null default now(),
  solicitante uuid default auth.uid() references public.perfiles(id) on delete set null,
  estado text not null default 'pendiente'
    check (estado in ('pendiente','aprobada','rechazada','pagada','cancelada')),
  concepto text not null check (char_length(concepto) between 1 and 200),
  monto numeric(12,2) not null check (monto > 0),
  area text,
  categoria text,
  fecha_requerida date,
  fecha_pago date,
  data jsonb not null default '{}'::jsonb check (pg_column_size(data) < 50000),  -- beneficiario, método, cuenta, notas, archivos, pago…
  actualizado timestamptz not null default now(),
  actualizado_por uuid
);
create index if not exists gastos_creado on public.gastos (creado desc);
create index if not exists gastos_pago on public.gastos (fecha_pago);

drop trigger if exists gastos_actualizado on public.gastos;
create trigger gastos_actualizado before update on public.gastos
for each row execute function public.marcar_actualizado();

-- Al crear: la fecha la pone la base y quien la pide es quien inició sesión
create or replace function public.gasto_nuevo()
returns trigger language plpgsql as $$
begin
  new.creado = now(); new.actualizado = now(); new.actualizado_por = auth.uid();
  if not public.puede_finanzas() then new.solicitante = auth.uid(); end if;
  return new;
end $$;
drop trigger if exists gastos_nuevo on public.gastos;
create trigger gastos_nuevo before insert on public.gastos
for each row execute function public.gasto_nuevo();

alter table public.gastos enable row level security;
drop policy if exists gastos_ver on public.gastos;
create policy gastos_ver on public.gastos for select to authenticated using (true);
drop policy if exists gastos_pedir on public.gastos;
create policy gastos_pedir on public.gastos for insert to authenticated
  with check (public.puede_finanzas() or (solicitante = auth.uid() and estado = 'pendiente' and fecha_pago is null));
-- Quien la pidió la edita o cancela mientras está pendiente
drop policy if exists gastos_mia on public.gastos;
create policy gastos_mia on public.gastos for update to authenticated
  using (solicitante = auth.uid() and estado = 'pendiente')
  with check (solicitante = auth.uid() and estado in ('pendiente','cancelada') and fecha_pago is null);
-- Finanzas y el desarrollador hacen todo
drop policy if exists gastos_finanzas on public.gastos;
create policy gastos_finanzas on public.gastos for all to authenticated
  using (public.puede_finanzas()) with check (public.puede_finanzas());

-- ============ Ingresos ============
create table if not exists public.ingresos (
  id uuid primary key default gen_random_uuid(),
  creado timestamptz not null default now(),
  fecha date not null,
  concepto text not null check (char_length(concepto) between 1 and 200),
  monto numeric(12,2) not null check (monto > 0),
  area text,
  categoria text,
  data jsonb not null default '{}'::jsonb check (pg_column_size(data) < 50000),  -- fuente, referencia, notas, archivos
  registrado_por uuid default auth.uid(),
  actualizado timestamptz not null default now(),
  actualizado_por uuid
);
create index if not exists ingresos_fecha on public.ingresos (fecha);
drop trigger if exists ingresos_actualizado on public.ingresos;
create trigger ingresos_actualizado before update on public.ingresos
for each row execute function public.marcar_actualizado();

alter table public.ingresos enable row level security;
drop policy if exists ingresos_ver on public.ingresos;
create policy ingresos_ver on public.ingresos for select to authenticated using (true);
drop policy if exists ingresos_finanzas on public.ingresos;
create policy ingresos_finanzas on public.ingresos for all to authenticated
  using (public.puede_finanzas()) with check (public.puede_finanzas());

-- ============ Comprobantes (Storage) ============
-- Carpeta privada: cotizaciones, facturas y comprobantes de pago. Hasta 25 MB por archivo.
insert into storage.buckets (id, name, public, file_size_limit)
values ('finanzas', 'finanzas', false, 26214400)
on conflict (id) do update set public = false, file_size_limit = excluded.file_size_limit;

drop policy if exists finanzas_leer on storage.objects;
create policy finanzas_leer on storage.objects for select to authenticated
  using (bucket_id = 'finanzas');
-- Cada quien sube en su carpeta (finanzas/<su id>/…); Finanzas sube en cualquiera
drop policy if exists finanzas_subir on storage.objects;
create policy finanzas_subir on storage.objects for insert to authenticated
  with check (bucket_id = 'finanzas' and ((storage.foldername(name))[1] = auth.uid()::text or public.puede_finanzas()));
drop policy if exists finanzas_borrar on storage.objects;
create policy finanzas_borrar on storage.objects for delete to authenticated
  using (bucket_id = 'finanzas' and ((storage.foldername(name))[1] = auth.uid()::text or public.puede_finanzas()));

-- ============ Tiempo real ============
do $$ begin alter publication supabase_realtime add table public.gastos;
exception when duplicate_object then null; end $$;
do $$ begin alter publication supabase_realtime add table public.ingresos;
exception when duplicate_object then null; end $$;

-- ============ Canciones: documentos que sube el equipo de Música ============
-- Los pasos 12 (registro INDAUTOR/SACM) y 13 (splitsheet firmado) piden subir el documento para completarse.
-- El equipo de Música sube en canciones/equipo/<canción>/…
drop policy if exists canciones_equipo_subir on storage.objects;
create policy canciones_equipo_subir on storage.objects for insert to authenticated
  with check (bucket_id = 'canciones' and (storage.foldername(name))[1] = 'equipo' and public.puede_area('musica'));
