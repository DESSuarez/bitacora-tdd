-- Bitácora Tiempo de Dios · esquema de base de datos (Supabase / Postgres)
-- Ejecútalo completo en Supabase → SQL Editor → New query → Run.

-- ============ Perfiles y roles ============
-- rol: 'pm' (project manager, ve y edita todo), 'desarrollador' (mismo acceso que la PM),
--      'lider' (encargado de un área), 'colaborador'
-- area: 'formacion' | 'musica' | 'audiovisual' | 'operativo' (null para la PM); areas: áreas adicionales
create table if not exists public.perfiles (
  id uuid primary key references auth.users(id) on delete cascade,
  nombre text not null,
  rol text not null default 'colaborador' constraint perfiles_rol_check check (rol in ('pm','desarrollador','lider','colaborador')),
  area text check (area in ('formacion','musica','audiovisual','operativo')),
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
  select exists (select 1 from public.perfiles where id = auth.uid() and rol in ('pm','desarrollador'));
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
  area text not null default 'formacion' check (area in ('formacion','musica','audiovisual','operativo')),
  data jsonb not null,
  actualizado timestamptz not null default now(),
  actualizado_por uuid default auth.uid()
);

create table if not exists public.logros (
  id text primary key,
  area text not null default 'formacion' check (area in ('formacion','musica','audiovisual','operativo')),
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
-- (con "if not exists" para poder volver a correr este archivo sin error)
do $$
begin
  if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and tablename = 'tareas') then
    alter publication supabase_realtime add table public.tareas;
  end if;
  if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and tablename = 'logros') then
    alter publication supabase_realtime add table public.logros;
  end if;
end $$;

-- ============ Perfil con fotografía ============
-- Foto de perfil (URL pública en Storage)
alter table public.perfiles add column if not exists foto text;

-- Cada quien puede editar su propio nombre y foto
drop policy if exists perfiles_yo on public.perfiles;
create policy perfiles_yo on public.perfiles for update to authenticated
  using (id = auth.uid()) with check (id = auth.uid());

-- ...pero solo la PM cambia rol y área.
-- (auth.uid() es null en SQL Editor y en la Edge Function, que sí pueden.)
create or replace function public.proteger_rol()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is not null and not public.es_pm()
     and (new.rol is distinct from old.rol or new.area is distinct from old.area) then
    raise exception 'Solo la project manager puede cambiar rol o área';
  end if;
  return new;
end $$;

drop trigger if exists proteger_rol on public.perfiles;
create trigger proteger_rol before update on public.perfiles
for each row execute function public.proteger_rol();

-- Bucket público para las fotos: cada persona sube solo a su carpeta (fotos/<su id>/...)
insert into storage.buckets (id, name, public)
values ('fotos', 'fotos', true)
on conflict (id) do update set public = true;

drop policy if exists fotos_leer on storage.objects;
create policy fotos_leer on storage.objects for select to authenticated
  using (bucket_id = 'fotos');

drop policy if exists fotos_subir on storage.objects;
create policy fotos_subir on storage.objects for insert to authenticated
  with check (bucket_id = 'fotos' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists fotos_cambiar on storage.objects;
create policy fotos_cambiar on storage.objects for update to authenticated
  using (bucket_id = 'fotos' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists fotos_borrar on storage.objects;
create policy fotos_borrar on storage.objects for delete to authenticated
  using (bucket_id = 'fotos' and (storage.foldername(name))[1] = auth.uid()::text);

-- ============ Entregables (archivos en tareas) ============

insert into storage.buckets (id, name, public, file_size_limit)
values ('entregables', 'entregables', false, 26214400)
on conflict (id) do update set public = false, file_size_limit = 26214400;

drop policy if exists entregables_leer on storage.objects;
create policy entregables_leer on storage.objects for select to authenticated
  using (bucket_id = 'entregables');

drop policy if exists entregables_subir on storage.objects;
create policy entregables_subir on storage.objects for insert to authenticated
  with check (bucket_id = 'entregables' and ((storage.foldername(name))[1] = public.mi_area() or public.es_pm()));

drop policy if exists entregables_borrar on storage.objects;
create policy entregables_borrar on storage.objects for delete to authenticated
  using (bucket_id = 'entregables' and ((storage.foldername(name))[1] = public.mi_area() or public.es_pm()));

-- ============ Nombre de usuario ============
alter table public.perfiles add column if not exists usuario text;

-- Propone un usuario libre a partir de un texto (normalmente lo que va antes de la @ del correo)
create or replace function public.usuario_libre(base text)
returns text language plpgsql security definer set search_path = public as $$
declare
  u text := left(lower(regexp_replace(coalesce(base, ''), '[^a-zA-Z0-9._]', '', 'g')), 26);
  r text;
  i int := 1;
begin
  if length(u) < 2 then u := 'usuario'; end if;
  r := u;
  while exists (select 1 from public.perfiles where lower(usuario) = r) loop
    i := i + 1;
    r := u || i;
  end loop;
  return r;
end $$;

-- Rellena a quien todavía no tenga usuario
do $$
declare x record;
begin
  for x in select p.id, u.email from public.perfiles p join auth.users u on u.id = p.id
           where p.usuario is null order by p.creado loop
    update public.perfiles set usuario = public.usuario_libre(split_part(x.email, '@', 1)) where id = x.id;
  end loop;
end $$;

-- Único (sin importar mayúsculas) y con formato simple
create unique index if not exists perfiles_usuario_unico on public.perfiles (lower(usuario));
alter table public.perfiles drop constraint if exists perfiles_usuario_formato;
alter table public.perfiles add constraint perfiles_usuario_formato
  check (usuario is null or usuario ~ '^[a-z0-9._]{2,30}$');

-- Las personas nuevas reciben su usuario al ser invitadas
create or replace function public.crear_perfil()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.perfiles (id, nombre, usuario)
  values (new.id,
          coalesce(new.raw_user_meta_data->>'nombre', split_part(new.email, '@', 1)),
          public.usuario_libre(coalesce(new.raw_user_meta_data->>'usuario', split_part(new.email, '@', 1))))
  on conflict (id) do nothing;
  return new;
end $$;

-- ============ Después de invitar a cada persona ============
-- Asigna su rol y área (cambia el correo):
-- update public.perfiles set nombre = 'Nombre de la PM', rol = 'pm', area = null
--   where id = (select id from auth.users where email = 'pm@tiempodedios.mx');
-- update public.perfiles set nombre = 'Ceci', rol = 'lider', area = 'formacion'
--   where id = (select id from auth.users where email = 'ceciliagomez@tiempodedios.mx');
-- update public.perfiles set nombre = 'Nombre', rol = 'colaborador', area = 'musica'
--   where id = (select id from auth.users where email = 'persona@tiempodedios.mx');

-- ============ Varias áreas por persona (migración 007) ============
alter table public.perfiles add column if not exists areas text[] not null default '{}';
alter table public.perfiles drop constraint if exists perfiles_areas_check;
alter table public.perfiles add constraint perfiles_areas_check
  check (areas <@ array['formacion','musica','audiovisual','operativo']::text[]);

-- ¿Puede la persona con sesión escribir en esta área? (PM / desarrollador, su área o una adicional)
create or replace function public.puede_area(a text)
returns boolean language sql stable security definer set search_path = public as $$
  select public.es_pm() or exists (
    select 1 from public.perfiles where id = auth.uid() and (area = a or a = any(areas)));
$$;

drop policy if exists tareas_escribir on public.tareas;
create policy tareas_escribir on public.tareas for all to authenticated
  using (public.puede_area(area)) with check (public.puede_area(area));
drop policy if exists logros_escribir on public.logros;
create policy logros_escribir on public.logros for all to authenticated
  using (public.puede_area(area)) with check (public.puede_area(area));

drop policy if exists entregables_subir on storage.objects;
create policy entregables_subir on storage.objects for insert to authenticated
  with check (bucket_id = 'entregables' and public.puede_area((storage.foldername(name))[1]));
drop policy if exists entregables_borrar on storage.objects;
create policy entregables_borrar on storage.objects for delete to authenticated
  using (bucket_id = 'entregables' and public.puede_area((storage.foldername(name))[1]));

-- "Sobre mí" del perfil (migración 009)
alter table public.perfiles add column if not exists bio text;
alter table public.perfiles drop constraint if exists perfiles_bio_largo;
alter table public.perfiles add constraint perfiles_bio_largo check (bio is null or char_length(bio) <= 600);

-- Portada de la carta de presentación (migración 014)
alter table public.perfiles add column if not exists portada text;

-- Quién es de Finanzas (migración 017)
alter table public.perfiles add column if not exists finanzas boolean not null default false;

-- Saludo del Dashboard: hijo o hija de Dios (migración 016)
alter table public.perfiles add column if not exists saludo text;
alter table public.perfiles drop constraint if exists perfiles_saludo_valido;
alter table public.perfiles add constraint perfiles_saludo_valido check (saludo is null or saludo in ('hijo','hija'));

-- Solo la PM cambia rol, área, áreas adicionales y finanzas; nombre, usuario, foto, bio y portada solo los cambia cada quien
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

-- ============ Entradas de formación (formulario público, migración 012) ============
-- ============ Tabla ============
create table if not exists public.entradas_formacion (
  id uuid primary key,
  creado timestamptz not null default now(),
  estado text not null default 'nueva'
    check (estado in ('nueva','revision','diseno','disenado','descartada')),
  data jsonb not null check (pg_column_size(data) < 200000),     -- respuestas del formulario
  archivos jsonb not null default '[]'::jsonb,                   -- [{nombre, ruta, tamano, tipo, campo}]
  notas text not null default '',                                -- notas internas del equipo
  actualizado timestamptz not null default now(),
  actualizado_por uuid
);

-- Hasta 20 documentos por entrada
alter table public.entradas_formacion drop constraint if exists entradas_formacion_archivos_check;
alter table public.entradas_formacion add constraint entradas_formacion_archivos_check
  check (jsonb_typeof(archivos) = 'array' and jsonb_array_length(archivos) <= 20);

create index if not exists entradas_formacion_creado on public.entradas_formacion (creado desc);

drop trigger if exists entradas_actualizado on public.entradas_formacion;
create trigger entradas_actualizado before update on public.entradas_formacion
for each row execute function public.marcar_actualizado();

-- Al enviar: la fecha la pone la base de datos (nadie puede adelantarla para quedar hasta arriba)
-- y cada documento debe estar en la carpeta de su propia entrada.
create or replace function public.entrada_nueva()
returns trigger language plpgsql as $$
begin
  new.creado = now(); new.actualizado = now(); new.actualizado_por = auth.uid();
  if exists (select 1 from jsonb_array_elements(new.archivos) a
             where coalesce(a->>'ruta','') not like new.id::text || '/%') then
    raise exception 'Cada documento debe estar en la carpeta de su entrada';
  end if;
  return new;
end $$;

drop trigger if exists entradas_nueva on public.entradas_formacion;
create trigger entradas_nueva before insert on public.entradas_formacion
for each row execute function public.entrada_nueva();

-- ============ Permisos ============
alter table public.entradas_formacion enable row level security;

-- Cualquiera con la liga puede ENVIAR una entrada nueva (sin iniciar sesión),
-- pero no puede leer, cambiar ni borrar entradas.
drop policy if exists entradas_enviar on public.entradas_formacion;
create policy entradas_enviar on public.entradas_formacion for insert to anon, authenticated
  with check (estado = 'nueva' and notas = '');

-- Solo la PM y quienes están en Formación (como área principal o en "También en") las ven y las trabajan.
drop policy if exists entradas_equipo on public.entradas_formacion;
create policy entradas_equipo on public.entradas_formacion for all to authenticated
  using (public.puede_area('formacion'))
  with check (public.puede_area('formacion'));

-- ============ Documentos (Storage) ============
-- Carpeta privada: hasta 25 MB por archivo, solo formatos de documentos e imágenes.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('entradas-formacion', 'entradas-formacion', false, 26214400, array[
  'application/pdf',
  'application/msword',
  'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  'application/vnd.ms-powerpoint',
  'application/vnd.openxmlformats-officedocument.presentationml.presentation',
  'application/vnd.ms-excel',
  'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  'application/vnd.oasis.opendocument.text',
  'application/vnd.oasis.opendocument.presentation',
  'text/plain', 'text/markdown',
  'image/jpeg', 'image/png'
])
on conflict (id) do update set
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types,
  public = false;

-- Subir: cualquiera, solo archivos nuevos dentro de una carpeta <uuid>/ (no puede reemplazar ni leer).
drop policy if exists entradas_docs_subir on storage.objects;
create policy entradas_docs_subir on storage.objects for insert to anon, authenticated
  with check (bucket_id = 'entradas-formacion'
    and (storage.foldername(name))[1] ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$');

-- Ver, descargar y borrar: solo la PM y Formación.
drop policy if exists entradas_docs_leer on storage.objects;
create policy entradas_docs_leer on storage.objects for select to authenticated
  using (bucket_id = 'entradas-formacion' and public.puede_area('formacion'));

drop policy if exists entradas_docs_borrar on storage.objects;
create policy entradas_docs_borrar on storage.objects for delete to authenticated
  using (bucket_id = 'entradas-formacion' and public.puede_area('formacion'));

-- ============ Tiempo real ============
-- Para que cada entrada nueva aparezca sola en la Bitácora.
do $$ begin
  alter publication supabase_realtime add table public.entradas_formacion;
exception when duplicate_object then null; end $$;

-- ============ Calendario, ligas por artista y canciones (migración 013) ============
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
alter table public.canciones add column if not exists ministerio text check (ministerio is null or char_length(ministerio) <= 120);  -- migración 015
alter table public.canciones add column if not exists lanzamiento date;  -- migración 015

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
  -- Las que llegan por liga toman el nombre de la liga como ministerio
  new.ministerio := coalesce((select nombre from public.ligas_artistas where id = new.liga), nullif(new.ministerio, ''), nullif(new.data->>'nombreArtistico',''));
  if exists (select 1 from jsonb_array_elements(new.archivos) a
             where coalesce(a->>'ruta','') not like coalesce(new.liga::text,'-') || '/' || new.id::text || '/%') then
    raise exception 'Cada archivo debe estar en la carpeta de su canción';
  end if;

  -- Las canciones que el equipo agrega a mano no traen liga: su pendiente lo crea la app (siguiente paso del checklist)
  if new.liga is null then return new; end if;

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
    'cancion_id', new.id, 'vence', null,
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

-- ============ Finanzas: solicitudes de gasto e ingresos (migración 017) ============
create or replace function public.puede_finanzas()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.perfiles where id = auth.uid() and (finanzas or rol = 'desarrollador'));
$$;

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

-- ============ Samply (migración 018) ============
-- Checklist de 24 pasos (las canciones nuevas nacen con pasos_version = 3)
alter table public.canciones add column if not exists pasos_version int not null default 3;  -- 3 = checklist de 24 pasos (migración 021)

-- ============ 2. Eventos de Samply ============
create table if not exists public.samply_eventos (
  id text primary key,                      -- webhook-id: evita guardar dos veces el mismo aviso
  creado timestamptz not null default now(),
  tipo text not null,                       -- upload.completed, comment.created…
  projectid text,
  boxid text,
  box_nombre text,
  mensaje text,
  autor text,
  payload jsonb
);
create index if not exists samply_eventos_proyecto on public.samply_eventos (projectid, creado desc);
alter table public.samply_eventos enable row level security;
drop policy if exists samply_eventos_ver on public.samply_eventos;
create policy samply_eventos_ver on public.samply_eventos for select to authenticated
  using (public.puede_area('musica'));
-- (solo la función "samply" escribe aquí, con la service_role key)

do $$ begin alter publication supabase_realtime add table public.samply_eventos;
exception when duplicate_object then null; end $$;

-- ============ 3. Configuración interna ============
create table if not exists public.samply_config (
  clave text primary key,
  valor text not null
);
alter table public.samply_config enable row level security;
-- Sin políticas: solo la service_role (la función) la lee y la escribe.

-- ============ Activos (migración 019) ============
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

-- ============ Ligas limpias e inamovibles por ministerio (migración 020) ============
alter table public.ligas_artistas add column if not exists slug text;
alter table public.ligas_artistas drop constraint if exists ligas_slug_formato;
alter table public.ligas_artistas add constraint ligas_slug_formato check (slug is null or slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$');
create unique index if not exists ligas_slug_unico on public.ligas_artistas (slug);

-- Texto → dirección: sin acentos, minúsculas y guiones (ANAWÍM → anawim, «Alex Patrón» → alex-patron)
create or replace function public.slug_texto(t text)
returns text language sql immutable as $$
  select left(trim(both '-' from regexp_replace(lower(translate(coalesce(t, ''),
    'ÁÉÍÓÚÜÑÀÈÌÒÙÂÊÎÔÛÇáéíóúüñàèìòùâêîôûç', 'AEIOUUNAEIOUAEIOUCaeiouunaeiouaeiouc')), '[^a-z0-9]+', '-', 'g')), 60);
$$;

-- Si ya existe, le agrega -2, -3…
create or replace function public.slug_libre(base text, propio uuid)
returns text language plpgsql stable set search_path = public as $$
declare s text := coalesce(nullif(trim(both '-' from base), ''), 'ministerio'); n int := 1; candidato text := s;
begin
  while exists (select 1 from public.ligas_artistas where slug = candidato and id is distinct from propio) loop
    n := n + 1; candidato := s || '-' || n;
  end loop;
  return candidato;
end $$;

create or replace function public.liga_slug()
returns trigger language plpgsql set search_path = public as $$
begin
  if tg_op = 'UPDATE' and old.slug is not null and new.slug is distinct from old.slug then
    raise exception 'La dirección de la liga de un ministerio no se puede cambiar';
  end if;
  if coalesce(new.slug, '') = '' then
    new.slug := public.slug_libre(public.slug_texto(new.nombre), new.id);
  end if;
  return new;
end $$;
drop trigger if exists ligas_slug on public.ligas_artistas;
create trigger ligas_slug before insert or update on public.ligas_artistas
for each row execute function public.liga_slug();

-- Las ligas que ya existían reciben su dirección (en orden de creación)
do $$ declare r record; begin
  for r in select id from public.ligas_artistas where coalesce(slug, '') = '' order by creado loop
    update public.ligas_artistas set slug = null where id = r.id;  -- el trigger le pone su dirección
  end loop;
end $$;

-- El formulario encuentra la liga por su dirección o por su id (las viejas), solo si está activa
create or replace function public.liga_resolver(l text)
returns json language plpgsql stable security definer set search_path = public as $$
declare r record;
begin
  select id, nombre, slug into r from public.ligas_artistas
   where activa and (slug = lower(trim(l)) or id::text = lower(trim(l))) limit 1;
  if not found then return null; end if;
  return json_build_object('id', r.id, 'nombre', r.nombre, 'slug', r.slug);
end $$;
grant execute on function public.liga_resolver(text) to anon, authenticated;

-- ============ Migración 022 (áreas Legal y Marketing, agenda para artistas, solicitudes de acceso) ============
-- ============ 1) Áreas nuevas: legal y marketing ============
alter table public.perfiles drop constraint if exists perfiles_area_check;
alter table public.perfiles add constraint perfiles_area_check
  check (area in ('formacion','musica','audiovisual','operativo','legal','marketing'));
alter table public.tareas drop constraint if exists tareas_area_check;
alter table public.tareas add constraint tareas_area_check
  check (area in ('formacion','musica','audiovisual','operativo','legal','marketing'));
alter table public.logros drop constraint if exists logros_area_check;
alter table public.logros add constraint logros_area_check
  check (area in ('formacion','musica','audiovisual','operativo','legal','marketing'));
alter table public.perfiles drop constraint if exists perfiles_areas_check;
alter table public.perfiles add constraint perfiles_areas_check
  check (areas <@ array['formacion','musica','audiovisual','operativo','legal','marketing']::text[]);

-- ¿La persona con sesión trabaja canciones? (Música, Legal, Marketing, Audiovisual por los lives, o PM)
create or replace function public.puede_canciones()
returns boolean language sql stable security definer set search_path = public as $$
  select public.puede_area('musica') or public.puede_area('legal') or public.puede_area('marketing') or public.puede_area('audiovisual');
$$;

-- ============ 2) Canciones: Legal, Marketing y Audiovisual también las ven y marcan su checklist ============
-- Dar de alta y borrar sigue siendo de Música (y PM).
drop policy if exists canciones_musica on public.canciones;
drop policy if exists canciones_ver on public.canciones;
create policy canciones_ver on public.canciones for select to authenticated using (public.puede_canciones());
drop policy if exists canciones_trabajar on public.canciones;
create policy canciones_trabajar on public.canciones for update to authenticated
  using (public.puede_canciones()) with check (public.puede_canciones());
drop policy if exists canciones_alta on public.canciones;
create policy canciones_alta on public.canciones for insert to authenticated with check (public.puede_area('musica'));
drop policy if exists canciones_borrar_fila on public.canciones;
create policy canciones_borrar_fila on public.canciones for delete to authenticated using (public.puede_area('musica'));

-- Documentos: Legal sube el comprobante INDAUTOR y el splitsheet en canciones/equipo/<canción>/…
drop policy if exists canciones_leer on storage.objects;
create policy canciones_leer on storage.objects for select to authenticated
  using (bucket_id = 'canciones' and public.puede_canciones());
drop policy if exists canciones_equipo_subir on storage.objects;
create policy canciones_equipo_subir on storage.objects for insert to authenticated
  with check (bucket_id = 'canciones' and (storage.foldername(name))[1] = 'equipo'
              and (public.puede_area('musica') or public.puede_area('legal')));

-- Pendientes automáticos de canciones: quien trabaja canciones crea y cierra el siguiente paso en cualquiera
-- de las áreas del funnel (Música, Legal, Marketing y la copia de Audiovisual de los lives).
drop policy if exists tareas_funnel on public.tareas;
create policy tareas_funnel on public.tareas for all to authenticated
  using (data ? 'cancion_id' and area in ('musica','legal','marketing','audiovisual') and public.puede_canciones())
  with check (data ? 'cancion_id' and area in ('musica','legal','marketing','audiovisual') and public.puede_canciones());

-- Los pendientes abiertos de INDAUTOR/splitsheet pasan a Legal y los de marketing (handoff y D-Day) a Marketing
update public.tareas set area = 'legal', data = jsonb_set(data, '{area}', '"legal"')
 where area = 'musica' and data ? 'cancion_id' and data->>'hecha' is null
   and (data->>'paso') in ('13','14')
   and exists (select 1 from public.canciones c where c.id::text = tareas.data->>'cancion_id' and coalesce(c.data->>'formato','estudio') <> 'live');
update public.tareas set area = 'marketing', data = jsonb_set(data, '{area}', '"marketing"')
 where area = 'musica' and data ? 'cancion_id' and data->>'hecha' is null
   and (data->>'paso') ~ '^(1[6-9]|2[0-4])$'
   and exists (select 1 from public.canciones c where c.id::text = tareas.data->>'cancion_id' and coalesce(c.data->>'formato','estudio') <> 'live');

-- ============ 3) Enlace de agenda de producción para artistas ============
-- Música arma un enlace (/agenda/<token>) marcando el tipo de producción del artista. El artista ve las semanas
-- con lugar para ese tipo (reglas en app/agenda-reglas.js) y reserva; la reserva queda en el calendario de Música.
create table if not exists public.agendas_artistas (
  id uuid primary key default gen_random_uuid(),
  token text not null unique default replace(gen_random_uuid()::text, '-', ''),
  tipo text not null check (tipo in ('acustico','fullband','grande')),
  nombre text not null default '' check (char_length(nombre) <= 120),
  cancion_id uuid references public.canciones(id) on delete set null,
  activa boolean not null default true,
  reservado jsonb,             -- {inicio, fin, nombre, correo, telefono, notas, cuando}
  creado timestamptz not null default now(),
  creado_por uuid default auth.uid()
);
alter table public.agendas_artistas enable row level security;
drop policy if exists agendas_musica on public.agendas_artistas;
create policy agendas_musica on public.agendas_artistas for all to authenticated
  using (public.puede_area('musica')) with check (public.puede_area('musica'));

