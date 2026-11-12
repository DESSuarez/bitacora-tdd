-- Bitácora Tiempo de Dios · migración 018: Samply y las dos escuchas del master
-- 1. El paso 11 («Aprobación del master por el artista») se divide en dos escuchas:
--      11 · Primera escucha del master (Samply)
--      12 · Segunda escucha y aprobación del master por el artista
--    Por eso todos los pasos desde el 11 suben un número (el checklist pasa de 22 a 23 pasos).
--    Esta migración reacomoda las canciones, sus documentos y sus pendientes que ya existían
--    (si el viejo paso 11 estaba hecho, quedan hechas las dos escuchas). Solo se aplica una vez.
-- 2. samply_eventos: lo que avisa Samply por webhook (subida terminada, comentario nuevo).
-- 3. samply_config: datos internos de la función "samply" (secreto del webhook). Nadie los lee desde la app.
-- Ejecútala una vez en Supabase → SQL Editor → New query → Run. Se puede volver a correr sin error.

-- ============ 1. Checklist de 23 pasos ============
alter table public.canciones add column if not exists pasos_version int not null default 1;

update public.canciones c set
  checklist = coalesce((
      select jsonb_object_agg(case when k.key ~ '^\d+$' and k.key::int >= 11 then (k.key::int + 1)::text else k.key end, k.value)
      from jsonb_each(c.checklist) k), '{}'::jsonb)
    || case when c.checklist ? '11' then jsonb_build_object('11', c.checklist->'11') else '{}'::jsonb end,
  archivos = coalesce((
      select jsonb_agg(case when a->>'campo' ~ '^paso\d+$' and substring(a->>'campo' from 5)::int >= 11
                            then jsonb_set(a, '{campo}', to_jsonb('paso' || (substring(a->>'campo' from 5)::int + 1)))
                            else a end)
      from jsonb_array_elements(c.archivos) a), '[]'::jsonb),
  pasos_version = 2
where c.pasos_version = 1;

-- Las canciones nuevas ya nacen con la numeración de 23 pasos
alter table public.canciones alter column pasos_version set default 2;

-- Pendientes de canciones: su número de paso también sube desde el 11 (se marcan para no repetirlo)
update public.tareas set data = jsonb_set(data, '{paso}', to_jsonb((data->>'paso')::int + 1)) || '{"pasos_version":2}'::jsonb
where data ? 'cancion_id' and data->>'paso' ~ '^\d+$' and (data->>'paso')::int >= 11
  and coalesce(data->>'pasos_version', '1') = '1';

-- ============ 2. Eventos de Samply ============
create table if not exists public.samply_eventos (
  id text primary key,                      -- webhook-id: evita guardar dos veces el mismo aviso
  creado timestamptz not null default now(),
  tipo text not null,                       -- upload.completed, comment.created…
  projectid text,
  boxid text,
  box_nombre text,
  mensaje text,
  autor text,
  payload jsonb
);
create index if not exists samply_eventos_proyecto on public.samply_eventos (projectid, creado desc);
alter table public.samply_eventos enable row level security;
drop policy if exists samply_eventos_ver on public.samply_eventos;
create policy samply_eventos_ver on public.samply_eventos for select to authenticated
  using (public.puede_area('musica'));
-- (solo la función "samply" escribe aquí, con la service_role key)

do $$ begin alter publication supabase_realtime add table public.samply_eventos;
exception when duplicate_object then null; end $$;

-- ============ 3. Configuración interna ============
create table if not exists public.samply_config (
  clave text primary key,
  valor text not null
);
alter table public.samply_config enable row level security;
-- Sin políticas: solo la service_role (la función) la lee y la escribe.
