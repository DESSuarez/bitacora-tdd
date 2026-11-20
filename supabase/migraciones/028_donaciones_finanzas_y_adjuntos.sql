-- Bitácora Tiempo de Dios · migración 028: donaciones recibidas en Finanzas y archivos en Sugerencias
-- 1) Las donaciones recibidas viven en Finanzas.
-- Finanzas (tabla «ingresos») es la fuente única del dinero que entra. Una donación de Personas
-- (crm_donaciones) es el compromiso; cuando se recibe, queda ligada a su ingreso en Finanzas
-- (columna «ingreso») y el monto que cuenta es el de ese ingreso. No se duplica nada.
-- · Una donación solo puede pasar a «recibida» si tiene su ingreso ligado.
-- · Si en Finanzas se borra el ingreso, la donación regresa sola a «comprometida».
-- · Un ingreso se liga a una sola donación.
-- No cambia nada de las tablas de Finanzas.
-- Ejecútala una vez en Supabase → SQL Editor → Run. Se puede volver a correr sin error.

alter table public.crm_donaciones add column if not exists ingreso uuid references public.ingresos(id) on delete set null;
create unique index if not exists crm_donaciones_ingreso on public.crm_donaciones (ingreso) where ingreso is not null;

create or replace function public.crm_donacion_coherente()
returns trigger language plpgsql as $$
begin
  -- se borró (o se desligó) el ingreso en Finanzas: la donación vuelve a estar comprometida
  if tg_op = 'UPDATE' and old.ingreso is not null and new.ingreso is null and new.estado = 'recibida' then
    new.estado := 'comprometida';
  end if;
  -- para estar «recibida» tiene que estar registrada en Finanzas
  if new.estado = 'recibida' and new.ingreso is null and (tg_op = 'INSERT' or old.estado is distinct from 'recibida') then
    raise exception 'Una donación recibida se registra como ingreso en Finanzas: liga su ingreso.';
  end if;
  return new;
end $$;
drop trigger if exists crm_donaciones_coherente on public.crm_donaciones;
create trigger crm_donaciones_coherente before insert or update on public.crm_donaciones
  for each row execute function public.crm_donacion_coherente();

-- 2) Sugerencias con archivos (capturas, documentos, .zip con prompts). Bucket privado «sugerencias»,
--    ruta <usuario>/<sugerencia>/<archivo>, máx. 50 MB por archivo. Todo el equipo los puede abrir.
alter table public.sugerencias add column if not exists archivos jsonb not null default '[]'::jsonb check (pg_column_size(archivos) < 20000);
insert into storage.buckets (id, name, public, file_size_limit) values ('sugerencias', 'sugerencias', false, 52428800)
on conflict (id) do update set public = false, file_size_limit = excluded.file_size_limit;
drop policy if exists sugerencias_archivos_leer on storage.objects;
create policy sugerencias_archivos_leer on storage.objects for select to authenticated using (bucket_id = 'sugerencias');
drop policy if exists sugerencias_archivos_subir on storage.objects;
create policy sugerencias_archivos_subir on storage.objects for insert to authenticated
  with check (bucket_id = 'sugerencias' and (storage.foldername(name))[1] = auth.uid()::text);
drop policy if exists sugerencias_archivos_borrar on storage.objects;
create policy sugerencias_archivos_borrar on storage.objects for delete to authenticated
  using (bucket_id = 'sugerencias' and ((storage.foldername(name))[1] = auth.uid()::text or public.es_pm()));

insert into public.migraciones_aplicadas (nombre) values ('028_donaciones_finanzas_y_adjuntos') on conflict (nombre) do nothing;
