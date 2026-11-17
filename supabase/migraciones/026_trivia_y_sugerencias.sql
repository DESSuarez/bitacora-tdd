-- Bitácora Tiempo de Dios · migración 026: trivia del día, sugerencias y registro de scripts corridos
-- · trivia_respuestas: lo que cada quien contestó en la trivia del día (una vez por día) → racha 🔥.
-- · sugerencias: cambios que propone el equipo; la PM o el desarrollador los aprueban y les dan seguimiento.
-- · Quien es responsable de una tarea puede editarla aunque sea de otra área.
-- · migraciones_aplicadas: qué scripts ya se corrieron, para que el desarrollador vea en la app los pendientes.
--   A partir de ahora, cada migración termina registrándose aquí sola.
-- Ejecútala una vez en Supabase → SQL Editor → Run. Se puede volver a correr sin error.

-- ============ Trivia del día ============
create table if not exists public.trivia_respuestas (
  usuario uuid not null default auth.uid() references public.perfiles(id) on delete cascade,
  fecha date not null,
  aciertos int not null check (aciertos between 0 and 20),
  total int not null check (total between 1 and 20),
  respuestas jsonb not null default '[]'::jsonb check (pg_column_size(respuestas) < 8000),
  creado timestamptz not null default now(),
  primary key (usuario, fecha)
);
alter table public.trivia_respuestas enable row level security;
drop policy if exists trivia_ver on public.trivia_respuestas;
create policy trivia_ver on public.trivia_respuestas for select to authenticated using (true);
-- Cada quien guarda la suya, una vez por día (con un día de margen por la zona horaria)
drop policy if exists trivia_contestar on public.trivia_respuestas;
create policy trivia_contestar on public.trivia_respuestas for insert to authenticated
  with check (usuario = auth.uid() and fecha between current_date - 1 and current_date + 1);

-- ============ Sugerencias ============
create table if not exists public.sugerencias (
  id uuid primary key default gen_random_uuid(),
  autor uuid default auth.uid() references public.perfiles(id) on delete set null,
  tipo text not null default 'mejora' check (tipo in ('mejora','error','idea')),
  area text,
  titulo text not null check (char_length(titulo) between 3 and 140),
  detalle text not null default '' check (char_length(detalle) <= 4000),
  estado text not null default 'nueva' check (estado in ('nueva','aprobada','en_proceso','hecha','rechazada')),
  respuesta text not null default '' check (char_length(respuesta) <= 2000),
  creado timestamptz not null default now(),
  actualizado timestamptz not null default now(),
  resuelto_por uuid
);
create or replace function public.sugerencia_actualizada()
returns trigger language plpgsql as $$ begin new.actualizado = now(); return new; end $$;
drop trigger if exists sugerencias_actualizado on public.sugerencias;
create trigger sugerencias_actualizado before update on public.sugerencias for each row execute function public.sugerencia_actualizada();
alter table public.sugerencias enable row level security;
drop policy if exists sugerencias_ver on public.sugerencias;
create policy sugerencias_ver on public.sugerencias for select to authenticated using (true);
-- Proponer: a nombre propio, como «nueva», y máximo 5 abiertas por persona (para que no se descontrolen)
drop policy if exists sugerencias_proponer on public.sugerencias;
create policy sugerencias_proponer on public.sugerencias for insert to authenticated
  with check (autor = auth.uid() and estado = 'nueva' and respuesta = ''
    and (select count(*) from public.sugerencias s where s.autor = auth.uid() and s.estado in ('nueva','aprobada','en_proceso')) < 5);
drop policy if exists sugerencias_gestionar on public.sugerencias;
create policy sugerencias_gestionar on public.sugerencias for update to authenticated using (public.es_pm()) with check (public.es_pm());
drop policy if exists sugerencias_borrar on public.sugerencias;
create policy sugerencias_borrar on public.sugerencias for delete to authenticated
  using (public.es_pm() or (autor = auth.uid() and estado = 'nueva'));

