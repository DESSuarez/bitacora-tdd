-- Bitácora Tiempo de Dios · migración 019: activos (Finanzas → Activos)
-- Todo lo que tiene Tiempo de Dios hoy: bancos y efectivo, equipo, instrumentos, vehículos, inventario,
-- cuentas por cobrar, inversiones… con su valor, a cargo de quién y dónde está.
-- Todo el equipo lo ve; solo Finanzas y el desarrollador lo registran y editan (puede_finanzas()).
-- Ejecútala una vez en Supabase → SQL Editor → New query → Run. Se puede volver a correr sin error.

create table if not exists public.activos (
  id uuid primary key default gen_random_uuid(),
  creado timestamptz not null default now(),
  tipo text not null default 'otro'
    check (tipo in ('banco','efectivo','inversion','por_cobrar','equipo','instrumento','vehiculo','inmueble','inventario','otro')),
  nombre text not null check (char_length(nombre) between 1 and 160),
  valor numeric(14,2) not null default 0 check (valor >= 0),
  cantidad int not null default 1 check (cantidad >= 1),
  area text,
  responsable text,
  ubicacion text,
  fecha_valor date not null default current_date,   -- a qué fecha corresponde el valor o saldo
  data jsonb not null default '{}'::jsonb check (pg_column_size(data) < 50000),  -- notas, marca/modelo, serie, estado, cuenta…
  actualizado timestamptz not null default now(),
  actualizado_por uuid
);
create index if not exists activos_tipo on public.activos (tipo);
drop trigger if exists activos_actualizado on public.activos;
create trigger activos_actualizado before update on public.activos
for each row execute function public.marcar_actualizado();

alter table public.activos enable row level security;
drop policy if exists activos_ver on public.activos;
create policy activos_ver on public.activos for select to authenticated using (true);
drop policy if exists activos_finanzas on public.activos;
create policy activos_finanzas on public.activos for all to authenticated
  using (public.puede_finanzas()) with check (public.puede_finanzas());

do $$ begin alter publication supabase_realtime add table public.activos;
exception when duplicate_object then null; end $$;
