-- Bitácora Tiempo de Dios · migración 023: liga fija de agenda por ministerio
-- Cada ministerio del colectivo tiene una liga fija por tipo de producción, que se usa todas las veces que quiera
-- (ej. pm.tiempodedios.mx/agenda/surgit-iglessia-fullband). Los artistas invitados (fuera del colectivo)
-- siguen con ligas de un solo uso. Cada reserva queda guardada en «reservas».
-- Ejecútala una vez en Supabase → SQL Editor → Run. Se puede volver a correr sin error.

alter table public.agendas_artistas add column if not exists reutilizable boolean not null default false;
alter table public.agendas_artistas add column if not exists reservas jsonb not null default '[]'::jsonb;
alter table public.agendas_artistas drop constraint if exists agendas_token_formato;
alter table public.agendas_artistas add constraint agendas_token_formato check (token ~ '^[a-z0-9]+(-[a-z0-9]+)*$');

-- Lo que ve el artista (las ligas fijas no se «gastan»: nunca se muestran como ya reservadas)
create or replace function public.agenda_ver(t text)
returns json language plpgsql stable security definer set search_path = public as $$
declare a record;
begin
  select * into a from public.agendas_artistas where token = lower(trim(t)) and activa limit 1;
  if not found then return null; end if;
  return json_build_object(
    'tipo', a.tipo, 'nombre', a.nombre, 'reutilizable', a.reutilizable,
    'reservado', case when a.reservado is null or a.reutilizable then null else json_build_object('inicio', a.reservado->>'inicio', 'fin', a.reservado->>'fin') end,
    'eventos', coalesce((select json_agg(json_build_object(
        'id', md5(e.id), 'tipo', e.data->>'tipo', 'fecha', e.data->>'fecha', 'fin', e.data->>'fin',
        'repetir', e.data->>'repetir', 'hasta', e.data->>'hasta', 'excepciones', coalesce(e.data->'excepciones', '[]'::jsonb),
        'cancion_id', case when coalesce(e.data->>'cancion_id', '') <> '' then 'si' end))
      from public.eventos e
      where e.data->>'tipo' in ('produccion','grabacion','externo','inhabil')
        and (coalesce(e.data->>'repetir', '') <> '' or coalesce(nullif(e.data->>'fin', ''), e.data->>'fecha') >= to_char(current_date - 14, 'YYYY-MM-DD'))), '[]'::json));
end $$;
grant execute on function public.agenda_ver(text) to anon, authenticated;

create or replace function public.agenda_reservar(t text, inicio date, fin date, nombre text, correo text, telefono text, notas text)
returns json language plpgsql security definer set search_path = public as $$
#variable_conflict use_variable
declare a record; c record; paso text; ev text; r jsonb; cancion text;
begin
  select * into a from public.agendas_artistas where token = lower(trim(t)) and activa for update;
  if not found then raise exception 'Este enlace ya no está activo.'; end if;
  if a.reservado is not null and not a.reutilizable then raise exception 'Este enlace ya tiene una fecha reservada.'; end if;
  if inicio is null or fin is null or fin < inicio or fin - inicio > 13 then raise exception 'Fechas no válidas.'; end if;
  if inicio <= current_date then raise exception 'Elige una fecha a partir de mañana.'; end if;
  if coalesce(trim(nombre), '') = '' or coalesce(trim(correo), '') = '' then raise exception 'Escribe tu nombre y tu correo.'; end if;
  if exists (select 1 from public.eventos e
              where (e.data->>'tipo' in ('produccion','inhabil') or (e.data->>'tipo' = 'grabacion' and coalesce(e.data->>'cancion_id', '') <> ''))
                and coalesce(e.data->>'repetir', '') = ''
                and (e.data->>'fecha')::date <= fin
                and coalesce(nullif(e.data->>'fin', ''), e.data->>'fecha')::date >= inicio) then
    raise exception 'Alguien acaba de apartar esas fechas. Elige otras, por favor.';
  end if;
  ev := 'agenda-' || a.id || case when a.reutilizable then '-' || to_char(inicio, 'YYYYMMDD') else '' end;
  -- En las ligas fijas, el nombre de la canción va en las notas (opcional): «Canción: …»
  cancion := nullif(trim(substring(coalesce(notas, '') from '^Canción: ([^\n]*)')), '');
  insert into public.eventos (id, area, data) values (ev, 'musica', jsonb_build_object(
    'titulo', 'Producción · ' || coalesce(nullif(a.nombre, ''), left(trim(nombre), 80)) || coalesce(' · «' || cancion || '»', ''),
    'tipo', 'produccion', 'tipoProd', a.tipo, 'fecha', to_char(inicio, 'YYYY-MM-DD'), 'fin', case when fin > inicio then to_char(fin, 'YYYY-MM-DD') else '' end,
    'hora', '09:00', 'horaFin', '17:00', 'repetir', '', 'hasta', '', 'area', 'musica', 'excepciones', '[]'::jsonb,
    'notas', left('Agendada por el artista desde el enlace de agenda: ' || trim(nombre) || ' · ' || trim(correo) || coalesce(' · ' || nullif(trim(telefono), ''), '') || coalesce(' · ' || nullif(trim(notas), ''), ''), 1000),
    'cancion_id', a.cancion_id, 'agenda_id', a.id, 'creado', now()));
  r := jsonb_build_object('inicio', inicio, 'fin', fin, 'nombre', left(trim(nombre), 120),
    'correo', left(trim(correo), 160), 'telefono', left(coalesce(trim(telefono), ''), 40), 'notas', left(coalesce(trim(notas), ''), 1000), 'cuando', now(), 'evento', ev);
  update public.agendas_artistas set reservado = r, reservas = coalesce(reservas, '[]'::jsonb) || jsonb_build_array(r) where id = a.id;
  if a.cancion_id is not null then
    select * into c from public.canciones where id = a.cancion_id;
    if found then
      paso := case when c.data->>'formato' = 'live' then '3' else '5' end;
      update public.canciones set semana = date_trunc('week', inicio)::date,
        checklist = case when checklist ? paso then checklist else checklist || jsonb_build_object(paso, now()) end,
        etapa = case when etapa in ('intake','preproduccion') then 'agendada' else etapa end
       where id = a.cancion_id;
    end if;
  end if;
  return json_build_object('ok', true, 'inicio', inicio, 'fin', fin);
end $$;
grant execute on function public.agenda_reservar(text, date, date, text, text, text, text) to anon, authenticated;
