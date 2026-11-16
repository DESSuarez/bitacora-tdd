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
