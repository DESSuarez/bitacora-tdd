-- Bitácora Tiempo de Dios · migración 002: perfil de usuario con fotografía
-- Ejecútala una vez en Supabase → SQL Editor → New query → Run.
-- Se puede volver a correr sin error. Ya está incluida en schema.sql para proyectos nuevos.

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

-- Bucket público para las fotos: cada persona sube a su carpeta (fotos/<su id>/...); la PM, a cualquiera
insert into storage.buckets (id, name, public)
values ('fotos', 'fotos', true)
on conflict (id) do update set public = true;

drop policy if exists fotos_subir on storage.objects;
create policy fotos_subir on storage.objects for insert to authenticated
  with check (bucket_id = 'fotos' and ((storage.foldername(name))[1] = auth.uid()::text or public.es_pm()));

drop policy if exists fotos_cambiar on storage.objects;
create policy fotos_cambiar on storage.objects for update to authenticated
  using (bucket_id = 'fotos' and ((storage.foldername(name))[1] = auth.uid()::text or public.es_pm()));

drop policy if exists fotos_borrar on storage.objects;
create policy fotos_borrar on storage.objects for delete to authenticated
  using (bucket_id = 'fotos' and ((storage.foldername(name))[1] = auth.uid()::text or public.es_pm()));
