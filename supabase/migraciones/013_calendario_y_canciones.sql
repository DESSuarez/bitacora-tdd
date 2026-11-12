-- Bitácora Tiempo de Dios · migración 013: calendario interno y canciones por producir
-- 1. "eventos": calendario del Dashboard (fechas únicas, de varios días o repetidas). Todo el equipo agenda.
-- 2. "ligas_artistas": una liga privada por artista para registrar canciones (se puede desactivar).
-- 3. "canciones": lo que registran los artistas, con su etapa, checklist y semana de producción.
--    Solo Música y la PM las ven y las trabajan.
-- 4. Al registrarse una canción se crea sola una tarea en Música para Ariel (con subtareas para Memo)
--    para aprobarla y agendar la semana de producción con el ministerio.
-- Ejecútala una vez en Supabase → SQL Editor → New query → Run. Se puede volver a correr sin error.

-- ============ 1. Calendario ============
create table if not exists public.eventos (
  id text primary key,
  area text not null default 'general',
  data jsonb not null check (pg_column_size(data) < 50000),
  actualizado timestamptz not null default now(),
  actualizado_por uuid default auth.uid()
);
drop trigger if exists eventos_actualizado on public.eventos;
create trigger eventos_actualizado before update on public.eventos
for each row execute function public.marcar_actualizado();

alter table public.eventos enable row level security;
drop policy if exists eventos_equipo on public.eventos;
create policy eventos_equipo on public.eventos for all to authenticated using (true) with check (true);

-- ============ 2. Ligas por artista ============
create table if not exists public.ligas_artistas (
  id uuid primary key default gen_random_uuid(),
  nombre text not null check (char_length(nombre) between 1 and 120),
  activa boolean not null default true,
  creado timestamptz not null default now(),
  creado_por uuid default auth.uid()
);
alter table public.ligas_artistas enable row level security;
drop policy if exists ligas_musica on public.ligas_artistas;
create policy ligas_musica on public.ligas_artistas for all to authenticated
  using (public.puede_area('musica')) with check (public.puede_area('musica'));

-- El formulario pregunta si su liga sigue activa (y el nombre del artista) sin poder leer la tabla
create or replace function public.liga_valida(l text)
returns boolean language plpgsql stable security definer set search_path = public as $$
begin
  return exists (select 1 from public.ligas_artistas where id = l::uuid and activa);
exception when others then return false;
end $$;

create or replace function public.liga_artista(l text)
returns text language plpgsql stable security definer set search_path = public as $$
begin
  return (select nombre from public.ligas_artistas where id = l::uuid and activa);
exception when others then return null;
end $$;

grant execute on function public.liga_valida(text) to anon, authenticated;
grant execute on function public.liga_artista(text) to anon, authenticated;

-- ============ 3. Canciones ============
create table if not exists public.canciones (
  id uuid primary key,
  liga uuid references public.ligas_artistas(id) on delete set null,
  creado timestamptz not null default now(),
  etapa text not null default 'intake'
    check (etapa in ('intake','preproduccion','agendada','produccion','registro','marketing','completado','bloqueado')),
  data jsonb not null check (pg_column_size(data) < 200000),     -- respuestas del formulario
  archivos jsonb not null default '[]'::jsonb,                   -- [{nombre, ruta, tamano, tipo, campo}]
  checklist jsonb not null default '{}'::jsonb,                  -- {"1": "2026-11-12T…", …}
  semana date,                                                   -- lunes de su semana de producción
  notas text not null default '',
  actualizado timestamptz not null default now(),
  actualizado_por uuid
);
alter table public.canciones drop constraint if exists canciones_archivos_check;
alter table public.canciones add constraint canciones_archivos_check
  check (jsonb_typeof(archivos) = 'array' and jsonb_array_length(archivos) <= 20);
create index if not exists canciones_creado on public.canciones (creado desc);

drop trigger if exists canciones_actualizado on public.canciones;
create trigger canciones_actualizado before update on public.canciones
for each row execute function public.marcar_actualizado();

-- Persona del equipo por usuario o por nombre (para asignar la tarea automática)
create or replace function public.persona_equipo(n text)
returns public.perfiles language sql stable security definer set search_path = public as $$
  select * from public.perfiles
  where lower(usuario) = lower(n) or nombre ilike n || '%'
  order by (lower(usuario) = lower(n)) desc limit 1;
$$;