-- Lo que ve el artista: tipo, nombre y solo las fechas que ocupan producción (sin títulos ni notas)
create or replace function public.agenda_ver(t text)
returns json language plpgsql stable security definer set search_path = public as $$
declare a record;
begin
  select * into a from public.agendas_artistas where token = lower(trim(t)) and activa limit 1;
  if not found then return null; end if;
  return json_build_object(
    'tipo', a.tipo, 'nombre', a.nombre,
    'reservado', case when a.reservado is null then null else json_build_object('inicio', a.reservado->>'inicio', 'fin', a.reservado->>'fin') end,
    'eventos', coalesce((select json_agg(json_build_object(
        'id', md5(e.id), 'tipo', e.data->>'tipo', 'fecha', e.data->>'fecha', 'fin', e.data->>'fin',
        'repetir', e.data->>'repetir', 'hasta', e.data->>'hasta', 'excepciones', coalesce(e.data->'excepciones', '[]'::jsonb),
        'cancion_id', case when coalesce(e.data->>'cancion_id', '') <> '' then 'si' end))
      from public.eventos e
      where e.data->>'tipo' in ('produccion','grabacion','externo','inhabil')
        and (coalesce(e.data->>'repetir', '') <> '' or coalesce(nullif(e.data->>'fin', ''), e.data->>'fecha') >= to_char(current_date - 14, 'YYYY-MM-DD'))), '[]'::json));
end $$;
grant execute on function public.agenda_ver(text) to anon, authenticated;

-- Reservar: vuelve a revisar que esas fechas sigan libres y deja la producción en el calendario
create or replace function public.agenda_reservar(t text, inicio date, fin date, nombre text, correo text, telefono text, notas text)
returns json language plpgsql security definer set search_path = public as $$
#variable_conflict use_variable
declare a record; c record; paso text; ev text;
begin
  select * into a from public.agendas_artistas where token = lower(trim(t)) and activa for update;
  if not found then raise exception 'Este enlace ya no está activo.'; end if;
  if a.reservado is not null then raise exception 'Este enlace ya tiene una fecha reservada.'; end if;
  if inicio is null or fin is null or fin < inicio or fin - inicio > 13 then raise exception 'Fechas no válidas.'; end if;
  if inicio <= current_date then raise exception 'Elige una fecha a partir de mañana.'; end if;
  if coalesce(trim(nombre), '') = '' or coalesce(trim(correo), '') = '' then raise exception 'Escribe tu nombre y tu correo.'; end if;
  if exists (select 1 from public.eventos e
              where (e.data->>'tipo' in ('produccion','inhabil') or (e.data->>'tipo' = 'grabacion' and coalesce(e.data->>'cancion_id', '') <> ''))
                and coalesce(e.data->>'repetir', '') = ''
                and (e.data->>'fecha')::date <= fin
                and coalesce(nullif(e.data->>'fin', ''), e.data->>'fecha')::date >= inicio) then
    raise exception 'Alguien acaba de apartar esas fechas. Elige otras, por favor.';
  end if;
  ev := 'agenda-' || a.id;
  insert into public.eventos (id, area, data) values (ev, 'musica', jsonb_build_object(
    'titulo', 'Producción · ' || coalesce(nullif(a.nombre, ''), left(trim(nombre), 80)),
    'tipo', 'produccion', 'tipoProd', a.tipo, 'fecha', to_char(inicio, 'YYYY-MM-DD'), 'fin', case when fin > inicio then to_char(fin, 'YYYY-MM-DD') else '' end,
    'hora', '09:00', 'horaFin', '17:00', 'repetir', '', 'hasta', '', 'area', 'musica', 'excepciones', '[]'::jsonb,
    'notas', left('Agendada por el artista desde el enlace de agenda: ' || trim(nombre) || ' · ' || trim(correo) || coalesce(' · ' || nullif(trim(telefono), ''), '') || coalesce(' · ' || nullif(trim(notas), ''), ''), 1000),
    'cancion_id', a.cancion_id, 'agenda_id', a.id, 'creado', now()));
  update public.agendas_artistas set reservado = jsonb_build_object('inicio', inicio, 'fin', fin, 'nombre', left(trim(nombre), 120),
    'correo', left(trim(correo), 160), 'telefono', left(coalesce(trim(telefono), ''), 40), 'notas', left(coalesce(trim(notas), ''), 1000), 'cuando', now(), 'evento', ev)
   where id = a.id;
  -- La canción ligada queda agendada (estudio: paso 5; live: paso 3)
  if a.cancion_id is not null then
    select * into c from public.canciones where id = a.cancion_id;
    if found then
      paso := case when c.data->>'formato' = 'live' then '3' else '5' end;
      update public.canciones set semana = date_trunc('week', inicio)::date,
        checklist = case when checklist ? paso then checklist else checklist || jsonb_build_object(paso, now()) end,
        etapa = case when etapa in ('intake','preproduccion') then 'agendada' else etapa end
       where id = a.cancion_id;
    end if;
  end if;
  return json_build_object('ok', true, 'inicio', inicio, 'fin', fin);
end $$;
grant execute on function public.agenda_reservar(text, date, date, text, text, text, text) to anon, authenticated;

do $$ begin alter publication supabase_realtime add table public.agendas_artistas;
exception when duplicate_object then null; end $$;

-- ============ 4) Acceso a áreas: cada quien ve solo sus áreas y pide las demás ============
-- La PM (o el desarrollador) aprueba en Equipo: se agrega el área a perfiles.areas (o como su área, si no tenía).
create table if not exists public.solicitudes_area (
  id uuid primary key default gen_random_uuid(),
  usuario uuid not null default auth.uid() references public.perfiles(id) on delete cascade,
  area text not null check (area in ('formacion','musica','audiovisual','operativo','legal','marketing')),
  nota text not null default '' check (char_length(nota) <= 500),
  estado text not null default 'pendiente' check (estado in ('pendiente','aprobada','rechazada')),
  creado timestamptz not null default now(),
  resuelto timestamptz,
  resuelto_por uuid
);
alter table public.solicitudes_area enable row level security;
drop policy if exists solicitudes_ver on public.solicitudes_area;
create policy solicitudes_ver on public.solicitudes_area for select to authenticated
  using (usuario = auth.uid() or public.es_pm());
