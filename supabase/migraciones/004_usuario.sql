-- Bitácora Tiempo de Dios · migración 004: nombre de usuario (@usuario) separado del nombre
-- "nombre" es como se ve la persona (Diego Suárez); "usuario" es su identificador único (@diegosuarez).
-- Ejecútala una vez en Supabase → SQL Editor → New query → Run. Se puede volver a correr sin error.

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
