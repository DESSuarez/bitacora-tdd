-- Bitácora Tiempo de Dios · migración 007: área "operativo" y personas en varias áreas
-- 1) Nueva área "operativo" en perfiles, tareas y logros.
-- 2) perfiles.areas: áreas adicionales donde también participa la persona (además de "area").
--    Sirve para asignarle tareas ahí y le da permiso de editar esas áreas.
-- 3) Diego (desarrollador) también participa en Música y Operativo.
-- Ejecútala una vez en Supabase → SQL Editor → New query → Run. Se puede volver a correr sin error.

-- 1) Área operativa
-- Quita las reglas viejas de área (las que solo aceptaban tres), tengan el nombre que tengan
do $$
declare r record;
begin
  for r in select c.conrelid::regclass as tabla, c.conname from pg_constraint c
           where c.contype = 'c' and c.conrelid in ('public.perfiles'::regclass, 'public.tareas'::regclass, 'public.logros'::regclass)
             and pg_get_constraintdef(c.oid) like '%audiovisual%' and pg_get_constraintdef(c.oid) not like '%operativo%'
  loop
    execute format('alter table %s drop constraint %I', r.tabla, r.conname);
  end loop;
end $$;
alter table public.perfiles drop constraint if exists perfiles_area_check;
alter table public.perfiles add constraint perfiles_area_check
  check (area in ('formacion','musica','audiovisual','operativo'));
alter table public.tareas drop constraint if exists tareas_area_check;
alter table public.tareas add constraint tareas_area_check
  check (area in ('formacion','musica','audiovisual','operativo'));
alter table public.logros drop constraint if exists logros_area_check;
alter table public.logros add constraint logros_area_check
  check (area in ('formacion','musica','audiovisual','operativo'));

-- 2) Áreas adicionales
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

-- Solo la PM cambia rol, área y áreas adicionales
create or replace function public.proteger_rol()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is not null and not public.es_pm()
     and (new.rol is distinct from old.rol or new.area is distinct from old.area
          or new.areas is distinct from old.areas) then
    raise exception 'Solo la project manager puede cambiar rol o área';
  end if;
  return new;
end $$;

-- 3) Diego también en Música y Operativo
update public.perfiles set areas = array['musica','operativo']
  where id = (select id from auth.users where email = 'diegosuarez@tiempodedios.mx');
