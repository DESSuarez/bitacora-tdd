// Configuración pública de Supabase. Está versionada a propósito:
// la "anon key" es pública por diseño (la protección está en las reglas RLS de supabase/schema.sql)
// y así la app ya no depende de un archivo que solo existe en el servidor.
// Si existe app/config.js (no versionado), lo que tenga reemplaza estos valores.
// Nunca pongas aquí la "service_role key".
window.BITACORA_CONFIG = {
  supabaseUrl: "https://zhzqvetehynndfjbrzti.supabase.co",
  supabaseAnonKey: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InpoenF2ZXRlaHlubmRmamJyenRpIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTM3Mjc3NjgsImV4cCI6MjEwOTMwMzc2OH0.ZhsazISy5Azt7i14qFeHKjcSPNQzXJeeAGcPAoEzjqw"
};