-- ============ Tareas asignadas a alguien de otra área ============
-- Quien es responsable de una tarea (o de una de sus subtareas) puede editarla y completarla
-- (notas, ligas, archivos, cierre) aunque no esté en esa área. Crear y borrar sigue siendo del área.
drop policy if exists tareas_asignadas on public.tareas;
create policy tareas_asignadas on public.tareas for update to authenticated
  using (data->>'responsable_id' = auth.uid()::text
         or exists (select 1 from jsonb_array_elements(coalesce(data->'subtareas', '[]'::jsonb)) s where s->>'responsable_id' = auth.uid()::text))
  with check (data->>'responsable_id' = auth.uid()::text
         or exists (select 1 from jsonb_array_elements(coalesce(data->'subtareas', '[]'::jsonb)) s where s->>'responsable_id' = auth.uid()::text));

-- Archivos entregables (<área>/<tarea>/…): cualquiera del área (también las áreas adicionales) o el responsable de la tarea
create or replace function public.puede_entregable(carpeta_area text, tarea text)
returns boolean language sql stable security definer set search_path = public as $$
  select public.puede_area(carpeta_area) or exists (
    select 1 from public.tareas t where t.id = tarea and (t.data->>'responsable_id' = auth.uid()::text
      or exists (select 1 from jsonb_array_elements(coalesce(t.data->'subtareas', '[]'::jsonb)) s where s->>'responsable_id' = auth.uid()::text)));
$$;
drop policy if exists entregables_subir on storage.objects;
create policy entregables_subir on storage.objects for insert to authenticated
  with check (bucket_id = 'entregables' and public.puede_entregable((storage.foldername(name))[1], (storage.foldername(name))[2]));
drop policy if exists entregables_borrar on storage.objects;
create policy entregables_borrar on storage.objects for delete to authenticated
  using (bucket_id = 'entregables' and public.puede_entregable((storage.foldername(name))[1], (storage.foldername(name))[2]));

-- ============ Scripts (migraciones) ya corridos ============
create table if not exists public.migraciones_aplicadas (
  nombre text primary key,
  aplicada timestamptz not null default now(),
  por uuid default auth.uid()
);
alter table public.migraciones_aplicadas enable row level security;
drop policy if exists migraciones_ver on public.migraciones_aplicadas;
create policy migraciones_ver on public.migraciones_aplicadas for select to authenticated using (public.es_pm());
drop policy if exists migraciones_marcar on public.migraciones_aplicadas;
create policy migraciones_marcar on public.migraciones_aplicadas for insert to authenticated with check (public.es_pm());

do $$ begin alter publication supabase_realtime add table public.trivia_respuestas;
exception when duplicate_object then null; end $$;
do $$ begin alter publication supabase_realtime add table public.sugerencias;
exception when duplicate_object then null; end $$;

-- Todas las anteriores ya se corrieron; esta también queda registrada
insert into public.migraciones_aplicadas (nombre) values
  ('002_perfil_y_fotos'),
  ('003_rol_desarrollador'),
  ('004_usuario'),
  ('005_fotos_lectura'),
  ('006_entregables'),
  ('007_operativo_y_varias_areas'),
  ('008_avisos_por_correo'),
  ('009_presentacion'),
  ('010_avisos_nombre_funcion'),
  ('011_perfil_propio'),
  ('012_entradas_formacion'),
  ('013_calendario_y_canciones'),
  ('014_portada'),
  ('015_ministerios_y_lanzamiento'),
  ('016_saludo'),
  ('017_finanzas'),
  ('018_samply'),
  ('019_activos'),
  ('020_ligas_limpias'),
  ('021_paso_distrokid'),
  ('022_legal_marketing_calendario'),
  ('023_agenda_por_ministerio'),
  ('024_dias_de_produccion'),
  ('025_cancion_a_agenda'),
  ('026_trivia_y_sugerencias')
on conflict (nombre) do nothing;
