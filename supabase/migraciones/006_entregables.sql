-- Bitácora Tiempo de Dios · migración 006: archivos entregables en tareas y subtareas
-- Bucket PRIVADO "entregables": solo quien inició sesión puede abrirlos (con una liga temporal).
-- Ruta de cada archivo: <área>/<id de la tarea>/<timestamp>-<nombre>
-- Sube y borra quien puede editar esa área (o la PM / desarrollador). Límite: 25 MB por archivo.
-- Ejecútala una vez en Supabase → SQL Editor → New query → Run. Se puede volver a correr sin error.

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
