-- Bitácora Tiempo de Dios · migración 022: áreas Legal y Marketing, funnel de canciones en tres áreas,
-- calendarios por área, agenda de producción para artistas y solicitudes de acceso a áreas.
-- Ejecútala una vez en Supabase → SQL Editor → New query → Run (si pregunta por RLS: «Run without RLS»,
-- la migración ya activa la RLS en sus tablas). Se puede volver a correr sin error.

-- ============ 1) Áreas nuevas: legal y marketing ============
alter table public.perfiles drop constraint if exists perfiles_area_check;
alter table public.perfiles add constraint perfiles_area_check
  check (area in ('formacion','musica','audiovisual','operativo','legal','marketing'));
alter table public.tareas drop constraint if exists tareas_area_check;
alter table public.tareas add constraint tareas_area_check
  check (area in ('formacion','musica','audiovisual','operativo','legal','marketing'));
alter table public.logros drop constraint if exists logros_area_check;
alter table public.logros add constraint logros_area_check
  check (area in ('formacion','musica','audiovisual','operativo','legal','marketing'));
alter table public.perfiles drop constraint if exists perfiles_areas_check;
alter table public.perfiles add constraint perfiles_areas_check
  check (areas <@ array['formacion','musica','audiovisual','operativo','legal','marketing']::text[]);

-- ¿La persona con sesión trabaja canciones? (Música, Legal, Marketing, Audiovisual por los lives, o PM)
create or replace function public.puede_canciones()
returns boolean language sql stable security definer set search_path = public as $$
  select public.puede_area('musica') or public.puede_area('legal') or public.puede_area('marketing') or public.puede_area('audiovisual');
$$;

-- ============ 2) Canciones: Legal, Marketing y Audiovisual también las ven y marcan su checklist ============
-- Dar de alta y borrar sigue siendo de Música (y PM).
drop policy if exists canciones_musica on public.canciones;
drop policy if exists canciones_ver on public.canciones;
create policy canciones_ver on public.canciones for select to authenticated using (public.puede_canciones());
drop policy if exists canciones_trabajar on public.canciones;
create policy canciones_trabajar on public.canciones for update to authenticated
  using (public.puede_canciones()) with check (public.puede_canciones());
drop policy if exists canciones_alta on public.canciones;
create policy canciones_alta on public.canciones for insert to authenticated with check (public.puede_area('musica'));
drop policy if exists canciones_borrar_fila on public.canciones;
create policy canciones_borrar_fila on public.canciones for delete to authenticated using (public.puede_area('musica'));

-- Documentos: Legal sube el comprobante INDAUTOR y el splitsheet en canciones/equipo/<canción>/…
drop policy if exists canciones_leer on storage.objects;
create policy canciones_leer on storage.objects for select to authenticated
  using (bucket_id = 'canciones' and public.puede_canciones());
drop policy if exists canciones_equipo_subir on storage.objects;
create policy canciones_equipo_subir on storage.objects for insert to authenticated
  with check (bucket_id = 'canciones' and (storage.foldername(name))[1] = 'equipo'
              and (public.puede_area('musica') or public.puede_area('legal')));

-- Pendientes automáticos de canciones: quien trabaja canciones crea y cierra el siguiente paso en cualquiera
-- de las áreas del funnel (Música, Legal, Marketing y la copia de Audiovisual de los lives).
drop policy if exists tareas_funnel on public.tareas;
create policy tareas_funnel on public.tareas for all to authenticated
  using (data ? 'cancion_id' and area in ('musica','legal','marketing','audiovisual') and public.puede_canciones())
  with check (data ? 'cancion_id' and area in ('musica','legal','marketing','audiovisual') and public.puede_canciones());

-- Los pendientes abiertos de INDAUTOR/splitsheet pasan a Legal y los de marketing (handoff y D-Day) a Marketing
update public.tareas set area = 'legal', data = jsonb_set(data, '{area}', '"legal"')
 where area = 'musica' and data ? 'cancion_id' and data->>'hecha' is null
   and (data->>'paso') in ('13','14')
   and exists (select 1 from public.canciones c where c.id::text = tareas.data->>'cancion_id' and coalesce(c.data->>'formato','estudio') <> 'live');
update public.tareas set area = 'marketing', data = jsonb_set(data, '{area}', '"marketing"')
 where area = 'musica' and data ? 'cancion_id' and data->>'hecha' is null
   and (data->>'paso') ~ '^(1[6-9]|2[0-4])$'
   and exists (select 1 from public.canciones c where c.id::text = tareas.data->>'cancion_id' and coalesce(c.data->>'formato','estudio') <> 'live');