-- Al registrar: la fecha la pone la base, los archivos deben estar en su carpeta
-- y se crea la tarea "Agendar producción" en Música.
create or replace function public.cancion_nueva()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  ariel public.perfiles; memo public.perfiles;
  titulo text := coalesce(nullif(new.data->>'titulo',''), 'Canción sin título');
  artista text := coalesce(nullif(new.data->>'nombreArtistico',''), nullif(new.data->>'nombre',''),
                           (select nombre from public.ligas_artistas where id = new.liga), 'Artista');
  lunes date := date_trunc('week', (now() at time zone 'America/Mexico_City'))::date;
  orden numeric;
  sub jsonb;
begin
  new.creado = now(); new.actualizado = now(); new.actualizado_por = auth.uid();
  if exists (select 1 from jsonb_array_elements(new.archivos) a
             where coalesce(a->>'ruta','') not like coalesce(new.liga::text,'-') || '/' || new.id::text || '/%') then
    raise exception 'Cada archivo debe estar en la carpeta de su canción';
  end if;

  ariel := public.persona_equipo('ariel');
  memo := public.persona_equipo('memo');
  select coalesce(max((data->>'orden')::numeric), 0) + 1 into orden
    from public.tareas where area = 'musica' and data->>'semana' = lunes::text;
  sub := jsonb_build_array(
    jsonb_build_object('id', 'c1', 'titulo', 'Revisar y aprobar la canción (intake)',
      'responsable', coalesce(memo.nombre, 'Memo'), 'responsable_id', memo.id, 'hecha', null),
    jsonb_build_object('id', 'c2', 'titulo', 'Agendar la semana de producción con el ministerio',
      'responsable', coalesce(ariel.nombre, 'Ariel'), 'responsable_id', ariel.id, 'hecha', null),
    jsonb_build_object('id', 'c3', 'titulo', 'Confirmar la semana con Memo, Diego y el artista',
      'responsable', coalesce(memo.nombre, 'Memo'), 'responsable_id', memo.id, 'hecha', null));

  insert into public.tareas (id, area, data) values ('cancion-' || new.id::text, 'musica', jsonb_build_object(
    'area', 'musica',
    'titulo', 'Agendar producción: «' || titulo || '» · ' || artista,
    'proyecto', 'Canciones',
    'responsable', coalesce(ariel.nombre, 'Ariel'), 'responsable_id', ariel.id,
    'semana', lunes::text,
    'creada', to_char(now() at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
    'creada_por', null, 'hecha', null, 'orden', orden,
    'nota', 'Canción registrada por ' || artista || ' desde su liga. Revísala en Música → Canciones y agenda su semana de producción.',
    'cancion_id', new.id,
    'subtareas', sub))
  on conflict (id) do nothing;
  return new;
end $$;

drop trigger if exists canciones_nueva on public.canciones;
create trigger canciones_nueva before insert on public.canciones
for each row execute function public.cancion_nueva();

alter table public.canciones enable row level security;

-- Registrar: solo con una liga activa, y como canción nueva
drop policy if exists canciones_registrar on public.canciones;
create policy canciones_registrar on public.canciones for insert to anon, authenticated
  with check (public.liga_valida(liga::text) and etapa = 'intake' and notas = ''
              and checklist = '{}'::jsonb and semana is null);

-- Ver y trabajar: Música y la PM
drop policy if exists canciones_musica on public.canciones;
create policy canciones_musica on public.canciones for all to authenticated
  using (public.puede_area('musica')) with check (public.puede_area('musica'));

-- ============ Archivos de canciones (Storage) ============
-- Carpeta privada: demos, notas de voz, letras, partituras. Hasta 50 MB por archivo.
insert into storage.buckets (id, name, public, file_size_limit)
values ('canciones', 'canciones', false, 52428800)
on conflict (id) do update set public = false, file_size_limit = excluded.file_size_limit;

-- Subir: solo con una liga activa, dentro de <liga>/<canción>/
drop policy if exists canciones_subir on storage.objects;
create policy canciones_subir on storage.objects for insert to anon, authenticated
  with check (bucket_id = 'canciones'
    and public.liga_valida((storage.foldername(name))[1])
    and (storage.foldername(name))[2] ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$');

drop policy if exists canciones_leer on storage.objects;
create policy canciones_leer on storage.objects for select to authenticated
  using (bucket_id = 'canciones' and public.puede_area('musica'));

drop policy if exists canciones_borrar on storage.objects;
create policy canciones_borrar on storage.objects for delete to authenticated
  using (bucket_id = 'canciones' and public.puede_area('musica'));

-- ============ Tiempo real ============
do $$ begin alter publication supabase_realtime add table public.eventos;
exception when duplicate_object then null; end $$;
do $$ begin alter publication supabase_realtime add table public.canciones;
exception when duplicate_object then null; end $$;
do $$ begin alter publication supabase_realtime add table public.ligas_artistas;
exception when duplicate_object then null; end $$;
