-- Bitácora Tiempo de Dios · migración 010: la función de avisos quedó desplegada como "bright-task"
-- (el código es supabase/functions/avisos). Reprograma el envío diario para llamarla con ese nombre.
-- Ejecútala una vez en Supabase → SQL Editor → New query → Run. Se puede volver a correr sin error.

select cron.unschedule('bitacora-avisos') where exists (select 1 from cron.job where jobname = 'bitacora-avisos');
select cron.schedule(
  'bitacora-avisos',
  '0 14 * * *',   -- 8:00 en el centro de México
  $$
  select net.http_post(
    url := 'https://zhzqvetehynndfjbrzti.supabase.co/functions/v1/bright-task',
    headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InpoenF2ZXRlaHlubmRmamJyenRpIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTM3Mjc3NjgsImV4cCI6MjEwOTMwMzc2OH0.ZhsazISy5Azt7i14qFeHKjcSPNQzXJeeAGcPAoEzjqw'),
    body := '{}'::jsonb,
    timeout_milliseconds := 60000
  );
  $$
);

-- Para revisar que quedó: select jobname, schedule, command from cron.job where jobname = 'bitacora-avisos';