-- ============ 3) Enlace de agenda de producción para artistas ============
-- Música arma un enlace (/agenda/<token>) marcando el tipo de producción del artista. El artista ve las semanas
-- con lugar para ese tipo (reglas en app/agenda-reglas.js) y reserva; la reserva queda en el calendario de Música.
create table if not exists public.agendas_artistas (
  id uuid primary key default gen_random_uuid(),
  token text not null unique default replace(gen_random_uuid()::text, '-', ''),
  tipo text not null check (tipo in ('acustico','fullband','grande')),
  nombre text not null default '' check (char_length(nombre) <= 120),
  cancion_id uuid references public.canciones(id) on delete set null,
  activa boolean not null default true,
  reservado jsonb,             -- {inicio, fin, nombre, correo, telefono, notas, cuando}
  creado timestamptz not null default now(),
  creado_por uuid default auth.uid()
);
alter table public.agendas_artistas enable row level security;
drop policy if exists agendas_musica on public.agendas_artistas;
create policy agendas_musica on public.agendas_artistas for all to authenticated
  using (public.puede_area('musica')) with check (public.puede_area('musica'));

-- Lo que ve el artista: tipo, nombre y solo las fechas que ocupan producción (sin títulos ni notas)
create or replace function public.agenda_ver(t text)
returns json language plpgsql stable security definer set search_path = public as $$
declare a record;
begin
  select * into a from public.agendas_artistas where token = lower(trim(t)) and activa limit 1;
  if not found then return null; end if;
  return json_build_object(
    'tipo', a.tipo, 'nombre', a.nombre,
    'reservado', case when a.reservado is null then null else json_build_object('inicio', a.reservado->>'inicio', 'fin', a.reservado->>'fin') end,
    'eventos', coalesce((select json_agg(json_build_object(
        'id', md5(e.id), 'tipo', e.data->>'tipo', 'fecha', e.data->>'fecha', 'fin', e.data->>'fin',
        'repetir', e.data->>'repetir', 'hasta', e.data->>'hasta', 'excepciones', coalesce(e.data->'excepciones', '[]'::jsonb),
        'cancion_id', case when coalesce(e.data->>'cancion_id', '') <> '' then 'si' end))
      from public.eventos e
      where e.data->>'tipo' in ('produccion','grabacion','externo','inhabil')
        and (coalesce(e.data->>'repetir', '') <> '' or coalesce(nullif(e.data->>'fin', ''), e.data->>'fecha') >= to_char(current_date - 14, 'YYYY-MM-DD'))), '[]'::json));
end $$;
grant execute on function public.agenda_ver(text) to anon, authenticated;

-- Reservar: vuelve a revisar que esas fechas sigan libres y deja la producción en el calendario
create or replace function public.agenda_reservar(t text, inicio date, fin date, nombre text, correo text, telefono text, notas text)
returns json language plpgsql security definer set search_path = public as $$
declare a record; c record; paso text; ev text;
begin
  select * into a from public.agendas_artistas where token = lower(trim(t)) and activa for update;
  if not found then raise exception 'Este enlace ya no está activo.'; end if;
  if a.reservado is not null then raise exception 'Este enlace ya tiene una fecha reservada.'; end if;
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
  ev := 'agenda-' || a.id;
  insert into public.eventos (id, area, data) values (ev, 'musica', jsonb_build_object(
    'titulo', 'Producción · ' || coalesce(nullif(a.nombre, ''), left(trim(nombre), 80)),
    'tipo', 'produccion', 'tipoProd', a.tipo, 'fecha', to_char(inicio, 'YYYY-MM-DD'), 'fin', case when fin > inicio then to_char(fin, 'YYYY-MM-DD') else '' end,
    'hora', '09:00', 'horaFin', '17:00', 'repetir', '', 'hasta', '', 'area', 'musica', 'excepciones', '[]'::jsonb,
    'notas', left('Agendada por el artista desde el enlace de agenda: ' || trim(nombre) || ' · ' || trim(correo) || coalesce(' · ' || nullif(trim(telefono), ''), '') || coalesce(' · ' || nullif(trim(notas), ''), ''), 1000),
    'cancion_id', a.cancion_id, 'agenda_id', a.id, 'creado', now()));
  update public.agendas_artistas set reservado = jsonb_build_object('inicio', inicio, 'fin', fin, 'nombre', left(trim(nombre), 120),
    'correo', left(trim(correo), 160), 'telefono', left(coalesce(trim(telefono), ''), 40), 'notas', left(coalesce(trim(notas), ''), 1000), 'cuando', now(), 'evento', ev)
   where id = a.id;
  -- La canción ligada queda agendada (estudio: paso 5; live: paso 3)
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

do $$ begin alter publication supabase_realtime add table public.agendas_artistas;
exception when duplicate_object then null; end $$;
