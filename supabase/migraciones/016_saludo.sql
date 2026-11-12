-- Bitácora Tiempo de Dios · migración 016: saludo del Dashboard
-- "Bienvenido Diego, hijo de Dios" / "Bienvenida Ceci, hija de Dios". Cada quien lo elige en su perfil;
-- mientras no elija, la app lo deduce del nombre.
-- Ejecútala una vez en Supabase → SQL Editor → New query → Run. Se puede volver a correr sin error.
alter table public.perfiles add column if not exists saludo text;
alter table public.perfiles drop constraint if exists perfiles_saludo_valido;
alter table public.perfiles add constraint perfiles_saludo_valido check (saludo is null or saludo in ('hijo','hija'));