drop policy if exists solicitudes_pedir on public.solicitudes_area;
create policy solicitudes_pedir on public.solicitudes_area for insert to authenticated
  with check (usuario = auth.uid() and estado = 'pendiente');
drop policy if exists solicitudes_resolver on public.solicitudes_area;
create policy solicitudes_resolver on public.solicitudes_area for update to authenticated
  using (public.es_pm()) with check (public.es_pm());
drop policy if exists solicitudes_borrar on public.solicitudes_area;
create policy solicitudes_borrar on public.solicitudes_area for delete to authenticated using (public.es_pm());

do $$ begin alter publication supabase_realtime add table public.solicitudes_area;
exception when duplicate_object then null; end $$;

-- ============ Migración 023 (liga fija de agenda por ministerio) ============
alter table public.agendas_artistas add column if not exists reutilizable boolean not null default false;
alter table public.agendas_artistas add column if not exists reservas jsonb not null default '[]'::jsonb;
alter table public.agendas_artistas drop constraint if exists agendas_token_formato;
alter table public.agendas_artistas add constraint agendas_token_formato check (token ~ '^[a-z0-9]+(-[a-z0-9]+)*$');

-- Lo que ve el artista (las ligas fijas no se «gastan»: nunca se muestran como ya reservadas)
create or replace function public.agenda_ver(t text)
returns json language plpgsql stable security definer set search_path = public as $$
declare a record;
begin
  select * into a from public.agendas_artistas where token = lower(trim(t)) and activa limit 1;
  if not found then return null; end if;
  return json_build_object(
    'tipo', a.tipo, 'nombre', a.nombre, 'reutilizable', a.reutilizable,
    'reservado', case when a.reservado is null or a.reutilizable then null else json_build_object('inicio', a.reservado->>'inicio', 'fin', a.reservado->>'fin') end,
    'eventos', coalesce((select json_agg(json_build_object(
        'id', md5(e.id), 'tipo', e.data->>'tipo', 'fecha', e.data->>'fecha', 'fin', e.data->>'fin',
        'repetir', e.data->>'repetir', 'hasta', e.data->>'hasta', 'excepciones', coalesce(e.data->'excepciones', '[]'::jsonb),
        'cancion_id', case when coalesce(e.data->>'cancion_id', '') <> '' then 'si' end))
      from public.eventos e
      where e.data->>'tipo' in ('produccion','grabacion','externo','inhabil')
        and (coalesce(e.data->>'repetir', '') <> '' or coalesce(nullif(e.data->>'fin', ''), e.data->>'fecha') >= to_char(current_date - 14, 'YYYY-MM-DD'))), '[]'::json));
end $$;
grant execute on function public.agenda_ver(text) to anon, authenticated;

create or replace function public.agenda_reservar(t text, inicio date, fin date, nombre text, correo text, telefono text, notas text)
returns json language plpgsql security definer set search_path = public as $$
#variable_conflict use_variable
declare a record; c record; paso text; ev text; r jsonb; cancion text;
begin
  select * into a from public.agendas_artistas where token = lower(trim(t)) and activa for update;
  if not found then raise exception 'Este enlace ya no está activo.'; end if;
  if a.reservado is not null and not a.reutilizable then raise exception 'Este enlace ya tiene una fecha reservada.'; end if;
  if inicio is null or fin is null or fin < inicio or fin - inicio > 13 then raise exception 'Fechas no válidas.'; end if;
  if inicio <= current_date then raise exception 'Elige una fecha a partir de mañana.'; end if;
  if coalesce(trim(nombre), '') = '' or coalesce(trim(correo), '') = '' then raise exception 'Escribe tu nombre y tu correo.'; end if;
  if exists (select 1 from public.eventos e
              where (e.data->>'tipo' in ('produccion','inhabil') or (e.data->>'tipo' = 'grabacion' and coalesce(e.data->>'cancion_id', '') <> ''))
                and coalesce(e.data->>'repetir', '') = ''
                and (e.data->>'fecha')::date <= fin
                and coalesce(nullif(e.data->>'fin', ''), e.data->>'fecha')::date >= inicio) then
    raise exception 'Alguien acaba de apartar esas fechas. Elige otras, por favor.';
  end if;
  ev := 'agenda-' || a.id || case when a.reutilizable then '-' || to_char(inicio, 'YYYYMMDD') else '' end;
  -- En las ligas fijas, el nombre de la canción va en las notas (opcional): «Canción: …»
  cancion := nullif(trim(substring(coalesce(notas, '') from '^Canción: ([^\n]*)')), '');
  insert into public.eventos (id, area, data) values (ev, 'musica', jsonb_build_object(
    'titulo', 'Producción · ' || coalesce(nullif(a.nombre, ''), left(trim(nombre), 80)) || coalesce(' · «' || cancion || '»', ''),
    'tipo', 'produccion', 'tipoProd', a.tipo, 'fecha', to_char(inicio, 'YYYY-MM-DD'), 'fin', case when fin > inicio then to_char(fin, 'YYYY-MM-DD') else '' end,
    'hora', '09:00', 'horaFin', '17:00', 'repetir', '', 'hasta', '', 'area', 'musica', 'excepciones', '[]'::jsonb,
    'notas', left('Agendada por el artista desde el enlace de agenda: ' || trim(nombre) || ' · ' || trim(correo) || coalesce(' · ' || nullif(trim(telefono), ''), '') || coalesce(' · ' || nullif(trim(notas), ''), ''), 1000),
    'cancion_id', a.cancion_id, 'agenda_id', a.id, 'creado', now()));
  r := jsonb_build_object('inicio', inicio, 'fin', fin, 'nombre', left(trim(nombre), 120),
    'correo', left(trim(correo), 160), 'telefono', left(coalesce(trim(telefono), ''), 40), 'notas', left(coalesce(trim(notas), ''), 1000), 'cuando', now(), 'evento', ev);
  update public.agendas_artistas set reservado = r, reservas = coalesce(reservas, '[]'::jsonb) || jsonb_build_array(r) where id = a.id;
  if a.cancion_id is not null then
    select * into c from public.canciones where id = a.cancion_id;
    if found then
      paso := case when c.data->>'formato' = 'live' then '3' else '5' end;
      update public.canciones set semana = date_trunc('week', inicio)::date,
        checklist = case when checklist ? paso then checklist else checklist || jsonb_build_object(paso, now()) end,
        etapa = case when etapa in ('intake','preproduccion') then 'agendada' else etapa end
       where id = a.cancion_id;
    end if;
  end if;
  return json_build_object('ok', true, 'inicio', inicio, 'fin', fin);
end $$;
grant execute on function public.agenda_reservar(text, date, date, text, text, text, text) to anon, authenticated;

-- ============ Migración 024 (días exactos en las producciones que aparta un artista) ============
create or replace function public.agenda_reservar(t text, inicio date, fin date, nombre text, correo text, telefono text, notas text)
returns json language plpgsql security definer set search_path = public as $$
#variable_conflict use_variable
declare a record; c record; paso text; ev text; r jsonb; cancion text; dias jsonb;
begin
  select * into a from public.agendas_artistas where token = lower(trim(t)) and activa for update;
  if not found then raise exception 'Este enlace ya no está activo.'; end if;
  if a.reservado is not null and not a.reutilizable then raise exception 'Este enlace ya tiene una fecha reservada.'; end if;
  if inicio is null or fin is null or fin < inicio or fin - inicio > 13 then raise exception 'Fechas no válidas.'; end if;
  if inicio <= current_date then raise exception 'Elige una fecha a partir de mañana.'; end if;
  if coalesce(trim(nombre), '') = '' or coalesce(trim(correo), '') = '' then raise exception 'Escribe tu nombre y tu correo.'; end if;
  if exists (select 1 from public.eventos e
              where (e.data->>'tipo' in ('produccion','inhabil') or (e.data->>'tipo' = 'grabacion' and coalesce(e.data->>'cancion_id', '') <> ''))
                and coalesce(e.data->>'repetir', '') = ''
                and (e.data->>'fecha')::date <= fin
                and coalesce(nullif(e.data->>'fin', ''), e.data->>'fecha')::date >= inicio) then
    raise exception 'Alguien acaba de apartar esas fechas. Elige otras, por favor.';
  end if;
  -- Días exactos: entre semana y sin el miércoles cuando ese viernes también se produce (igual que agenda-reglas.js)
  select coalesce(jsonb_agg(to_char(d, 'YYYY-MM-DD') order by d), '[]'::jsonb) into dias
    from generate_series(inicio::timestamp, fin::timestamp, interval '1 day') g(d)
   where extract(isodow from d) < 6 and not (extract(isodow from d) = 3 and d::date + 2 <= fin);
  ev := 'agenda-' || a.id || case when a.reutilizable then '-' || to_char(inicio, 'YYYYMMDD') else '' end;
  -- En las ligas fijas, el nombre de la canción va en las notas (opcional): «Canción: …»
  cancion := nullif(trim(substring(coalesce(notas, '') from '^Canción: ([^\n]*)')), '');
  insert into public.eventos (id, area, data) values (ev, 'musica', jsonb_build_object(
    'titulo', 'Producción · ' || coalesce(nullif(a.nombre, ''), left(trim(nombre), 80)) || coalesce(' · «' || cancion || '»', ''),
    'tipo', 'produccion', 'tipoProd', a.tipo, 'fecha', to_char(inicio, 'YYYY-MM-DD'), 'fin', case when fin > inicio then to_char(fin, 'YYYY-MM-DD') else '' end,
    'dias', dias, 'hora', '09:00', 'horaFin', '17:00', 'repetir', '', 'hasta', '', 'area', 'musica', 'excepciones', '[]'::jsonb,
    'notas', left('Agendada por el artista desde el enlace de agenda: ' || trim(nombre) || ' · ' || trim(correo) || coalesce(' · ' || nullif(trim(telefono), ''), '') || coalesce(' · ' || nullif(trim(notas), ''), ''), 1000),
    'cancion_id', a.cancion_id, 'agenda_id', a.id, 'creado', now()));
  r := jsonb_build_object('inicio', inicio, 'fin', fin, 'nombre', left(trim(nombre), 120),
    'correo', left(trim(correo), 160), 'telefono', left(coalesce(trim(telefono), ''), 40), 'notas', left(coalesce(trim(notas), ''), 1000), 'cuando', now(), 'evento', ev);
  update public.agendas_artistas set reservado = r, reservas = coalesce(reservas, '[]'::jsonb) || jsonb_build_array(r) where id = a.id;
  if a.cancion_id is not null then
    select * into c from public.canciones where id = a.cancion_id;
    if found then
      paso := case when c.data->>'formato' = 'live' then '3' else '5' end;
      update public.canciones set semana = date_trunc('week', inicio)::date,
        checklist = case when checklist ? paso then checklist else checklist || jsonb_build_object(paso, now()) end,
        etapa = case when etapa in ('intake','preproduccion') then 'agendada' else etapa end
       where id = a.cancion_id;
    end if;
  end if;
  return json_build_object('ok', true, 'inicio', inicio, 'fin', fin);
end $$;
grant execute on function public.agenda_reservar(text, date, date, text, text, text, text) to anon, authenticated;

-- ============ Migración 025 (del registro de canción a la agenda) ============
-- Ministerios del colectivo (solo nombres de las ligas activas) para el selector del formulario
create or replace function public.ministerios_colectivo()
returns json language sql stable security definer set search_path = public as $$
  select coalesce(json_agg(nombre order by lower(nombre)), '[]'::json)
    from (select distinct nombre from public.ligas_artistas where activa and coalesce(trim(nombre), '') <> '') m;
$$;
grant execute on function public.ministerios_colectivo() to anon, authenticated;

-- La liga fija de agenda de un ministerio queda amarrada a su liga de canciones
alter table public.agendas_artistas add column if not exists liga uuid references public.ligas_artistas(id) on delete set null;

-- Código de la liga fija de agenda del ministerio de esa liga para ese tipo (la crea si no existe)
create or replace function public.agenda_de_liga(l uuid, tipo text)
returns text language plpgsql security definer set search_path = public as $$
#variable_conflict use_variable
declare li record; a record; base text; tok text; n int := 1;
begin
  if tipo not in ('acustico','fullband','grande') then return null; end if;
  select * into li from public.ligas_artistas where id = l and activa;
  if not found then return null; end if;
  select * into a from public.agendas_artistas x
   where x.reutilizable and x.activa and x.tipo = tipo and (x.liga = l or (x.liga is null and x.nombre = li.nombre))
   order by (x.liga = l) desc nulls last limit 1;
  if found then
    if a.liga is null then update public.agendas_artistas set liga = l where id = a.id; end if;
    return a.token;
  end if;
  base := coalesce(nullif(li.slug, ''), public.slug_texto(li.nombre), 'ministerio') || '-' ||
          case tipo when 'acustico' then 'acustica' else tipo end;
  tok := base;
  while exists (select 1 from public.agendas_artistas where token = tok) loop n := n + 1; tok := base || '-' || n; end loop;
  insert into public.agendas_artistas (token, tipo, nombre, reutilizable, liga, creado_por)
  values (tok, tipo, left(li.nombre, 120), true, l, null);
  return tok;
end $$;
grant execute on function public.agenda_de_liga(uuid, text) to anon, authenticated;

