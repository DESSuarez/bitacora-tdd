-- Bitácora Tiempo de Dios · migración 008: avisos automáticos por correo
-- Antes de correrla: despliega la Edge Function "avisos" y agrégale los secretos SMTP_USER y SMTP_PASS (ver README).
-- Ejecútala una vez en Supabase → SQL Editor → New query → Run. Se puede volver a correr sin error.

-- Registro de lo que ya se envió: evita mandar el mismo aviso dos veces el mismo día
create table if not exists public.avisos_enviados (
  dia date not null,
  destino text not null,
  tipo text not null,            -- 'personal' (vence mañana / atrasadas) o 'semanal' (resumen del sábado a la PM)
  enviado timestamptz not null default now(),
  primary key (dia, destino, tipo)
);
alter table public.avisos_enviados enable row level security;   -- sin políticas: solo la función (service_role) lo usa
delete from public.avisos_enviados where dia < current_date - 60;

-- Programación diaria: 14:00 UTC = 8:00 en el centro de México
create extension if not exists pg_cron;
create extension if not exists pg_net;

select cron.unschedule('bitacora-avisos') where exists (select 1 from cron.job where jobname = 'bitacora-avisos');
select cron.schedule(
  'bitacora-avisos',
  '0 14 * * *',
  $$
  select net.http_post(
    url := 'https://zhzqvetehynndfjbrzti.supabase.co/functions/v1/avisos',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      -- anon key (pública): la función no acepta parámetros peligrosos y no repite envíos del día
      'Authorization', 'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InpoenF2ZXRlaHlubmRmamJyenRpIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTM3Mjc3NjgsImV4cCI6MjEwOTMwMzc2OH0.ZhsazISy5Azt7i14qFeHKjcSPNQzXJeeAGcPAoEzjqw'
    ),
    body := '{}'::jsonb,
    timeout_milliseconds := 60000
  );
  $$
);

-- Para revisar: select * from cron.job_run_details where jobid = (select jobid from cron.job where jobname = 'bitacora-avisos') order by start_time desc limit 5;
-- Para ver lo enviado: select * from public.avisos_enviados order by enviado desc limit 20;
