-- Bitácora Tiempo de Dios · migración 003: rol "desarrollador"
-- Mismo acceso completo que la PM (ve y edita todo, administra el equipo), con su propia etiqueta.
-- Ejecútala una vez en Supabase → SQL Editor → New query → Run. Se puede volver a correr sin error.

alter table public.perfiles drop constraint if exists perfiles_rol_check;
alter table public.perfiles add constraint perfiles_rol_check
  check (rol in ('pm','desarrollador','lider','colaborador'));

-- es_pm() decide quién tiene acceso completo en todas las reglas (RLS, fotos, proteger_rol)
create or replace function public.es_pm()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.perfiles where id = auth.uid() and rol in ('pm','desarrollador'));
$$;

-- Diego pasa a ser desarrollador
update public.perfiles set rol = 'desarrollador', area = null
  where id = (select id from auth.users where email = 'diegosuarez@tiempodedios.mx');