-- Reservar, ahora con la canción que el artista acaba de registrar (c_id, opcional)
drop function if exists public.agenda_reservar(text, date, date, text, text, text, text);
create or replace function public.agenda_reservar(t text, inicio date, fin date, nombre text, correo text, telefono text, notas text, c_id uuid default null)
returns json language plpgsql security definer set search_path = public as $$
#variable_conflict use_variable
declare a record; c record; paso text; ev text; r jsonb; cancion text; dias jsonb; cid uuid;
begin
  select * into a from public.agendas_artistas where token = lower(trim(t)) and activa for update;
  if not found then raise exception 'Este enlace ya no está activo.'; end if;
  if a.reservado is not null and not a.reutilizable then raise exception 'Este enlace ya tiene una fecha reservada.'; end if;
  if inicio is null or fin is null or fin < inicio or fin - inicio > 13 then raise exception 'Fechas no válidas.'; end if;
  if inicio <= current_date then raise exception 'Elige una fecha a partir de mañana.'; end if;
  if coalesce(trim(nombre), '') = '' or coalesce(trim(correo), '') = '' then raise exception 'Escribe tu nombre y tu correo.'; end if;
  if exists (select 1 from public.eventos e
              where (e.data->>'tipo' in ('produccion','inhabil') or (e.data->>'tipo' = 'grabacion' and coalesce(e.data->>'cancion_id', '') <> ''))
                and coalesce(e.data->>'repetir', '') = ''
                and (e.data->>'fecha')::date <= fin
                and coalesce(nullif(e.data->>'fin', ''), e.data->>'fecha')::date >= inicio) then
    raise exception 'Alguien acaba de apartar esas fechas. Elige otras, por favor.';
  end if;
  -- La canción: la de la liga de un solo uso o la que el artista acaba de registrar con la liga de su ministerio (sin agendar aún)
  cid := a.cancion_id;
  if cid is null and c_id is not null and a.liga is not null then
    select id into cid from public.canciones where id = c_id and liga = a.liga and semana is null;
  end if;
  select coalesce(jsonb_agg(to_char(d, 'YYYY-MM-DD') order by d), '[]'::jsonb) into dias
    from generate_series(inicio::timestamp, fin::timestamp, interval '1 day') g(d)
   where extract(isodow from d) < 6 and not (extract(isodow from d) = 3 and d::date + 2 <= fin);
  ev := 'agenda-' || a.id || case when a.reutilizable then '-' || to_char(inicio, 'YYYYMMDD') else '' end;
  cancion := coalesce((select nullif(data->>'titulo', '') from public.canciones where id = cid),
                      nullif(trim(substring(coalesce(notas, '') from '^Canción: ([^\n]*)')), ''));
  insert into public.eventos (id, area, data) values (ev, 'musica', jsonb_build_object(
    'titulo', 'Producción · ' || coalesce(nullif(a.nombre, ''), left(trim(nombre), 80)) || coalesce(' · «' || cancion || '»', ''),
    'tipo', 'produccion', 'tipoProd', a.tipo, 'fecha', to_char(inicio, 'YYYY-MM-DD'), 'fin', case when fin > inicio then to_char(fin, 'YYYY-MM-DD') else '' end,
    'dias', dias, 'hora', '09:00', 'horaFin', '17:00', 'repetir', '', 'hasta', '', 'area', 'musica', 'excepciones', '[]'::jsonb,
    'notas', left('Agendada por el artista desde el enlace de agenda: ' || trim(nombre) || ' · ' || trim(correo) || coalesce(' · ' || nullif(trim(telefono), ''), '') || coalesce(' · ' || nullif(trim(notas), ''), ''), 1000),
    'cancion_id', cid, 'agenda_id', a.id, 'creado', now()));
  r := jsonb_build_object('inicio', inicio, 'fin', fin, 'nombre', left(trim(nombre), 120), 'correo', left(trim(correo), 160),
    'telefono', left(coalesce(trim(telefono), ''), 40), 'notas', left(coalesce(trim(notas), ''), 1000), 'cuando', now(), 'evento', ev, 'cancion_id', cid);
  update public.agendas_artistas set reservado = r, reservas = coalesce(reservas, '[]'::jsonb) || jsonb_build_array(r) where id = a.id;
  if cid is not null then
    select * into c from public.canciones where id = cid;
    if found then
      paso := case when c.data->>'formato' = 'live' then '3' else '5' end;
      update public.canciones set semana = date_trunc('week', inicio)::date,
        data = case when c.data ? 'tipoProd' then c.data else c.data || jsonb_build_object('tipoProd', a.tipo) end,
        checklist = case when checklist ? paso then checklist else checklist || jsonb_build_object(paso, now()) end,
        etapa = case when etapa in ('intake','preproduccion') then 'agendada' else etapa end
       where id = cid;
      -- El pendiente «Agendar producción» de esa canción queda hecho
      update public.tareas set data = data || jsonb_build_object('hecha', to_char(now() at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
             'cierre', 'El artista apartó sus fechas desde la liga de agenda: ' || to_char(inicio, 'DD/MM') || ' – ' || to_char(fin, 'DD/MM/YYYY'))
       where data->>'cancion_id' = cid::text and not (data ? 'paso') and coalesce(data->>'hecha', '') = '';
    end if;
  end if;
  return json_build_object('ok', true, 'inicio', inicio, 'fin', fin);
end $$;
grant execute on function public.agenda_reservar(text, date, date, text, text, text, text, uuid) to anon, authenticated;

-- ============ Migración 026 (trivia, sugerencias, scripts, tareas asignadas) ============
-- ============ Trivia del día ============
create table if not exists public.trivia_respuestas (
  usuario uuid not null default auth.uid() references public.perfiles(id) on delete cascade,
  fecha date not null,
  aciertos int not null check (aciertos between 0 and 20),
  total int not null check (total between 1 and 20),
  respuestas jsonb not null default '[]'::jsonb check (pg_column_size(respuestas) < 8000),
  creado timestamptz not null default now(),
  primary key (usuario, fecha)
);
alter table public.trivia_respuestas enable row level security;
drop policy if exists trivia_ver on public.trivia_respuestas;
create policy trivia_ver on public.trivia_respuestas for select to authenticated using (true);
-- Cada quien guarda la suya, una vez por día (con un día de margen por la zona horaria)
drop policy if exists trivia_contestar on public.trivia_respuestas;
create policy trivia_contestar on public.trivia_respuestas for insert to authenticated
  with check (usuario = auth.uid() and fecha between current_date - 1 and current_date + 1);

-- ============ Sugerencias ============
create table if not exists public.sugerencias (
  id uuid primary key default gen_random_uuid(),
  autor uuid default auth.uid() references public.perfiles(id) on delete set null,
  tipo text not null default 'mejora' check (tipo in ('mejora','error','idea')),
  area text,
  titulo text not null check (char_length(titulo) between 3 and 140),
  detalle text not null default '' check (char_length(detalle) <= 4000),
  estado text not null default 'nueva' check (estado in ('nueva','aprobada','en_proceso','hecha','rechazada')),
  respuesta text not null default '' check (char_length(respuesta) <= 2000),
  creado timestamptz not null default now(),
  actualizado timestamptz not null default now(),
  resuelto_por uuid
);
create or replace function public.sugerencia_actualizada()
returns trigger language plpgsql as $$ begin new.actualizado = now(); return new; end $$;
drop trigger if exists sugerencias_actualizado on public.sugerencias;
create trigger sugerencias_actualizado before update on public.sugerencias for each row execute function public.sugerencia_actualizada();
alter table public.sugerencias enable row level security;
drop policy if exists sugerencias_ver on public.sugerencias;
create policy sugerencias_ver on public.sugerencias for select to authenticated using (true);
-- Proponer: a nombre propio, como «nueva», y máximo 5 abiertas por persona (para que no se descontrolen)
drop policy if exists sugerencias_proponer on public.sugerencias;
create policy sugerencias_proponer on public.sugerencias for insert to authenticated
  with check (autor = auth.uid() and estado = 'nueva' and respuesta = ''
    and (select count(*) from public.sugerencias s where s.autor = auth.uid() and s.estado in ('nueva','aprobada','en_proceso')) < 5);
drop policy if exists sugerencias_gestionar on public.sugerencias;
create policy sugerencias_gestionar on public.sugerencias for update to authenticated using (public.es_pm()) with check (public.es_pm());
drop policy if exists sugerencias_borrar on public.sugerencias;
create policy sugerencias_borrar on public.sugerencias for delete to authenticated
  using (public.es_pm() or (autor = auth.uid() and estado = 'nueva'));

-- ============ Tareas asignadas a alguien de otra área ============
-- Quien es responsable de una tarea (o de una de sus subtareas) puede editarla y completarla
-- (notas, ligas, archivos, cierre) aunque no esté en esa área. Crear y borrar sigue siendo del área.
drop policy if exists tareas_asignadas on public.tareas;
create policy tareas_asignadas on public.tareas for update to authenticated
  using (data->>'responsable_id' = auth.uid()::text
         or exists (select 1 from jsonb_array_elements(coalesce(data->'subtareas', '[]'::jsonb)) s where s->>'responsable_id' = auth.uid()::text))
  with check (data->>'responsable_id' = auth.uid()::text
         or exists (select 1 from jsonb_array_elements(coalesce(data->'subtareas', '[]'::jsonb)) s where s->>'responsable_id' = auth.uid()::text));

-- Archivos entregables (<área>/<tarea>/…): cualquiera del área (también las áreas adicionales) o el responsable de la tarea
create or replace function public.puede_entregable(carpeta_area text, tarea text)
returns boolean language sql stable security definer set search_path = public as $$
  select public.puede_area(carpeta_area) or exists (
    select 1 from public.tareas t where t.id = tarea and (t.data->>'responsable_id' = auth.uid()::text
      or exists (select 1 from jsonb_array_elements(coalesce(t.data->'subtareas', '[]'::jsonb)) s where s->>'responsable_id' = auth.uid()::text)));
$$;
drop policy if exists entregables_subir on storage.objects;
create policy entregables_subir on storage.objects for insert to authenticated
  with check (bucket_id = 'entregables' and public.puede_entregable((storage.foldername(name))[1], (storage.foldername(name))[2]));
drop policy if exists entregables_borrar on storage.objects;
create policy entregables_borrar on storage.objects for delete to authenticated
  using (bucket_id = 'entregables' and public.puede_entregable((storage.foldername(name))[1], (storage.foldername(name))[2]));

-- ============ Scripts (migraciones) ya corridos ============
create table if not exists public.migraciones_aplicadas (
  nombre text primary key,
  aplicada timestamptz not null default now(),
  por uuid default auth.uid()
);
alter table public.migraciones_aplicadas enable row level security;
drop policy if exists migraciones_ver on public.migraciones_aplicadas;
create policy migraciones_ver on public.migraciones_aplicadas for select to authenticated using (public.es_pm());
drop policy if exists migraciones_marcar on public.migraciones_aplicadas;
create policy migraciones_marcar on public.migraciones_aplicadas for insert to authenticated with check (public.es_pm());

do $$ begin alter publication supabase_realtime add table public.trivia_respuestas;
exception when duplicate_object then null; end $$;
do $$ begin alter publication supabase_realtime add table public.sugerencias;
exception when duplicate_object then null; end $$;

-- Todas las anteriores ya se corrieron; esta también queda registrada
insert into public.migraciones_aplicadas (nombre) values
  ('002_perfil_y_fotos'),
  ('003_rol_desarrollador'),
  ('004_usuario'),
  ('005_fotos_lectura'),
  ('006_entregables'),
  ('007_operativo_y_varias_areas'),
  ('008_avisos_por_correo'),
  ('009_presentacion'),
  ('010_avisos_nombre_funcion'),
  ('011_perfil_propio'),
  ('012_entradas_formacion'),
  ('013_calendario_y_canciones'),
  ('014_portada'),
  ('015_ministerios_y_lanzamiento'),
  ('016_saludo'),
  ('017_finanzas'),
  ('018_samply'),
  ('019_activos'),
  ('020_ligas_limpias'),
  ('021_paso_distrokid'),
  ('022_legal_marketing_calendario'),
  ('023_agenda_por_ministerio'),
  ('024_dias_de_produccion'),
  ('025_cancion_a_agenda'),
  ('026_trivia_y_sugerencias')
on conflict (nombre) do nothing;

-- ============ Migración 027: Operativo → Personas ============
-- Bitácora Tiempo de Dios · migración 027: Operativo → Personas (base de asistentes y donadores)
-- · crm_personas: un perfil único por persona (contacto, cumpleaños, estado de seguimiento, responsable,
--   próxima acción). No se duplica: el registro busca primero por correo y luego por teléfono.
-- · crm_asistencias: quién se registró, confirmó, vino o no vino a cada fecha de un cenáculo o evento del
--   calendario (evento = id del evento en «eventos», fecha = el día; los cenáculos se repiten).
-- · crm_seguimientos: historial de conversaciones y próximas acciones.
-- · crm_donaciones: solo Finanzas, la PM y el desarrollador ven montos. «donador» en la persona lo pone un trigger.
-- · crm_mensajes: correos y WhatsApp enviados o recibidos (también evita mandar dos veces lo mismo).
-- · crm_boletines: newsletters.
-- · Funciones públicas para el formulario /registro: eventos con registro abierto, registrarse,
--   confirmar o cancelar desde la liga personal y darse de baja de los correos.
-- · Cron diario (9:00 de México) que llama a la Edge Function «crm»: invitaciones 15 y 7 días antes,
--   recordatorio por WhatsApp 2 días antes y resumen para Operativo.
-- Ejecútala una vez en Supabase → SQL Editor → Run. Se puede volver a correr sin error.

create or replace function public.crm_tocar()
returns trigger language plpgsql as $$ begin new.actualizado = now(); return new; end $$;

-- ============ Personas ============
create table if not exists public.crm_personas (
  id uuid primary key default gen_random_uuid(),
  nombre text not null check (char_length(trim(nombre)) between 2 and 120),
  telefono text not null default '' check (char_length(telefono) <= 40),
  tel_digitos text generated always as (right(regexp_replace(telefono, '\D', '', 'g'), 10)) stored,
  correo text not null default '' check (char_length(correo) <= 160),
  nacimiento date,
  empresa text not null default '' check (char_length(empresa) <= 120),
  cargo text not null default '' check (char_length(cargo) <= 120),
  ciudad text not null default '' check (char_length(ciudad) <= 120),
  origen text not null default '' check (char_length(origen) <= 160),
  responsable uuid references public.perfiles(id) on delete set null,
  estado text not null default 'sin_contactar' check (estado in
    ('sin_contactar','contacto_inicial','en_conversacion','interesado','seguimiento_pendiente','no_interesado','relacion_activa')),
  proxima_accion text not null default '' check (char_length(proxima_accion) <= 300),
  proxima_fecha date,
  notas text not null default '' check (char_length(notas) <= 4000),
  acepta_correos boolean not null default true,
  acepta_whatsapp boolean not null default true,
  donador boolean not null default false,
  token uuid not null default gen_random_uuid() unique,  -- liga personal: confirmar asistencia y darse de baja
  creado timestamptz not null default now(),
  actualizado timestamptz not null default now(),
  creado_por uuid default auth.uid()
);
create unique index if not exists crm_personas_correo on public.crm_personas (lower(correo)) where correo <> '';
create index if not exists crm_personas_tel on public.crm_personas (tel_digitos);
drop trigger if exists crm_personas_actualizado on public.crm_personas;
create trigger crm_personas_actualizado before update on public.crm_personas for each row execute function public.crm_tocar();

-- ============ Asistencia a cada fecha de un evento ============
create table if not exists public.crm_asistencias (
  id uuid primary key default gen_random_uuid(),
  persona uuid not null references public.crm_personas(id) on delete cascade,
  evento text not null,
  fecha date not null,
  estado text not null default 'registrado' check (estado in ('invitado','registrado','confirmo','asistio','no_asistio','cancelo')),
  origen text not null default 'manual' check (origen in ('formulario','puerta','manual')),
  nota text not null default '' check (char_length(nota) <= 1000),
  creado timestamptz not null default now(),
  actualizado timestamptz not null default now(),
  marcado_por uuid default auth.uid(),
  unique (persona, evento, fecha)
);
create index if not exists crm_asistencias_evento on public.crm_asistencias (evento, fecha);
drop trigger if exists crm_asistencias_actualizado on public.crm_asistencias;
create trigger crm_asistencias_actualizado before update on public.crm_asistencias for each row execute function public.crm_tocar();

-- ============ Seguimiento (historial de conversaciones) ============
create table if not exists public.crm_seguimientos (
  id uuid primary key default gen_random_uuid(),
  persona uuid not null references public.crm_personas(id) on delete cascade,
  fecha timestamptz not null default now(),
  medio text not null default 'whatsapp' check (medio in ('llamada','whatsapp','correo','en_persona','otro','sistema')),
  responsable uuid references public.perfiles(id) on delete set null,
  resumen text not null default '' check (char_length(resumen) <= 4000),
  interes text not null default '' check (char_length(interes) <= 300),
  proxima_accion text not null default '' check (char_length(proxima_accion) <= 300),
  proxima_fecha date,
  estado text,  -- estado al que pasó la persona con esta conversación (si cambió)
  creado timestamptz not null default now(),
  creado_por uuid default auth.uid()
);
create index if not exists crm_seguimientos_persona on public.crm_seguimientos (persona, fecha desc);

-- ============ Donaciones (solo Finanzas, PM y desarrollador) ============
create table if not exists public.crm_donaciones (
  id uuid primary key default gen_random_uuid(),
  persona uuid not null references public.crm_personas(id) on delete cascade,
  monto numeric(12,2) not null check (monto > 0),
  fecha date not null default current_date,
  tipo text not null default 'unica' check (tipo in ('unica','recurrente')),
  destino text not null default '' check (char_length(destino) <= 160),
  metodo text not null default '' check (char_length(metodo) <= 80),
  estado text not null default 'comprometida' check (estado in ('comprometida','recibida','cancelada')),
  evento text not null default '',   -- «<id del evento>|<fecha>» si salió de un evento
  comprobante text not null default '' check (char_length(comprobante) <= 500),
  notas text not null default '' check (char_length(notas) <= 2000),
  creado timestamptz not null default now(),
  actualizado timestamptz not null default now(),
  creado_por uuid default auth.uid()
);
create index if not exists crm_donaciones_persona on public.crm_donaciones (persona);
drop trigger if exists crm_donaciones_actualizado on public.crm_donaciones;
create trigger crm_donaciones_actualizado before update on public.crm_donaciones for each row execute function public.crm_tocar();
-- «Donador» se ve en la persona sin mostrar montos: alguien con al menos una donación recibida
create or replace function public.crm_marcar_donador()
returns trigger language plpgsql security definer set search_path = public as $$
declare p uuid := coalesce(new.persona, old.persona);
begin
  update public.crm_personas set donador = exists (select 1 from public.crm_donaciones d where d.persona = p and d.estado = 'recibida')
   where id = p;
  if tg_op = 'UPDATE' and old.persona <> new.persona then
    update public.crm_personas set donador = exists (select 1 from public.crm_donaciones d where d.persona = old.persona and d.estado = 'recibida')
     where id = old.persona;
  end if;
  return null;
end $$;
drop trigger if exists crm_donaciones_donador on public.crm_donaciones;
create trigger crm_donaciones_donador after insert or update or delete on public.crm_donaciones
  for each row execute function public.crm_marcar_donador();

-- ============ Mensajes (correo y WhatsApp) ============
create table if not exists public.crm_mensajes (
  id uuid primary key default gen_random_uuid(),
  persona uuid references public.crm_personas(id) on delete cascade,
  canal text not null check (canal in ('correo','whatsapp')),
  direccion text not null default 'salida' check (direccion in ('salida','entrada')),
  tipo text not null default '' check (char_length(tipo) <= 40),  -- invitacion15, invitacion7, recordatorio, boletin, texto, respuesta…
  texto text not null default '' check (char_length(texto) <= 4000),
  evento text not null default '',
  fecha_evento date,
  clave text unique,   -- para no mandar dos veces el mismo aviso
  estado text not null default 'enviado' check (char_length(estado) <= 40),
  wa_id text,
  error text not null default '' check (char_length(error) <= 1000),
  creado timestamptz not null default now(),
  creado_por uuid default auth.uid()
);
create index if not exists crm_mensajes_persona on public.crm_mensajes (persona, creado desc);
create index if not exists crm_mensajes_wa on public.crm_mensajes (wa_id) where wa_id is not null;

-- ============ Newsletters ============
create table if not exists public.crm_boletines (
  id uuid primary key default gen_random_uuid(),
  asunto text not null default '' check (char_length(asunto) <= 160),
  titulo text not null default '' check (char_length(titulo) <= 160),
  cuerpo text not null default '' check (char_length(cuerpo) <= 20000),
  imagen text not null default '' check (char_length(imagen) <= 500),
  boton_texto text not null default '' check (char_length(boton_texto) <= 60),
  boton_liga text not null default '' check (char_length(boton_liga) <= 500),
  estado text not null default 'borrador' check (estado in ('borrador','enviando','enviado')),
  enviados int not null default 0,
  total int not null default 0,
  enviado_en timestamptz,
  creado timestamptz not null default now(),
  actualizado timestamptz not null default now(),
  creado_por uuid default auth.uid()
);
drop trigger if exists crm_boletines_actualizado on public.crm_boletines;
create trigger crm_boletines_actualizado before update on public.crm_boletines for each row execute function public.crm_tocar();

-- ============ Permisos ============
-- Operativo (también como área adicional), la PM y el desarrollador: personas, asistencia, seguimiento, mensajes y boletines.
-- Donaciones: solo Finanzas, la PM y el desarrollador. Borrar personas: solo la PM y el desarrollador.
alter table public.crm_personas enable row level security;
alter table public.crm_asistencias enable row level security;
alter table public.crm_seguimientos enable row level security;
alter table public.crm_donaciones enable row level security;
alter table public.crm_mensajes enable row level security;
alter table public.crm_boletines enable row level security;
do $$ declare t text; begin
  foreach t in array array['crm_personas','crm_asistencias','crm_seguimientos','crm_mensajes','crm_boletines'] loop
    execute format('drop policy if exists %1$s_ver on public.%1$s', t);
    execute format('create policy %1$s_ver on public.%1$s for select to authenticated using (public.puede_area(''operativo''))', t);
    execute format('drop policy if exists %1$s_crear on public.%1$s', t);
    execute format('create policy %1$s_crear on public.%1$s for insert to authenticated with check (public.puede_area(''operativo''))', t);
    execute format('drop policy if exists %1$s_editar on public.%1$s', t);
    execute format('create policy %1$s_editar on public.%1$s for update to authenticated using (public.puede_area(''operativo'')) with check (public.puede_area(''operativo''))', t);
    execute format('drop policy if exists %1$s_borrar on public.%1$s', t);
    if t = 'crm_personas' then
      execute format('create policy %1$s_borrar on public.%1$s for delete to authenticated using (public.es_pm())', t);
    else
      execute format('create policy %1$s_borrar on public.%1$s for delete to authenticated using (public.puede_area(''operativo''))', t);
    end if;
  end loop;
end $$;
drop policy if exists crm_donaciones_todo on public.crm_donaciones;
create policy crm_donaciones_todo on public.crm_donaciones for all to authenticated
  using (public.puede_finanzas() or public.es_pm()) with check (public.puede_finanzas() or public.es_pm());

-- ============ Fechas de un evento del calendario ============
-- ¿El evento (data de «eventos») ocurre ese día? Misma regla que ocurrencias() de agenda-reglas.js
create or replace function public.evento_ocurre(d jsonb, f date)
returns boolean language plpgsql immutable as $$
declare ini date; hasta date; rep text := coalesce(d->>'repetir', '');
begin
  begin ini := (d->>'fecha')::date; hasta := nullif(d->>'hasta', '')::date; exception when others then return false; end;
  if ini is null or f < ini then return false; end if;
  if rep <> '' and hasta is not null and f > hasta then return false; end if;
  if coalesce(d->'excepciones', '[]'::jsonb) ? to_char(f, 'YYYY-MM-DD') then return false; end if;
  return case rep
    when '' then f = ini
    when 'semanal' then (f - ini) % 7 = 0
    when 'quincenal' then (f - ini) % 14 = 0
    when 'mensual' then extract(day from f) = extract(day from ini)
    when 'anual' then to_char(f, 'MM-DD') = to_char(ini, 'MM-DD')
    else f = ini end;
end $$;
-- Un evento tiene registro abierto si es cenáculo o si se marcó «registro» en el calendario
create or replace function public.evento_con_registro(d jsonb)
returns boolean language sql immutable as $$
  select d->>'tipo' = 'cenaculo' or coalesce(d->>'registro', '') = 'true';
$$;

-- Eventos con registro abierto (para el formulario público): solo lo necesario para mostrarlos
create or replace function public.registro_eventos()
returns json language sql stable security definer set search_path = public as $$
  select coalesce(json_agg(json_build_object('id', e.id, 'titulo', e.data->>'titulo', 'tipo', e.data->>'tipo',
      'fecha', e.data->>'fecha', 'fin', coalesce(e.data->>'fin', ''), 'hora', coalesce(e.data->>'hora', ''),
      'horaFin', coalesce(e.data->>'horaFin', ''), 'repetir', coalesce(e.data->>'repetir', ''), 'hasta', coalesce(e.data->>'hasta', ''),
      'excepciones', coalesce(e.data->'excepciones', '[]'::jsonb), 'lugar', coalesce(e.data->>'lugar', ''))), '[]'::json)
    from public.eventos e
   where public.evento_con_registro(e.data)
     and ((coalesce(e.data->>'repetir', '') <> '' and coalesce(nullif(e.data->>'hasta', ''), '9999-12-31') >= to_char(current_date, 'YYYY-MM-DD'))
          or (e.data->>'fecha') >= to_char(current_date - 1, 'YYYY-MM-DD'));
$$;
grant execute on function public.registro_eventos() to anon, authenticated;

-- ============ Alta sin duplicados ============
-- Busca por correo; si no, por teléfono (10 dígitos) cuando alguno de los dos no tiene correo. Completa lo que falte.
create or replace function public.crm_guardar_persona(p_nombre text, p_tel text, p_correo text, p_nac date, p_origen text, p_acepta boolean)
returns uuid language plpgsql security definer set search_path = public as $$
declare pid uuid; c text := lower(trim(coalesce(p_correo, ''))); t text := right(regexp_replace(coalesce(p_tel, ''), '\D', '', 'g'), 10);
begin
  if c <> '' then select id into pid from public.crm_personas where lower(correo) = c limit 1; end if;
  if pid is null and char_length(t) = 10 then
    select id into pid from public.crm_personas where tel_digitos = t and (c = '' or correo = '') order by creado limit 1;
  end if;
  if pid is null then
    insert into public.crm_personas (nombre, telefono, correo, nacimiento, origen, acepta_correos, creado_por)
    values (left(trim(p_nombre), 120), left(trim(coalesce(p_tel, '')), 40), left(c, 160), p_nac, left(coalesce(p_origen, ''), 160), coalesce(p_acepta, true), auth.uid())
    returning id into pid;
  else
    update public.crm_personas set
      telefono = case when telefono = '' then left(trim(coalesce(p_tel, '')), 40) else telefono end,
      correo = case when correo = '' then left(c, 160) else correo end,
      nacimiento = coalesce(nacimiento, p_nac),
      acepta_correos = case when p_acepta then true else acepta_correos end
     where id = pid;
  end if;
  return pid;
end $$;
revoke all on function public.crm_guardar_persona(text, text, text, date, text, boolean) from public, anon, authenticated;

-- Registro público a una fecha de un evento (formulario /registro)
create or replace function public.registro_evento(ev text, f date, nombre text, telefono text, correo text, nacimiento date, acepta boolean default true)
returns json language plpgsql security definer set search_path = public as $$
#variable_conflict use_variable
declare e record; pid uuid;
begin
  if coalesce(char_length(trim(nombre)), 0) < 2 then raise exception 'Escribe tu nombre.'; end if;
  if coalesce(trim(correo), '') !~* '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'Revisa tu correo.'; end if;
  if char_length(regexp_replace(coalesce(telefono, ''), '\D', '', 'g')) < 10 then raise exception 'Escribe tu teléfono a 10 dígitos.'; end if;
  if nacimiento is not null and (nacimiento > current_date or nacimiento < date '1900-01-01') then raise exception 'Revisa tu fecha de nacimiento.'; end if;
  select * into e from public.eventos x where x.id = ev;
  if not found or not public.evento_con_registro(e.data) or not public.evento_ocurre(e.data, f) then raise exception 'Este evento ya no tiene registro abierto.'; end if;
  if f < current_date - 1 or f > current_date + 180 then raise exception 'El registro para esa fecha está cerrado.'; end if;
  pid := public.crm_guardar_persona(nombre, telefono, correo, nacimiento, 'Registro: ' || coalesce(e.data->>'titulo', 'evento'), coalesce(acepta, false));
  insert into public.crm_asistencias (persona, evento, fecha, estado, origen, marcado_por) values (pid, ev, f, 'registrado', 'formulario', null)
  on conflict (persona, evento, fecha) do update set estado = case when crm_asistencias.estado in ('invitado','cancelo','no_asistio') then 'registrado' else crm_asistencias.estado end;
  return json_build_object('ok', true, 'titulo', e.data->>'titulo', 'fecha', f, 'hora', coalesce(e.data->>'hora', ''), 'lugar', coalesce(e.data->>'lugar', ''));
end $$;
grant execute on function public.registro_evento(text, date, text, text, text, date, boolean) to anon, authenticated;

-- Alta en la puerta (el mismo día): la registra y la marca como «vino»
create or replace function public.crm_puerta(ev text, f date, nombre text, telefono text, correo text, nacimiento date)
returns uuid language plpgsql security definer set search_path = public as $$
#variable_conflict use_variable
declare pid uuid; titulo text;
begin
  if not public.puede_area('operativo') then raise exception 'Solo Operativo puede pasar lista.'; end if;
  if coalesce(char_length(trim(nombre)), 0) < 2 then raise exception 'Escribe el nombre.'; end if;
  select data->>'titulo' into titulo from public.eventos where id = ev;
  pid := public.crm_guardar_persona(nombre, telefono, correo, nacimiento, 'En la puerta: ' || coalesce(titulo, 'evento'), true);
  insert into public.crm_asistencias (persona, evento, fecha, estado, origen) values (pid, ev, f, 'asistio', 'puerta')
  on conflict (persona, evento, fecha) do update set estado = 'asistio';
  return pid;
end $$;
grant execute on function public.crm_puerta(text, date, text, text, text, date) to authenticated;

-- Liga personal (en correos y WhatsApp): r = 'info' (solo ver), 'registrar', 'si' (confirma), 'no' (cancela)
create or replace function public.crm_responder(t uuid, ev text, f date, r text default 'info')
returns json language plpgsql security definer set search_path = public as $$
#variable_conflict use_variable
declare p record; e record; a record; nuevo text;
begin
  select * into p from public.crm_personas where token = t;
  if not found then raise exception 'Esta liga no es válida.'; end if;
  select * into e from public.eventos x where x.id = ev;
  if not found or not public.evento_ocurre(e.data, f) then raise exception 'No encontramos ese evento.'; end if;
  select * into a from public.crm_asistencias x where x.persona = p.id and x.evento = ev and x.fecha = f;
  if r in ('registrar','si','no') then
    if f < current_date then raise exception 'Ese evento ya pasó.'; end if;
    nuevo := case r when 'no' then 'cancelo' when 'si' then 'confirmo' else 'registrado' end;
    if a.id is null then
      if not public.evento_con_registro(e.data) then raise exception 'Este evento no tiene registro abierto.'; end if;
      insert into public.crm_asistencias (persona, evento, fecha, estado, origen, marcado_por) values (p.id, ev, f, nuevo, 'formulario', null);
    elsif not (r = 'registrar' and a.estado in ('confirmo','asistio')) then
      update public.crm_asistencias set estado = nuevo where id = a.id;
    end if;
    insert into public.crm_mensajes (persona, canal, direccion, tipo, texto, evento, fecha_evento, creado_por)
    values (p.id, 'correo', 'entrada', 'respuesta', case r when 'no' then 'No podrá ir (desde su liga)' when 'si' then 'Confirmó que sí va (desde su liga)' else 'Se registró desde su liga' end, ev, f, null);
    select * into a from public.crm_asistencias x where x.persona = p.id and x.evento = ev and x.fecha = f;
  end if;
  return json_build_object('nombre', split_part(p.nombre, ' ', 1), 'titulo', e.data->>'titulo', 'fecha', f,
    'hora', coalesce(e.data->>'hora', ''), 'lugar', coalesce(e.data->>'lugar', ''), 'estado', a.estado);
end $$;
grant execute on function public.crm_responder(uuid, text, date, text) to anon, authenticated;

-- Darse de baja de los correos (liga al pie de cada correo)
create or replace function public.crm_baja(t uuid)
returns json language plpgsql security definer set search_path = public as $$
declare n text;
begin
  update public.crm_personas set acepta_correos = false where token = t returning split_part(nombre, ' ', 1) into n;
  if n is null then raise exception 'Esta liga no es válida.'; end if;
  return json_build_object('ok', true, 'nombre', n);
end $$;
grant execute on function public.crm_baja(uuid) to anon, authenticated;

do $$ begin alter publication supabase_realtime add table public.crm_personas; exception when duplicate_object then null; end $$;
do $$ begin alter publication supabase_realtime add table public.crm_asistencias; exception when duplicate_object then null; end $$;
do $$ begin alter publication supabase_realtime add table public.crm_seguimientos; exception when duplicate_object then null; end $$;
do $$ begin alter publication supabase_realtime add table public.crm_donaciones; exception when duplicate_object then null; end $$;
do $$ begin alter publication supabase_realtime add table public.crm_mensajes; exception when duplicate_object then null; end $$;

-- ============ Envíos automáticos (Edge Function «crm», cada día a las 9:00 de México) ============
select cron.unschedule('bitacora-crm') where exists (select 1 from cron.job where jobname = 'bitacora-crm');
select cron.schedule(
  'bitacora-crm',
  '0 15 * * *',
  $$
  select net.http_post(
    url := 'https://zhzqvetehynndfjbrzti.supabase.co/functions/v1/crm',
    headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InpoenF2ZXRlaHlubmRmamJyenRpIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTM3Mjc3NjgsImV4cCI6MjEwOTMwMzc2OH0.ZhsazISy5Azt7i14qFeHKjcSPNQzXJeeAGcPAoEzjqw'),
    body := '{"accion":"diario"}'::jsonb,
    timeout_milliseconds := 120000
  );
  $$
);

insert into public.migraciones_aplicadas (nombre) values ('027_personas_y_eventos') on conflict (nombre) do nothing;

-- ============ Migración 028 ============
-- Bitácora Tiempo de Dios · migración 028: donaciones recibidas en Finanzas y archivos en Sugerencias
-- 1) Las donaciones recibidas viven en Finanzas.
-- Finanzas (tabla «ingresos») es la fuente única del dinero que entra. Una donación de Personas
-- (crm_donaciones) es el compromiso; cuando se recibe, queda ligada a su ingreso en Finanzas
-- (columna «ingreso») y el monto que cuenta es el de ese ingreso. No se duplica nada.
-- · Una donación solo puede pasar a «recibida» si tiene su ingreso ligado.
-- · Si en Finanzas se borra el ingreso, la donación regresa sola a «comprometida».
-- · Un ingreso se liga a una sola donación.
-- No cambia nada de las tablas de Finanzas.
-- Ejecútala una vez en Supabase → SQL Editor → Run. Se puede volver a correr sin error.

