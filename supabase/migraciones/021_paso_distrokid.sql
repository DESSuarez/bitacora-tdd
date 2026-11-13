-- Bitácora Tiempo de Dios · migración 021: paso «Subir canción a plataformas (DistroKid)»
-- Se agrega como paso 15, justo después del splitsheet firmado (14). Todos los pasos desde el 15 suben un número
-- y el checklist pasa de 23 a 24 pasos. Reacomoda las canciones y sus pendientes que ya existían. Solo se aplica una vez.
-- Ejecútala una vez en Supabase → SQL Editor → New query → Run. Se puede volver a correr sin error.

update public.canciones c set
  checklist = coalesce((
      select jsonb_object_agg(case when k.key ~ '^\d+$' and k.key::int >= 15 then (k.key::int + 1)::text else k.key end, k.value)
      from jsonb_each(c.checklist) k), '{}'::jsonb),
  archivos = coalesce((
      select jsonb_agg(case when a->>'campo' ~ '^paso\d+$' and substring(a->>'campo' from 5)::int >= 15
                            then jsonb_set(a, '{campo}', to_jsonb('paso' || (substring(a->>'campo' from 5)::int + 1)))
                            else a end)
      from jsonb_array_elements(c.archivos) a), '[]'::jsonb),
  pasos_version = 3
where c.pasos_version = 2;

-- Las canciones nuevas ya nacen con la numeración de 24 pasos
alter table public.canciones alter column pasos_version set default 3;

-- Pendientes de canciones: su número de paso también sube desde el 15
update public.tareas set data = jsonb_set(data, '{paso}', to_jsonb((data->>'paso')::int + 1)) || '{"pasos_version":3}'::jsonb
where data ? 'cancion_id' and data->>'paso' ~ '^\d+$' and (data->>'paso')::int >= 15
  and coalesce(data->>'pasos_version', '1') = '2';
