-- Bitácora Tiempo de Dios · migración 020: ligas limpias e inamovibles para registrar canciones
-- Cada ministerio tiene una dirección fija: pm.tiempodedios.mx/cancion/<ministerio>
--   (ej. «Surgit Iglessia» → /cancion/surgit-iglessia). Se crea sola a partir del nombre, una sola vez,
--   y nunca cambia aunque después se cambie el nombre del ministerio.
-- Las ligas viejas (/cancion/?l=<id>) siguen funcionando.
-- Ejecútala una vez en Supabase → SQL Editor → New query → Run. Se puede volver a correr sin error.

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