alter table public.crm_donaciones add column if not exists ingreso uuid references public.ingresos(id) on delete set null;
create unique index if not exists crm_donaciones_ingreso on public.crm_donaciones (ingreso) where ingreso is not null;

create or replace function public.crm_donacion_coherente()
returns trigger language plpgsql as $$
begin
  -- se borró (o se desligó) el ingreso en Finanzas: la donación vuelve a estar comprometida
  if tg_op = 'UPDATE' and old.ingreso is not null and new.ingreso is null and new.estado = 'recibida' then
    new.estado := 'comprometida';
  end if;
  -- para estar «recibida» tiene que estar registrada en Finanzas
  if new.estado = 'recibida' and new.ingreso is null and (tg_op = 'INSERT' or old.estado is distinct from 'recibida') then
    raise exception 'Una donación recibida se registra como ingreso en Finanzas: liga su ingreso.';
  end if;
  return new;
end $$;
drop trigger if exists crm_donaciones_coherente on public.crm_donaciones;
create trigger crm_donaciones_coherente before insert or update on public.crm_donaciones
  for each row execute function public.crm_donacion_coherente();

-- 2) Sugerencias con archivos (capturas, documentos, .zip con prompts). Bucket privado «sugerencias»,
--    ruta <usuario>/<sugerencia>/<archivo>, máx. 50 MB por archivo. Todo el equipo los puede abrir.
alter table public.sugerencias add column if not exists archivos jsonb not null default '[]'::jsonb check (pg_column_size(archivos) < 20000);
insert into storage.buckets (id, name, public, file_size_limit) values ('sugerencias', 'sugerencias', false, 52428800)
on conflict (id) do update set public = false, file_size_limit = excluded.file_size_limit;
drop policy if exists sugerencias_archivos_leer on storage.objects;
create policy sugerencias_archivos_leer on storage.objects for select to authenticated using (bucket_id = 'sugerencias');
drop policy if exists sugerencias_archivos_subir on storage.objects;
create policy sugerencias_archivos_subir on storage.objects for insert to authenticated
  with check (bucket_id = 'sugerencias' and (storage.foldername(name))[1] = auth.uid()::text);
