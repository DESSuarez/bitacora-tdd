-- Bitácora Tiempo de Dios · migración 025: del registro de canción directo a la agenda de producción
-- · El formulario de canciones lista los ministerios del colectivo (selector de «Artista o ministerio»).
-- · Al enviar la canción, el artista pasa a la liga fija de agenda de su ministerio para el tipo de producción
--   que eligió, y lo que aparte queda ligado a esa canción (y cierra el pendiente «Agendar producción»).
--   Si no quiere elegir fechas, el pendiente sigue abierto para que Música coordine con él.
-- Ejecútala una vez en Supabase → SQL Editor → Run. Se puede volver a correr sin error.

-- Ministerios del colectivo (solo nombres de las ligas activas) para el selector del formulario
create or replace function public.ministerios_colectivo()
returns json language sql stable security definer set search_path = public as $$
  select coalesce(json_agg(nombre order by lower(nombre)), '[]'::json)
    from (select distinct nombre from public.ligas_artistas where activa and coalesce(trim(nombre), '') <> '') m;
$$;
grant execute on function public.ministerios_colectivo() to anon, authenticated;

-- La liga fija de agenda de un ministerio queda amarrada a su liga de canciones
alter table public.agendas_artistas add column if not exists liga uuid references public.ligas_artistas(id) on delete set null;

-- Código de la liga fija de agenda del ministerio de esa liga para ese tipo (la crea si no existe)
create or replace function public.agenda_de_liga(l uuid, tipo text)
returns text language plpgsql security definer set search_path = public as $$
#variable_conflict use_variable
declare li record; a record; base text; tok text; n int := 1;
begin
  if tipo not in ('acustico','fullband','grande') then return null; end if;
  select * into li from public.ligas_artistas where id = l and activa;
  if not found then return null; end if;
  select * into a from public.agendas_artistas x
   where x.reutilizable and x.activa and x.tipo = tipo and (x.liga = l or (x.liga is null and x.nombre = li.nombre))
   order by (x.liga = l) desc nulls last limit 1;
  if found then
    if a.liga is null then update public.agendas_artistas set liga = l where id = a.id; end if;
    return a.token;
  end if;
  base := coalesce(nullif(li.slug, ''), public.slug_texto(li.nombre), 'ministerio') || '-' ||
          case tipo when 'acustico' then 'acustica' else tipo end;
  tok := base;
  while exists (select 1 from public.agendas_artistas where token = tok) loop n := n + 1; tok := base || '-' || n; end loop;
  insert into public.agendas_artistas (token, tipo, nombre, reutilizable, liga, creado_por)
  values (tok, tipo, left(li.nombre, 120), true, l, null);
  return tok;
end $$;
grant execute on function public.agenda_de_liga(uuid, text) to anon, authenticated;

-- Reservar, ahora con la canción que el artista acaba de registrar (c_id, opcional)
drop function if exists public.agenda_reservar(text, date, date, text, text, text, text);
create or replace function public.agenda_reservar(t text, inicio date, fin date, nombre text, correo text, telefono text, notas text, c_id uuid default null)
returns json language plpgsql security definer set search_path = public as $$
#variable_conflict use_variable
declare a record; c record; paso text; ev text; r jsonb; cancion text; dias jsonb; cid uuid;
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
  -- La canción: la de la liga de un solo uso o la que el artista acaba de registrar con la liga de su ministerio (sin agendar aún)
  cid := a.cancion_id;
  if cid is null and c_id is not null and a.liga is not null then
    select id into cid from public.canciones where id = c_id and liga = a.liga and semana is null;
  end if;
  select coalesce(jsonb_agg(to_char(d, 'YYYY-MM-DD') order by d), '[]'::jsonb) into dias
    from generate_series(inicio::timestamp, fin::timestamp, interval '1 day') g(d)
   where extract(isodow from d) < 6 and not (extract(isodow from d) = 3 and d::date + 2 <= fin);
  ev := 'agenda-' || a.id || case when a.reutilizable then '-' || to_char(inicio, 'YYYYMMDD') else '' end;
  cancion := coalesce((select nullif(data->>'titulo', '') from public.canciones where id = cid),
                      nullif(trim(substring(coalesce(notas, '') from '^Canción: ([^\n]*)')), ''));
  insert into public.eventos (id, area, data) values (ev, 'musica', jsonb_build_object(
    'titulo', 'Producción · ' || coalesce(nullif(a.nombre, ''), left(trim(nombre), 80)) || coalesce(' · «' || cancion || '»', ''),
    'tipo', 'produccion', 'tipoProd', a.tipo, 'fecha', to_char(inicio, 'YYYY-MM-DD'), 'fin', case when fin > inicio then to_char(fin, 'YYYY-MM-DD') else '' end,
    'dias', dias, 'hora', '09:00', 'horaFin', '17:00', 'repetir', '', 'hasta', '', 'area', 'musica', 'excepciones', '[]'::jsonb,
    'notas', left('Agendada por el artista desde el enlace de agenda: ' || trim(nombre) || ' · ' || trim(correo) || coalesce(' · ' || nullif(trim(telefono), ''), '') || coalesce(' · ' || nullif(trim(notas), ''), ''), 1000),
    'cancion_id', cid, 'agenda_id', a.id, 'creado', now()));
  r := jsonb_build_object('inicio', inicio, 'fin', fin, 'nombre', left(trim(nombre), 120), 'correo', left(trim(correo), 160),
    'telefono', left(coalesce(trim(telefono), ''), 40), 'notas', left(coalesce(trim(notas), ''), 1000), 'cuando', now(), 'evento', ev, 'cancion_id', cid);
  update public.agendas_artistas set reservado = r, reservas = coalesce(reservas, '[]'::jsonb) || jsonb_build_array(r) where id = a.id;
  if cid is not null then
    select * into c from public.canciones where id = cid;
    if found then
      paso := case when c.data->>'formato' = 'live' then '3' else '5' end;
      update public.canciones set semana = date_trunc('week', inicio)::date,
        data = case when c.data ? 'tipoProd' then c.data else c.data || jsonb_build_object('tipoProd', a.tipo) end,
        checklist = case when checklist ? paso then checklist else checklist || jsonb_build_object(paso, now()) end,
        etapa = case when etapa in ('intake','preproduccion') then 'agendada' else etapa end
       where id = cid;
      -- El pendiente «Agendar producción» de esa canción queda hecho
      update public.tareas set data = data || jsonb_build_object('hecha', to_char(now() at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
             'cierre', 'El artista apartó sus fechas desde la liga de agenda: ' || to_char(inicio, 'DD/MM') || ' – ' || to_char(fin, 'DD/MM/YYYY'))
       where data->>'cancion_id' = cid::text and not (data ? 'paso') and coalesce(data->>'hecha', '') = '';
    end if;
  end if;
  return json_build_object('ok', true, 'inicio', inicio, 'fin', fin);
end $$;
grant execute on function public.agenda_reservar(text, date, date, text, text, text, text, uuid) to anon, authenticated;
