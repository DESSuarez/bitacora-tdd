-- Bitácora Tiempo de Dios · migración 014: portada en la carta de presentación
-- Cada quien puede poner una imagen de portada en su perfil (fotos/<su id>/portada-<fecha>.jpg).
-- Si no pone ninguna, la portada usa los colores de sus áreas.
-- Solo la persona dueña del perfil la cambia (ni la PM), igual que nombre, usuario, foto y "Sobre mí".
-- Ejecútala una vez en Supabase → SQL Editor → New query → Run. Se puede volver a correr sin error.

alter table public.perfiles add column if not exists portada text;

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
          or new.foto is distinct from old.foto or new.bio is distinct from old.bio
          or new.portada is distinct from old.portada) then
    raise exception 'Solo puedes editar tu propio perfil';
  end if;
  return new;
end $$;
