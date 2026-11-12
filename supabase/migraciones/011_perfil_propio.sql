-- Bitácora Tiempo de Dios · migración 011: cada quien edita solo su propio perfil
-- Nombre, usuario, foto y "Sobre mí" solo los cambia la persona dueña del perfil (ni la PM).
-- La PM sigue administrando rol, área y áreas adicionales en la pestaña Equipo.
-- (auth.uid() es null en el SQL Editor y en la Edge Function "equipo", que sí pueden.)
-- Ejecútala una vez en Supabase → SQL Editor → New query → Run. Se puede volver a correr sin error.

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

-- Fotos: cada persona sube, cambia y borra solo en su carpeta (fotos/<su id>/...)
drop policy if exists fotos_subir on storage.objects;
create policy fotos_subir on storage.objects for insert to authenticated
  with check (bucket_id = 'fotos' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists fotos_cambiar on storage.objects;
create policy fotos_cambiar on storage.objects for update to authenticated
  using (bucket_id = 'fotos' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists fotos_borrar on storage.objects;
create policy fotos_borrar on storage.objects for delete to authenticated
  using (bucket_id = 'fotos' and (storage.foldername(name))[1] = auth.uid()::text);
