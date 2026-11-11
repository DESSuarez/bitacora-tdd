-- Bitácora Tiempo de Dios · migración 009: "Sobre mí" en el perfil (carta de presentación)
-- Cada persona escribe su presentación; la PM también puede editarla.
-- Ejecútala una vez en Supabase → SQL Editor → New query → Run. Se puede volver a correr sin error.

alter table public.perfiles add column if not exists bio text;
alter table public.perfiles drop constraint if exists perfiles_bio_largo;
alter table public.perfiles add constraint perfiles_bio_largo check (bio is null or char_length(bio) <= 600);
