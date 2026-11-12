-- Bitácora Tiempo de Dios · migración 012: Entradas de formación
-- Formulario público (pm.tiempodedios.mx/entrada/) donde formadores, facilitadores y expertos
-- comparten los datos de un curso o taller y suben sus documentos.
-- Las respuestas llegan a la pestaña "Entradas" del área de Formación.
-- Ejecútala una vez en Supabase → SQL Editor → New query → Run. Se puede volver a correr sin error.

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