drop policy if exists sugerencias_archivos_borrar on storage.objects;
create policy sugerencias_archivos_borrar on storage.objects for delete to authenticated
  using (bucket_id = 'sugerencias' and ((storage.foldername(name))[1] = auth.uid()::text or public.es_pm()));

insert into public.migraciones_aplicadas (nombre) values ('028_donaciones_finanzas_y_adjuntos') on conflict (nombre) do nothing;

-- ============ Migración 029 ============
-- Bitácora Tiempo de Dios · migración 029: «Ya he ido a un cenáculo» en el registro público
-- Quien ya está en la base busca su nombre, confirma que es él o ella con su teléfono (o correo)
-- y queda registrado sin volver a escribir sus datos.
-- · registro_buscar(q): mínimo 3 letras, máximo 6 resultados y solo nombre + inicial del apellido
--   y los 2 últimos dígitos del teléfono (no expone datos de contacto).
-- · registro_rapido(p, dato, ev, f): registra solo si el teléfono (10 dígitos) o el correo coinciden.
-- Ejecútala una vez en Supabase → SQL Editor → Run. Se puede volver a correr sin error.

create or replace function public.texto_simple(t text)
returns text language sql immutable as $$
  select lower(translate(coalesce(t, ''), 'áéíóúüñÁÉÍÓÚÜÑàèìòùÀÈÌÒÙ', 'aeiouunAEIOUUNaeiouAEIOU'));
$$;

create or replace function public.registro_buscar(q text)
returns json language plpgsql stable security definer set search_path = public as $$
declare b text := public.texto_simple(trim(q));
begin
  if char_length(b) < 3 then return '[]'::json; end if;
  return coalesce((select json_agg(x) from (
    select p.id as ref,
           split_part(trim(p.nombre), ' ', 1) || coalesce(' ' || nullif(left(split_part(trim(p.nombre), ' ', 2), 1), '') || '.', '') as nombre,
           case when char_length(p.tel_digitos) = 10 then right(p.tel_digitos, 2) else '' end as tel,
           p.correo <> '' as con_correo
      from public.crm_personas p
     where public.texto_simple(p.nombre) like '%' || b || '%'
     order by p.actualizado desc
     limit 6) x), '[]'::json);
end $$;
grant execute on function public.registro_buscar(text) to anon, authenticated;

create or replace function public.registro_rapido(p uuid, dato text, ev text, f date)
returns json language plpgsql security definer set search_path = public as $$
#variable_conflict use_variable
declare per record; e record; d text := trim(coalesce(dato, '')); dig text := right(regexp_replace(coalesce(dato, ''), '\D', '', 'g'), 10);
begin
  select * into per from public.crm_personas where id = p;
  if not found then raise exception 'No te encontramos. Regístrate con tus datos.'; end if;
  if not ((char_length(dig) = 10 and per.tel_digitos = dig) or (d like '%@%' and lower(per.correo) = lower(d))) then
    raise exception 'Ese teléfono o correo no coincide con el que tenemos. Revísalo o regístrate con tus datos.';
  end if;
  select * into e from public.eventos x where x.id = ev;
  if not found or not public.evento_con_registro(e.data) or not public.evento_ocurre(e.data, f) then raise exception 'Este evento ya no tiene registro abierto.'; end if;
  if f < current_date - 1 or f > current_date + 180 then raise exception 'El registro para esa fecha está cerrado.'; end if;
  insert into public.crm_asistencias (persona, evento, fecha, estado, origen, marcado_por) values (per.id, ev, f, 'registrado', 'formulario', null)
  on conflict (persona, evento, fecha) do update set estado = case when crm_asistencias.estado in ('invitado','cancelo','no_asistio') then 'registrado' else crm_asistencias.estado end;
  return json_build_object('ok', true, 'nombre', split_part(trim(per.nombre), ' ', 1));
end $$;
grant execute on function public.registro_rapido(uuid, text, text, date) to anon, authenticated;

insert into public.migraciones_aplicadas (nombre) values ('029_registro_rapido') on conflict (nombre) do nothing;

-- ============ Migración 030 ============
-- Bitácora Tiempo de Dios · migración 030: «¿Cómo te enteraste?» y quién invitó
-- · Cada registro a un cenáculo o evento guarda por qué medio llegó la persona (crm_asistencias.medio:
--   invitacion, instagram, facebook, tiktok, whatsapp, correo, parroquia u otro) y, si alguien la invitó,
--   quién (crm_asistencias.referido → crm_referidos).
-- · crm_referidos unifica los nombres de quien invita: «ricarDo Bañuelos Sanches» y «Ricardo Bañuelos Sánchez»
--   quedan como la misma persona (sin importar mayúsculas, acentos y pequeñas diferencias de escritura, con pg_trgm)
--   y se muestra siempre la forma mejor escrita (con acentos y con mayúscula inicial). Si Operativo corrige el
--   nombre a mano, se queda así (fijo).
-- · registro_evento, registro_rapido y crm_puerta reciben el medio y quién invitó.
-- Requiere la 029. Ejecútala una vez en Supabase → SQL Editor → Run. Se puede volver a correr sin error.

create extension if not exists pg_trgm with schema extensions;

create or replace function public.texto_simple(t text)
returns text language sql immutable as $$
  select lower(translate(coalesce(t, ''), 'áéíóúüñÁÉÍÓÚÜÑàèìòùÀÈÌÒÙ', 'aeiouunAEIOUUNaeiouAEIOU'));
$$;
-- Clave para comparar nombres: sin acentos, en minúsculas y con espacios sencillos
create or replace function public.nombre_clave(t text)
returns text language sql immutable as $$
  select trim(regexp_replace(public.texto_simple(t), '\s+', ' ', 'g'));
$$;
-- Qué tan bien escrito está un nombre: acentos o ñ, mayúscula inicial en cada palabra y no todo en mayúsculas
create or replace function public.nombre_puntaje(t text)
returns int language sql immutable as $$
  select (case when t ~ '[áéíóúüñÁÉÍÓÚÜÑ]' then 3 else 0 end)
       + (case when t = initcap(t) then 2 else 0 end)
       + (case when t <> upper(t) and t <> lower(t) then 1 else 0 end);
$$;

create table if not exists public.crm_referidos (
  id uuid primary key default gen_random_uuid(),
  nombre text not null check (char_length(nombre) between 2 and 120),
  clave text not null unique,
  variantes jsonb not null default '{}'::jsonb,   -- {«como lo escribieron»: veces}
  veces int not null default 0,
  fijo boolean not null default false,             -- Operativo corrigió el nombre a mano
  creado timestamptz not null default now(),
  actualizado timestamptz not null default now()
);
drop trigger if exists crm_referidos_actualizado on public.crm_referidos;
create trigger crm_referidos_actualizado before update on public.crm_referidos for each row execute function public.crm_tocar();
alter table public.crm_referidos enable row level security;
drop policy if exists crm_referidos_operativo on public.crm_referidos;
create policy crm_referidos_operativo on public.crm_referidos for all to authenticated
  using (public.puede_area('operativo')) with check (public.puede_area('operativo'));

alter table public.crm_asistencias add column if not exists medio text not null default '' check (char_length(medio) <= 40);
alter table public.crm_asistencias add column if not exists medio_otro text not null default '' check (char_length(medio_otro) <= 120);
alter table public.crm_asistencias add column if not exists referido uuid references public.crm_referidos(id) on delete set null;
alter table public.crm_personas add column if not exists referido uuid references public.crm_referidos(id) on delete set null;

-- Encuentra (o crea) a quien invita y suma esta forma de escribirlo
create or replace function public.crm_referido(t text)
returns uuid language plpgsql security definer set search_path = public, extensions as $$
declare v text := left(trim(regexp_replace(coalesce(t, ''), '\s+', ' ', 'g')), 120); c text; rid uuid; r record; mejor text;
begin
  if char_length(v) < 3 then return null; end if;
  c := public.nombre_clave(v);
  select id into rid from public.crm_referidos where clave = c;
  if rid is null then
    select id into rid from public.crm_referidos where similarity(clave, c) >= 0.55 order by similarity(clave, c) desc limit 1;
  end if;
  if rid is null then
    insert into public.crm_referidos (nombre, clave, variantes, veces)
    values (case when public.nombre_puntaje(v) >= 3 then v else initcap(v) end, c, jsonb_build_object(v, 1), 1)
    on conflict (clave) do update set veces = crm_referidos.veces + 1
    returning id into rid;
    return rid;
  end if;
  update public.crm_referidos set variantes = variantes || jsonb_build_object(v, coalesce((variantes->>v)::int, 0) + 1), veces = veces + 1
   where id = rid returning * into r;
  if not r.fijo then
    select key into mejor from jsonb_each_text(r.variantes) order by public.nombre_puntaje(key) desc, value::int desc, char_length(key) desc limit 1;
    update public.crm_referidos set nombre = case when public.nombre_puntaje(mejor) >= 3 then mejor else initcap(mejor) end where id = rid;
  end if;
  return rid;
