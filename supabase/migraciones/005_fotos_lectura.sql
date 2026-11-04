-- Bitácora Tiempo de Dios · migración 005: permiso de lectura en el bucket "fotos"
-- Storage pide permiso de lectura para sobrescribir o borrar archivos. Con esto la app
-- puede borrar la foto anterior cuando alguien sube una nueva (si no, solo se acumulan).
-- Ejecútala una vez en Supabase → SQL Editor → New query → Run. Se puede volver a correr sin error.

drop policy if exists fotos_leer on storage.objects;
create policy fotos_leer on storage.objects for select to authenticated
  using (bucket_id = 'fotos');
