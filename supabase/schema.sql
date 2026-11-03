-- Bitácora Tiempo de Dios · esquema de base de datos (Supabase / Postgres)
-- Ejecútalo completo en Supabase → SQL Editor → New query → Run.

-- ============ Perfiles y roles ============
-- rol: 'pm' (project manager, ve y edita todo), 'lider' (encargado de un área), 'colaborador'
-- area: 'formacion' | 'musica' | 'audiovisual' (null para la PM)
create table if not exists public.perfiles (
  id uuid primary key references auth.users(id) on delete cascade,
  nombre text not null,
  rol text not null default 'colaborador' check (rol in ('pm','lider','colaborador')),
  area text check (area in ('formacion','musica','audiovisual')),
  creado timestamptz not null default now()
);

-- Crea el perfil automáticamente cuando invitas a alguien
create or replace function public.crear_perfil()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.perfiles (id, nombre)
  values (new.id, coalesce(new.raw_user_meta_data->>'nombre', split_part(new.email, '@', 1)))
  on conflict (id) do nothing;
  return new;
end $$;

drop trigger if exists al_crear_usuario on auth.users;
create trigger al_crear_usuario after insert on auth.users
for each row execute function public.crear_perfil();

-- Funciones auxiliares para las reglas
create or replace function public.es_pm()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.perfiles where id = auth.uid() and rol = 'pm');
$$;

create or replace function public.mi_area()
returns text language sql stable security definer set search_path = public as $$
  select area from public.perfiles where id = auth.uid();
$$;

-- ============ Tareas y logros ============
-- Cada registro guarda su contenido en "data" (jsonb), igual que el prototipo.
-- "area" se repite como columna para poder aplicar permisos por área.
create table if not exists public.tareas (
  id text primary key,
  area text not null default 'formacion' check (area in ('formacion','musica','audiovisual')),
  data jsonb not null,
  actualizado timestamptz not null default now(),
  actualizado_por uuid default auth.uid()
);

create table if not exists public.logros (
  id text primary key,
  area text not null default 'formacion' check (area in ('formacion','musica','audiovisual')),
  data jsonb not null,
  actualizado timestamptz not null default now(),
  actualizado_por uuid default auth.uid()
);

create or replace function public.marcar_actualizado()
returns trigger language plpgsql as $$
begin new.actualizado = now(); new.actualizado_por = auth.uid(); return new; end $$;

drop trigger if exists tareas_actualizado on public.tareas;
create trigger tareas_actualizado before update on public.tareas for each row execute function public.marcar_actualizado();
drop trigger if exists logros_actualizado on public.logros;
create trigger logros_actualizado before update on public.logros for each row execute function public.marcar_actualizado();

-- ============ Permisos (Row Level Security) ============
alter table public.perfiles enable row level security;
alter table public.tareas enable row level security;
alter table public.logros enable row level security;

-- Perfiles: cualquiera con sesión los ve (para elegir responsables); solo la PM los edita
drop policy if exists perfiles_leer on public.perfiles;
create policy perfiles_leer on public.perfiles for select to authenticated using (true);
drop policy if exists perfiles_pm on public.perfiles;
create policy perfiles_pm on public.perfiles for update to authenticated using (public.es_pm()) with check (public.es_pm());

-- Tareas y logros: todos con sesión leen; escriben la PM y el equipo del área
drop policy if exists tareas_leer on public.tareas;
create policy tareas_leer on public.tareas for select to authenticated using (true);
drop policy if exists tareas_escribir on public.tareas;
create policy tareas_escribir on public.tareas for all to authenticated
  using (public.es_pm() or area = public.mi_area())
  with check (public.es_pm() or area = public.mi_area());

drop policy if exists logros_leer on public.logros;
create policy logros_leer on public.logros for select to authenticated using (true);
drop policy if exists logros_escribir on public.logros;
create policy logros_escribir on public.logros for all to authenticated
  using (public.es_pm() or area = public.mi_area())
  with check (public.es_pm() or area = public.mi_area());

-- ============ Tiempo real ============
-- Para que los cambios aparezcan en vivo en todas las pantallas
alter publication supabase_realtime add table public.tareas;
alter publication supabase_realtime add table public.logros;

-- ============ Después de invitar a cada persona ============
-- Asigna su rol y área (cambia el correo):
-- update public.perfiles set nombre = 'Nombre de la PM', rol = 'pm', area = null
--   where id = (select id from auth.users where email = 'pm@tiempodedios.mx');
-- update public.perfiles set nombre = 'Ceci', rol = 'lider', area = 'formacion'
--   where id = (select id from auth.users where email = 'ceciliagomez@tiempodedios.mx');
-- update public.perfiles set nombre = 'Nombre', rol = 'colaborador', area = 'musica'
--   where id = (select id from auth.users where email = 'persona@tiempodedios.mx');
