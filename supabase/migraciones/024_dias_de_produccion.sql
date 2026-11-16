-- Bitácora Tiempo de Dios · migración 024: días exactos en las producciones que aparta un artista
-- Una producción full band ocupa lunes, martes, jueves y viernes (el miércoles queda para las demás áreas);
-- si el viernes no se produce, de lunes a jueves. La app ya guarda así sus producciones («dias»); esto hace
-- lo mismo con las que llegan por el enlace de agenda. Ejecútala una vez en Supabase → SQL Editor → Run.

create or replace function public.agenda_reservar(t text, inicio date, fin date, nombre text, correo text, telefono text, notas text)
returns json language plpgsql security definer set search_path = public as $$
#variable_conflict use_variable
declare a record; c record; paso text; ev text; r jsonb; cancion text; dias jsonb;
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
  -- Días exactos: entre semana y sin el miércoles cuando ese viernes también se produce (igual que agenda-reglas.js)
  select coalesce(jsonb_agg(to_char(d, 'YYYY-MM-DD') order by d), '[]'::jsonb) into dias
    from generate_series(inicio::timestamp, fin::timestamp, interval '1 day') g(d)
   where extract(isodow from d) < 6 and not (extract(isodow from d) = 3 and d::date + 2 <= fin);
  ev := 'agenda-' || a.id || case when a.reutilizable then '-' || to_char(inicio, 'YYYYMMDD') else '' end;
  -- En las ligas fijas, el nombre de la canción va en las notas (opcional): «Canción: …»
  cancion := nullif(trim(substring(coalesce(notas, '') from '^Canción: ([^\n]*)')), '');
  insert into public.eventos (id, area, data) values (ev, 'musica', jsonb_build_object(
    'titulo', 'Producción · ' || coalesce(nullif(a.nombre, ''), left(trim(nombre), 80)) || coalesce(' · «' || cancion || '»', ''),
    'tipo', 'produccion', 'tipoProd', a.tipo, 'fecha', to_char(inicio, 'YYYY-MM-DD'), 'fin', case when fin > inicio then to_char(fin, 'YYYY-MM-DD') else '' end,
    'dias', dias, 'hora', '09:00', 'horaFin', '17:00', 'repetir', '', 'hasta', '', 'area', 'musica', 'excepciones', '[]'::jsonb,
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
