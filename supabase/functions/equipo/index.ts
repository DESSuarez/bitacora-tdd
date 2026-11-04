// Edge Function "equipo": administración del equipo desde la app (solo PM).
// Usa la service_role key, que Supabase inyecta como variable de entorno: nunca llega al navegador.
// Acciones (POST con JSON):
//   {accion:"listar"}                                  → correos y estado de cada usuario
//   {accion:"invitar", email, nombre, rol, area, redirectTo} → envía la invitación y asigna rol y área
//   {accion:"reenviar", email, redirectTo}             → vuelve a mandar la invitación
//   {accion:"quitar", id}                              → borra el usuario (y su perfil)
import { createClient } from "npm:@supabase/supabase-js@2.45.4";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const ROLES = ["pm", "desarrollador", "lider", "colaborador"];
const ACCESO_TOTAL = ["pm", "desarrollador"];
const AREAS = ["formacion", "musica", "audiovisual"];

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "Método no permitido." }, 405);

  const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  // Quién llama: solo una PM puede usar esta función
  const jwt = (req.headers.get("Authorization") || "").replace(/^Bearer\s+/i, "");
  const { data: { user } } = await admin.auth.getUser(jwt);
  if (!user) return json({ error: "Tu sesión expiró. Vuelve a entrar." }, 401);
  const { data: yo } = await admin.from("perfiles").select("rol").eq("id", user.id).single();
  if (!ACCESO_TOTAL.includes(yo?.rol)) return json({ error: "Solo la project manager puede administrar el equipo." }, 403);

  const body = await req.json().catch(() => ({}));

  if (body.accion === "listar") {
    const { data, error } = await admin.auth.admin.listUsers({ perPage: 1000 });
    if (error) return json({ error: error.message }, 500);
    return json({
      usuarios: data.users.map((u) => ({
        id: u.id,
        email: u.email,
        invitado: u.invited_at || null,
        activo: !!u.last_sign_in_at,
        ultimo: u.last_sign_in_at || null,
      })),
    });
  }

  if (body.accion === "invitar" || body.accion === "reenviar") {
    const email = String(body.email || "").trim().toLowerCase();
    if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) return json({ error: "El correo no parece válido." }, 400);
    const redirectTo = typeof body.redirectTo === "string" ? body.redirectTo : undefined;

    if (body.accion === "reenviar") {
      const { error } = await admin.auth.admin.inviteUserByEmail(email, { redirectTo });
      if (error) return json({ error: "No se pudo reenviar: " + error.message }, 400);
      return json({ ok: true });
    }

    const nombre = String(body.nombre || "").trim().slice(0, 60) || email.split("@")[0];
    const rol = ROLES.includes(body.rol) ? body.rol : "colaborador";
    const area = ACCESO_TOTAL.includes(rol) ? null : AREAS.includes(body.area) ? body.area : null;
    if (!ACCESO_TOTAL.includes(rol) && !area) return json({ error: "Elige el área de la persona." }, 400);

    const { data, error } = await admin.auth.admin.inviteUserByEmail(email, { data: { nombre }, redirectTo });
    if (error) {
      const ya = /already|registered|exists/i.test(error.message);
      return json({ error: ya ? "Ese correo ya tiene cuenta en la bitácora." : "No se pudo invitar: " + error.message }, 400);
    }
    // El trigger crear_perfil ya creó la fila; aquí se le asigna rol y área
    const { error: e2 } = await admin.from("perfiles").upsert({ id: data.user.id, nombre, rol, area });
    if (e2) return json({ error: "Se envió la invitación, pero no se pudo asignar el rol: " + e2.message }, 500);
    return json({ ok: true, id: data.user.id });
  }

  if (body.accion === "quitar") {
    const id = String(body.id || "");
    if (!id) return json({ error: "Falta la persona." }, 400);
    if (id === user.id) return json({ error: "No puedes quitar el acceso a tu propia cuenta." }, 400);
    const { error } = await admin.auth.admin.deleteUser(id);
    if (error) return json({ error: "No se pudo quitar el acceso: " + error.message }, 500);
    return json({ ok: true });
  }

  return json({ error: "Acción desconocida." }, 400);
});
