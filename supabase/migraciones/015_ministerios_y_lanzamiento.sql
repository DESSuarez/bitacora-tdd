-- Bitácora Tiempo de Dios · migración 015: ministerios, lanzamiento y canciones agregadas a mano
-- 1. canciones.ministerio: a qué ministerio del colectivo pertenece (para el dashboard por ministerio).
-- 2. canciones.lanzamiento: fecha del lanzamiento (D0); de ahí salen las fechas del pipeline de Marketing.
-- 3. El equipo de Música puede agregar canciones que ya estaban en proceso; esas no crean la tarea
--    "Agendar producción": su pendiente es el siguiente paso del checklist y lo crea la app.
-- Ejecútala una vez en Supabase → SQL Editor → New query → Run. Se puede volver a correr sin error.

alter table public.canciones add column if not exists ministerio text check (ministerio is null or char_length(ministerio) <= 120);
alter table public.canciones add column if not exists lanzamiento date;

-- Las canciones que ya existían toman el nombre de su liga como ministerio
update public.canciones c set ministerio = l.nombre
  from public.ligas_artistas l where c.liga = l.id and coalesce(c.ministerio, '') = '';

-- Persona del equipo por usuario o por nombre (para asignar la tarea automática)
create or replace function public.persona_equipo(n text)
returns public.perfiles language sql stable security definer set search_path = public as $$
  select * from public.perfiles
  where lower(usuario) = lower(n) or nombre ilike n || '%'
  order by (lower(usuario) = lower(n)) desc limit 1;
$$;

-- Al registrar: la fecha la pone la base, los archivos deben estar en su carpeta
-- y se crea la tarea "Agendar producción" en Música.
create or replace function public.cancion_nueva()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  ariel public.perfiles; memo public.perfiles;
  titulo text := coalesce(nullif(new.data->>'titulo',''), 'Canción sin título');
  artista text := coalesce(nullif(new.data->>'nombreArtistico',''), nullif(new.data->>'nombre',''),
                           (select nombre from public.ligas_artistas where id = new.liga), 'Artista');
  lunes date := date_trunc('week', (now() at time zone 'America/Mexico_City'))::date;
  orden numeric;
  sub jsonb;
begin
  new.creado = now(); new.actualizado = now(); new.actualizado_por = auth.uid();
  -- Las que llegan por liga toman el nombre de la liga como ministerio
  new.ministerio := coalesce((select nombre from public.ligas_artistas where id = new.liga), nullif(new.ministerio, ''), nullif(new.data->>'nombreArtistico',''));
  if exists (select 1 from jsonb_array_elements(new.archivos) a
             where coalesce(a->>'ruta','') not like coalesce(new.liga::text,'-') || '/' || new.id::text || '/%') then
    raise exception 'Cada archivo debe estar en la carpeta de su canción';
  end if;

  -- Las canciones que el equipo agrega a mano no traen liga: su pendiente lo crea la app (siguiente paso del checklist)
  if new.liga is null then return new; end if;

  ariel := public.persona_equipo('ariel');
  memo := public.persona_equipo('memo');
  select coalesce(max((data->>'orden')::numeric), 0) + 1 into orden
    from public.tareas where area = 'musica' and data->>'semana' = lunes::text;
  sub := jsonb_build_array(
    jsonb_build_object('id', 'c1', 'titulo', 'Revisar y aprobar la canción (intake)',
      'responsable', coalesce(memo.nombre, 'Memo'), 'responsable_id', memo.id, 'hecha', null),
    jsonb_build_object('id', 'c2', 'titulo', 'Agendar la semana de producción con el ministerio',
      'responsable', coalesce(ariel.nombre, 'Ariel'), 'responsable_id', ariel.id, 'hecha', null),
    jsonb_build_object('id', 'c3', 'titulo', 'Confirmar la semana con Memo, Diego y el artista',
      'responsable', coalesce(memo.nombre, 'Memo'), 'responsable_id', memo.id, 'hecha', null));

  insert into public.tareas (id, area, data) values ('cancion-' || new.id::text, 'musica', jsonb_build_object(
    'area', 'musica',
    'titulo', 'Agendar producción: «' || titulo || '» · ' || artista,
    'proyecto', 'Canciones',
    'responsable', coalesce(ariel.nombre, 'Ariel'), 'responsable_id', ariel.id,
    'semana', lunes::text,
    'creada', to_char(now() at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
    'creada_por', null, 'hecha', null, 'orden', orden,
    'nota', 'Canción registrada por ' || artista || ' desde su liga. Revísala en Música → Canciones y agenda su semana de producción.',
    'cancion_id', new.id, 'vence', null,
    'subtareas', sub))
  on conflict (id) do nothing;
  return new;
end $$;

