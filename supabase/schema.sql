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

-- Solo la PM cambia rol, área y áreas adicionales; nombre, usuario, foto y bio solo los cambia cada quien (migración 011)
create or replace function public.proteger_rol()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is not null and not public.es_pm()
     and (new.rol is distinct from old.rol or new.area is distinct from old.area
          or new.areas is distinct from old.areas) then
    raise exception 'Solo la project manager puede cambiar rol o área';
  end if;
  if auth.uid() is not null and auth.uid() <> old.id
     and (new.nombre is distinct from old.nombre or new.usuario is distinct from old.usuario
          or new.foto is distinct from old.foto or new.bio is distinct from old.bio) then
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