end $$;
revoke all on function public.crm_referido(text) from public, anon, authenticated;

-- Para el formulario: nombres de quien invita que coinciden (mín. 3 letras, máx. 5)
create or replace function public.registro_invitan(q text)
returns json language sql stable security definer set search_path = public, extensions as $$
  select coalesce(json_agg(nombre), '[]'::json) from (
    select nombre from public.crm_referidos
     where char_length(public.nombre_clave(q)) >= 3
       and (clave like '%' || public.nombre_clave(q) || '%' or similarity(clave, public.nombre_clave(q)) >= 0.4)
     order by veces desc limit 5) x;
$$;
grant execute on function public.registro_invitan(text) to anon, authenticated;

-- Guarda el medio en una asistencia (y quién invitó)
create or replace function public.crm_medio(a uuid, medio text, quien text)
returns void language plpgsql security definer set search_path = public as $$
#variable_conflict use_variable
declare m text := lower(trim(coalesce(medio, ''))); rid uuid; pid uuid;
begin
  if m = '' then return; end if;
  if m not in ('invitacion','instagram','facebook','tiktok','whatsapp','correo','parroquia','otro') then m := 'otro'; end if;
  if m = 'invitacion' then rid := public.crm_referido(quien); end if;
  update public.crm_asistencias set medio = m, referido = coalesce(rid, referido),
         medio_otro = case when m = 'otro' then left(trim(coalesce(quien, '')), 120) else '' end
   where id = a returning persona into pid;
  if rid is not null then update public.crm_personas set referido = rid where id = pid and referido is null; end if;
end $$;
revoke all on function public.crm_medio(uuid, text, text) from public, anon, authenticated;

-- Registro público (con medio)
drop function if exists public.registro_evento(text, date, text, text, text, date, boolean);
create or replace function public.registro_evento(ev text, f date, nombre text, telefono text, correo text, nacimiento date,
  acepta boolean default true, medio text default '', quien text default '')
returns json language plpgsql security definer set search_path = public as $$
#variable_conflict use_variable
declare e record; pid uuid; aid uuid;
begin
  if coalesce(char_length(trim(nombre)), 0) < 2 then raise exception 'Escribe tu nombre.'; end if;
  if coalesce(trim(correo), '') !~* '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'Revisa tu correo.'; end if;
  if char_length(regexp_replace(coalesce(telefono, ''), '\D', '', 'g')) < 10 then raise exception 'Escribe tu teléfono a 10 dígitos.'; end if;
  if nacimiento is null or nacimiento > current_date or nacimiento < date '1900-01-01' then raise exception 'Revisa tu fecha de nacimiento.'; end if;
  if coalesce(trim(medio), '') = '' then raise exception 'Cuéntanos cómo te enteraste.'; end if;
  if medio = 'invitacion' and char_length(trim(coalesce(quien, ''))) < 3 then raise exception 'Escribe el nombre de quien te invitó.'; end if;
  select * into e from public.eventos x where x.id = ev;
  if not found or not public.evento_con_registro(e.data) or not public.evento_ocurre(e.data, f) then raise exception 'Este evento ya no tiene registro abierto.'; end if;
  if f < current_date - 1 or f > current_date + 180 then raise exception 'El registro para esa fecha está cerrado.'; end if;
  pid := public.crm_guardar_persona(nombre, telefono, correo, nacimiento, 'Registro: ' || coalesce(e.data->>'titulo', 'evento'), coalesce(acepta, false));
  insert into public.crm_asistencias (persona, evento, fecha, estado, origen, marcado_por) values (pid, ev, f, 'registrado', 'formulario', null)
  on conflict (persona, evento, fecha) do update set estado = case when crm_asistencias.estado in ('invitado','cancelo','no_asistio') then 'registrado' else crm_asistencias.estado end
  returning id into aid;
  perform public.crm_medio(aid, medio, quien);
  return json_build_object('ok', true, 'titulo', e.data->>'titulo', 'fecha', f, 'hora', coalesce(e.data->>'hora', ''), 'lugar', coalesce(e.data->>'lugar', ''));
end $$;
grant execute on function public.registro_evento(text, date, text, text, text, date, boolean, text, text) to anon, authenticated;

-- «Ya he ido a un cenáculo» (con medio)
drop function if exists public.registro_rapido(uuid, text, text, date);
create or replace function public.registro_rapido(p uuid, dato text, ev text, f date, medio text default '', quien text default '')
returns json language plpgsql security definer set search_path = public as $$
#variable_conflict use_variable
declare per record; e record; aid uuid; d text := trim(coalesce(dato, '')); dig text := right(regexp_replace(coalesce(dato, ''), '\D', '', 'g'), 10);
begin
  select * into per from public.crm_personas where id = p;
  if not found then raise exception 'No te encontramos. Regístrate con tus datos.'; end if;
  if not ((char_length(dig) = 10 and per.tel_digitos = dig) or (d like '%@%' and lower(per.correo) = lower(d))) then
    raise exception 'Ese teléfono o correo no coincide con el que tenemos. Revísalo o regístrate con tus datos.';
  end if;
  if coalesce(trim(medio), '') = '' then raise exception 'Cuéntanos cómo te enteraste.'; end if;
  if medio = 'invitacion' and char_length(trim(coalesce(quien, ''))) < 3 then raise exception 'Escribe el nombre de quien te invitó.'; end if;
  select * into e from public.eventos x where x.id = ev;
  if not found or not public.evento_con_registro(e.data) or not public.evento_ocurre(e.data, f) then raise exception 'Este evento ya no tiene registro abierto.'; end if;
  if f < current_date - 1 or f > current_date + 180 then raise exception 'El registro para esa fecha está cerrado.'; end if;
  insert into public.crm_asistencias (persona, evento, fecha, estado, origen, marcado_por) values (per.id, ev, f, 'registrado', 'formulario', null)
  on conflict (persona, evento, fecha) do update set estado = case when crm_asistencias.estado in ('invitado','cancelo','no_asistio') then 'registrado' else crm_asistencias.estado end
  returning id into aid;
  perform public.crm_medio(aid, medio, quien);
  return json_build_object('ok', true, 'nombre', split_part(trim(per.nombre), ' ', 1));
end $$;
grant execute on function public.registro_rapido(uuid, text, text, date, text, text) to anon, authenticated;

-- Alta en la puerta (con medio)
drop function if exists public.crm_puerta(text, date, text, text, text, date);
create or replace function public.crm_puerta(ev text, f date, nombre text, telefono text, correo text, nacimiento date,
  medio text default '', quien text default '')
returns uuid language plpgsql security definer set search_path = public as $$
#variable_conflict use_variable
declare pid uuid; aid uuid; titulo text;
begin
  if not public.puede_area('operativo') then raise exception 'Solo Operativo puede pasar lista.'; end if;
  if coalesce(char_length(trim(nombre)), 0) < 2 then raise exception 'Escribe el nombre.'; end if;
  select data->>'titulo' into titulo from public.eventos where id = ev;
  pid := public.crm_guardar_persona(nombre, telefono, correo, nacimiento, 'En la puerta: ' || coalesce(titulo, 'evento'), true);
  insert into public.crm_asistencias (persona, evento, fecha, estado, origen) values (pid, ev, f, 'asistio', 'puerta')
  on conflict (persona, evento, fecha) do update set estado = 'asistio'
  returning id into aid;
  perform public.crm_medio(aid, medio, quien);
  return pid;
end $$;
grant execute on function public.crm_puerta(text, date, text, text, text, date, text, text) to authenticated;

do $$ begin alter publication supabase_realtime add table public.crm_referidos; exception when duplicate_object then null; end $$;

insert into public.migraciones_aplicadas (nombre) values ('030_como_se_entero') on conflict (nombre) do nothing;

-- ============ Migración 031 ============
-- Bitácora Tiempo de Dios · migración 031: Formación → Proyectos (planeación en 6 pasos)
-- Viene del paquete «modulo-proyectos-tdd» (03-proyectos.sql + 04-datos-iniciales-proyectos.sql), adaptado:
-- · Permisos con puede_area(area): la PM, el desarrollador y quien está en el área (también como área adicional).
-- · Los datos del piloto (Eleva tu música, Plataforma de formación, Cursos masivos de formación y el equipo
--   guardado «Equipo base») se cargan solo si no existen: volver a correrla no borra cambios.
-- Ejecútala una vez en Supabase → SQL Editor → Run. Se puede volver a correr sin error.


create table if not exists public.proyectos (
  id text primary key,
  area text not null default 'formacion' check (area in ('formacion','musica','audiovisual','operativo','legal','marketing')),
  data jsonb not null check (pg_column_size(data) < 900000),
  actualizado timestamptz not null default now(),
  actualizado_por uuid default auth.uid()
);

alter table public.proyectos drop constraint if exists proyectos_area_check;
alter table public.proyectos add constraint proyectos_area_check check (area in ('formacion','musica','audiovisual','operativo','legal','marketing'));
drop trigger if exists proyectos_actualizado on public.proyectos;
create trigger proyectos_actualizado before update on public.proyectos
for each row execute function public.marcar_actualizado();

alter table public.proyectos enable row level security;

-- Todos con sesión los ven; editan la PM y el equipo del área del proyecto
drop policy if exists proyectos_leer on public.proyectos;
create policy proyectos_leer on public.proyectos for select to authenticated using (true);
drop policy if exists proyectos_escribir on public.proyectos;
create policy proyectos_escribir on public.proyectos for all to authenticated
  using (public.puede_area(area))
  with check (public.puede_area(area));

do $$ begin
  alter publication supabase_realtime add table public.proyectos;
exception when duplicate_object then null; end $$;

-- ============ Equipos guardados ============
-- Equipos que se reutilizan entre proyectos (Charter → Equipos guardados).
create table if not exists public.equipos (
  id text primary key,
  area text not null default 'formacion' check (area in ('formacion','musica','audiovisual','operativo','legal','marketing')),
  data jsonb not null,
  actualizado timestamptz not null default now(),
  actualizado_por uuid default auth.uid()
);
alter table public.equipos drop constraint if exists equipos_area_check;
alter table public.equipos add constraint equipos_area_check check (area in ('formacion','musica','audiovisual','operativo','legal','marketing'));
drop trigger if exists equipos_actualizado on public.equipos;
create trigger equipos_actualizado before update on public.equipos
for each row execute function public.marcar_actualizado();
alter table public.equipos enable row level security;
drop policy if exists equipos_leer on public.equipos;
create policy equipos_leer on public.equipos for select to authenticated using (true);
drop policy if exists equipos_escribir on public.equipos;
create policy equipos_escribir on public.equipos for all to authenticated
  using (public.puede_area(area))
  with check (public.puede_area(area));
do $$ begin
  alter publication supabase_realtime add table public.equipos;
exception when duplicate_object then null; end $$;

-- ============ Eventos de los proyectos (para el calendario) ============
-- Cada proyecto marcado como evento en su Project Charter aparece aquí como una fila.
-- El calendario de la Bitácora puede leer esta vista directamente.
create or replace view public.eventos_proyectos with (security_invoker = true) as
select
  p.id                                         as proyecto_id,
  p.area,
  p.data->>'nombre'                            as titulo,
  (p.data->'charter'->>'eventoInicio')::date   as inicio,
  coalesce(nullif(p.data->'charter'->>'eventoFin','')::date,
           (p.data->'charter'->>'eventoInicio')::date) as fin,
  nullif(p.data->'charter'->>'eventoLugar','')   as lugar,
  nullif(p.data->'charter'->>'eventoHorario','') as horario,
  p.actualizado
from public.proyectos p
where (p.data->'charter'->>'esEvento')::boolean is true
  and nullif(p.data->'charter'->>'eventoInicio','') is not null;

grant select on public.eventos_proyectos to authenticated;

-- ============ Datos del piloto ============
insert into public.proyectos (id, area, data) values
('cursos-masivos-de-formacion', 'formacion', $tdd${"area": "formacion", "charter": {}, "cierre": {"objetivos": {}}, "creado": "2026-11-19T22:00:02.000Z", "equipo": [], "indicadores": [], "items": [], "nombre": "Cursos masivos de formación"}$tdd$::jsonb),
('eleva-tu-musica', 'formacion', $tdd${"actualizado": "2026-11-20T16:39:23.000Z", "area": "formacion", "charter": {"beneficiarios": "A los músicos o ministerios de música con un proyecto de evangelización que están en proceso de profesionalización. ", "entregablesClave": "Campamento de 1 fin de semana jueves a domingo", "esEvento": true, "eventoFin": "2027-10-17", "eventoHorario": "jueves 2 pm a domingo 3 pm", "eventoInicio": "2027-10-08", "eventoLugar": "Tapalpa, Guadalajara", "excluye": "1. Transporte del aeropuerto al punto de reunión. \n2. Vuelos o traslados para llegar a la sede. \n3. Hospedaje del domingo. ", "exito": "Si llenamos el cupo del campamento, con el nivel de satisfacción de los ministerios que asistan, si salen o no prospectos para el colectivo de Tiempo de Dios. ", "fin": "2027-10-29", "guardado": "2026-11-20T15:52:46.428Z", "incluye": "1. Hospedaje\n2. Alimentación\n3. Transporte \n4. Instrumentos y equipo de audio\n5. Materiales\n6. Actividades creativas\n7. Mentorías\n", "inicio": "2027-01-11", "lider": "Ceci Gómez", "listo": true, "objetivo": "Ser un campamento experiencial, en el que músicos o ministerios de música con proyectos de evangelización puedan continuar su profesionalización y hacer comunidad entre ellos. ", "objetivosEsp": "1. Crear comunidad entre músicos que están en un camino de profesionalización. \n2. Encontrar ministerios de música que puedan empezar un proceso de acompañamiento para discernir si podrían formar parte del colectivo. ", "patrocinador": "", "presupuesto": "", "proposito": "El ETM existe como un semillero para hacer comunidad con posibles músicos o ministerio de evangelización que puedan participar en el colectivo de Tiempo de Dios, es decir, que puedan comenzar el proceso de discernimiento y empezar a formarse para eventualmente poder producir música y videos y colaborar con Tiempo de Dios. ", "riesgos": "Que los ministerios de música no puedan asistir ese fin de semana, que los costos sean demasiado altos. ", "supuestos": "Que va a haber ministerios de música interesados en asistir. "}, "cierre": {"cerrado": false, "objetivos": {}}, "creado": "2026-11-19T22:00:00.000Z", "equipo": [{"id": "fmohus2f0tcl", "nombre": "Ceci Gómez", "rol": "Project Manager"}, {"id": "gc3d9ivv1hlq", "nombre": "Rosy Ruesga", "rol": "Seguimiento músicos", "roles": ["Seguimiento músicos"]}, {"id": "4onj0g1p1x7a", "nombre": "Diego Suárez", "rol": "Desarrollador web, Formador", "roles": ["Desarrollador web", "Formador"]}, {"id": "6hat8jti60jw", "nombre": "Memo Reyes", "rol": "Formador", "roles": ["Formador"]}, {"id": "ejfua4wd6pgm", "nombre": "Ale Suárez", "rol": "Formadora, Diseñadora instruccional", "roles": ["Formadora", "Diseñadora instruccional"]}, {"id": "sz0bhb8e6xb1", "nombre": "Ariel González", "rol": "Formador", "roles": ["Formador"]}, {"id": "qm4901l38a2m", "nombre": "Willy Gálvez", "rol": "Coordinador audiovisual", "roles": ["Coordinador audiovisual"]}, {"id": "zgjqu0xn8icc", "nombre": "Karla Flores", "rol": "Formadora, Seguimiento formadores", "roles": ["Formadora", "Seguimiento formadores"]}, {"id": "dpibwu7h2cgq", "nombre": "Ricardo Bañuelos", "rol": "Finanzas", "roles": ["Finanzas"]}], "indicadores": [{"actual": 3, "id": "a16uklierhd5", "meta": "", "nombre": "", "unidad": ""}, {"actual": "", "id": "tdm51r3aeiiz", "meta": "", "nombre": "", "unidad": ""}], "items": [{"estado": "pendiente", "id": "wblr926o8cy8", "nombre": "Definición del evento", "parent": null, "raci": {}}, {"estado": "pendiente", "fin": "2027-01-22", "hito": false, "id": "tu0xemu1oi2a", "ini": "2027-01-11", "nombre": "Confirmar fecha exacta y sede del Eleva", "parent": "wblr926o8cy8", "raci": {}}, {"estado": "pendiente", "fin": "2027-01-22", "hito": false, "id": "wn10740ypbrm", "ini": "2027-01-11", "nombre": "Definir cupo y perfil de los asistentes", "parent": "wblr926o8cy8", "raci": {}}, {"estado": "pendiente", "id": "0yoxk0tfouvd", "nombre": "Diseño de la experiencia ETM", "parent": null, "raci": {}}, {"estado": "pendiente", "fin": "2027-02-05", "hito": false, "id": "q9dk5d7jp0np", "ini": "2027-01-25", "nombre": "Diagnóstico de necesidades formativas y experienciales", "parent": "0yoxk0tfouvd", "raci": {"4onj0g1p1x7a": "I", "ejfua4wd6pgm": "R", "fmohus2f0tcl": "A", "gc3d9ivv1hlq": "R"}}, {"estado": "pendiente", "fin": "2027-02-19", "hito": false, "id": "xfguuh7cp42u", "ini": "2027-02-08", "nombre": "Diseño propuesta de actividades", "parent": "0yoxk0tfouvd", "raci": {"ejfua4wd6pgm": "R", "fmohus2f0tcl": "R"}}, {"estado": "pendiente", "fin": "2027-03-05", "hito": false, "id": "hy3nefpgp736", "ini": "2027-02-22", "nombre": "Propuesta de itinerario", "parent": "0yoxk0tfouvd", "raci": {"fmohus2f0tcl": "R"}}, {"estado": "pendiente", "id": "p71gezjv9eyz", "nombre": "Formadores y mentorías", "parent": null, "raci": {}}, {"estado": "pendiente", "fin": "2027-02-19", "hito": false, "id": "5hg9zxdtb9jc", "ini": "2027-02-08", "nombre": "Contactar formadores", "parent": "p71gezjv9eyz", "raci": {}}, {"estado": "pendiente", "fin": "2027-05-14", "hito": false, "id": "3cgx4czcc63i", "ini": "2027-04-19", "nombre": "Guiones instruccionales o planeaciones de temas", "parent": "p71gezjv9eyz", "raci": {}}, {"estado": "pendiente", "fin": "2027-06-25", "hito": false, "id": "u0dy27zaaamx", "ini": "2027-05-31", "nombre": "Diseño de material formativo para las mentorías y master classes", "parent": "p71gezjv9eyz", "raci": {}}, {"estado": "pendiente", "id": "4g00hra5dcip", "nombre": "Convocatoria y selección de ministerios", "parent": null, "raci": {}}, {"estado": "pendiente", "fin": "2027-03-05", "hito": false, "id": "9k3v22ixe9ta", "ini": "2027-02-22", "nombre": "Definir criterios de elección de ministerios", "parent": "4g00hra5dcip", "raci": {}}, {"estado": "pendiente", "fin": "2027-03-19", "hito": false, "id": "lbspb91pehf9", "ini": "2027-03-08", "nombre": "Definir comité de selección de ministerios", "parent": "4g00hra5dcip", "raci": {}}, {"estado": "pendiente", "fin": "2027-04-02", "hito": false, "id": "ve3cbl2yesih", "ini": "2027-03-22", "nombre": "Evaluar si es necesario un curso de estandarización en la plataforma", "parent": "4g00hra5dcip", "raci": {}}, {"estado": "pendiente", "fin": "2027-04-16", "hito": false, "id": "9qjasfnefnzb", "ini": "2027-04-05", "nombre": "Crear espacio en la plataforma para la aplicación de ministerios", "parent": "4g00hra5dcip", "raci": {}}, {"estado": "pendiente", "fin": "2027-04-30", "hito": false, "id": "jzzn1zmxfwmf", "ini": "2027-04-19", "nombre": "Definir periodo para aplicar", "parent": "4g00hra5dcip", "raci": {}}, {"estado": "pendiente", "fin": "2027-05-17", "hito": true, "id": "rx0pb8fei25t", "ini": "2027-05-17", "nombre": "Abrir convocatoria", "parent": "4g00hra5dcip", "raci": {}}, {"estado": "pendiente", "fin": "2027-07-02", "hito": true, "id": "9w3xbputg939", "ini": "2027-07-02", "nombre": "Cerrar aplicaciones", "parent": "4g00hra5dcip", "raci": {}}, {"estado": "pendiente", "fin": "2027-07-23", "hito": false, "id": "2wi8khjsgcm0", "ini": "2027-07-12", "nombre": "Evaluar aplicaciones", "parent": "4g00hra5dcip", "raci": {}}, {"estado": "pendiente", "id": "75bjopy8o9q0", "nombre": "Campaña de difusión", "parent": null, "raci": {}}, {"estado": "pendiente", "fin": "2027-03-19", "hito": false, "id": "a1zn5qjsbzqt", "ini": "2027-03-08", "nombre": "Objetivos específicos de comunicación", "parent": "75bjopy8o9q0", "raci": {"fmohus2f0tcl": "A", "gc3d9ivv1hlq": "R"}}, {"estado": "pendiente", "fin": "2027-04-02", "hito": false, "id": "mkz4yvzmc7b5", "ini": "2027-03-22", "nombre": "Planeación de contenido", "parent": "75bjopy8o9q0", "raci": {"ejfua4wd6pgm": "R", "fmohus2f0tcl": "A", "qm4901l38a2m": "R"}}, {"estado": "pendiente", "fin": "2027-04-16", "hito": false, "id": "pft910cecgzw", "ini": "2027-04-05", "nombre": "Programar grabación de contenido", "parent": "75bjopy8o9q0", "raci": {"qm4901l38a2m": "R"}}, {"estado": "pendiente", "fin": "2027-04-30", "hito": false, "id": "4i8r6jizyu9w", "ini": "2027-04-19", "nombre": "Grabar contenido", "parent": "75bjopy8o9q0", "raci": {}}, {"estado": "pendiente", "fin": "2027-05-14", "hito": false, "id": "8inunddvcnwp", "ini": "2027-05-03", "nombre": "Editar y entregar contenido", "parent": "75bjopy8o9q0", "raci": {"fmohus2f0tcl": "A", "qm4901l38a2m": "R"}}, {"estado": "pendiente", "fin": "2027-05-14", "hito": false, "id": "c6320ji1czo5", "ini": "2027-05-03", "nombre": "Calendarización de publicaciones y pauta", "parent": "75bjopy8o9q0", "raci": {"qm4901l38a2m": "I", "sz0bhb8e6xb1": "R"}}, {"estado": "pendiente", "fin": "2027-05-17", "hito": true, "id": "ht6rmfytutpf", "ini": "2027-05-17", "nombre": "Lanzamiento de la campaña", "parent": "75bjopy8o9q0", "raci": {}}, {"estado": "pendiente", "id": "3xmucac1brvr", "nombre": "Logística y operación", "parent": null, "raci": {}}, {"estado": "pendiente", "fin": "2027-06-11", "hito": false, "id": "e4lnqp1loq48", "ini": "2027-05-31", "nombre": "Hacer lista de necesidades operativas y logísticas", "parent": "3xmucac1brvr", "raci": {}}, {"estado": "pendiente", "fin": "2027-06-25", "hito": false, "id": "wuuq0226p6c0", "ini": "2027-06-14", "nombre": "Crear sheet con las necesidades operativas", "parent": "3xmucac1brvr", "raci": {}}, {"estado": "pendiente", "fin": "2027-08-06", "hito": false, "id": "ycpeohgxkslu", "ini": "2027-07-26", "nombre": "Reservar hospedaje y alimentación", "parent": "3xmucac1brvr", "raci": {}}, {"estado": "pendiente", "fin": "2027-08-27", "hito": false, "id": "rrjxw7zodbmi", "ini": "2027-08-23", "nombre": "Contratar transporte", "parent": "3xmucac1brvr", "raci": {}}, {"estado": "pendiente", "fin": "2027-09-03", "hito": false, "id": "i4swba4rp2i9", "ini": "2027-08-30", "nombre": "Asegurar instrumentos y equipo de audio", "parent": "3xmucac1brvr", "raci": {}}, {"estado": "pendiente", "fin": "2027-09-24", "hito": false, "id": "kmnid1ly7i4b", "ini": "2027-09-20", "nombre": "Preparar materiales y kits para asistentes", "parent": "3xmucac1brvr", "raci": {}}, {"estado": "pendiente", "fin": "2027-10-07", "hito": false, "id": "waiorhz1y8zj", "ini": "2027-10-04", "nombre": "Confirmación final con sede, proveedores y formadores", "parent": "3xmucac1brvr", "raci": {}}, {"estado": "pendiente", "id": "3un6bzvlv784", "nombre": "Comunicación con asistentes", "parent": null, "raci": {}}, {"estado": "pendiente", "fin": "2027-08-06", "hito": false, "id": "2r9ndwb6vgwy", "ini": "2027-07-26", "nombre": "Enviar mensaje de aceptación al campamento", "parent": "3un6bzvlv784", "raci": {}}, {"estado": "pendiente", "fin": "2027-08-13", "hito": false, "id": "cgxkegs7vsp7", "ini": "2027-08-09", "nombre": "Hacer llamada a los asistentes aceptados al camp", "parent": "3un6bzvlv784", "raci": {}}, {"estado": "pendiente", "fin": "2027-08-20", "hito": false, "id": "s1n0licuw257", "ini": "2027-08-16", "nombre": "Crear grupo de WhatsApp para asistentes", "parent": "3un6bzvlv784", "raci": {}}, {"estado": "pendiente", "fin": "2027-08-20", "hito": false, "id": "hxmyr2tb8553", "ini": "2027-08-16", "nombre": "Hacer plan de comunicación con asistentes", "parent": "3un6bzvlv784", "raci": {}}, {"estado": "pendiente", "fin": "2027-09-10", "hito": false, "id": "5zzhbb52sefi", "ini": "2027-09-06", "nombre": "Crear página con el itinerario", "parent": "3un6bzvlv784", "raci": {}}, {"estado": "pendiente", "fin": "2027-09-10", "hito": false, "id": "t8ly8nmds93t", "ini": "2027-09-06", "nombre": "Crear lista de qué llevar", "parent": "3un6bzvlv784", "raci": {}}, {"estado": "pendiente", "fin": "2027-09-17", "hito": false, "id": "a7yspsczuxi5", "ini": "2027-09-13", "nombre": "Crear formulario de registro de llevadas", "parent": "3un6bzvlv784", "raci": {}}, {"estado": "pendiente", "fin": "2027-10-01", "hito": false, "id": "atkhhd1u8ukc", "ini": "2027-09-27", "nombre": "Enviar material a los participantes", "parent": "3un6bzvlv784", "raci": {}}, {"estado": "pendiente", "id": "ah2kt8eehqla", "nombre": "Evento", "parent": null, "raci": {}}, {"estado": "pendiente", "fin": "2027-10-17", "hito": false, "id": "stln4fxcu4z3", "ini": "2027-10-08", "nombre": "Campamento Eleva tu música", "parent": "ah2kt8eehqla", "raci": {}}, {"estado": "pendiente", "id": "acrcu53t8nyy", "nombre": "Cierre y evaluación", "parent": null, "raci": {}}, {"estado": "pendiente", "fin": "2027-10-22", "hito": false, "id": "pjzhymluwonj", "ini": "2027-10-18", "nombre": "Encuesta de satisfacción a los asistentes", "parent": "acrcu53t8nyy", "raci": {}}, {"estado": "pendiente", "fin": "2027-10-29", "hito": false, "id": "2lo9lktg9ihn", "ini": "2027-10-18", "nombre": "Seguimiento a ministerios prospectos para el colectivo", "parent": "acrcu53t8nyy", "raci": {}}, {"estado": "pendiente", "fin": "2027-10-29", "hito": false, "id": "fani1chyojqj", "ini": "2027-10-25", "nombre": "Reporte de resultados y aprendizajes", "parent": "acrcu53t8nyy", "raci": {}}], "nombre": "Eleva tu música"}$tdd$::jsonb),
('plataforma-de-formacion', 'formacion', $tdd${"area": "formacion", "charter": {}, "cierre": {"objetivos": {}}, "creado": "2026-11-19T22:00:01.000Z", "equipo": [], "indicadores": [], "items": [], "nombre": "Plataforma de formación"}$tdd$::jsonb)
on conflict (id) do nothing;

insert into public.equipos (id, area, data) values
('fvlyafwp2pjh', 'formacion', $tdd${"actualizado": "2026-11-20T16:01:43.373Z", "area": "formacion", "miembros": [{"nombre": "Ceci Gómez", "roles": ["Project Manager"]}, {"nombre": "Rosy Ruesga", "roles": ["Seguimiento músicos"]}, {"nombre": "Diego Suárez", "roles": ["Desarrollador web", "Formador"]}, {"nombre": "Memo Reyes", "roles": ["Formador"]}, {"nombre": "Ale Suárez", "roles": ["Formadora", "Diseñadora instruccional"]}, {"nombre": "Ariel González", "roles": ["Formador"]}, {"nombre": "Willy Gálvez", "roles": ["Coordinador audiovisual"]}, {"nombre": "Karla Flores", "roles": ["Formadora", "Seguimiento formadores"]}, {"nombre": "Ricardo Bañuelos", "roles": ["Finanzas"]}], "nombre": "Equipo base"}$tdd$::jsonb)
on conflict (id) do nothing;

-- El equipo guardado de la versión anterior de este archivo se reemplazó; se borra por si ya se había cargado.
delete from public.equipos where id = '4550igq497x4';

insert into public.migraciones_aplicadas (nombre) values ('031_proyectos_formacion') on conflict (nombre) do nothing;
