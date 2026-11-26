// Edge Function «stripe»: los depósitos de Stripe (payouts a la cuenta del banco) quedan como ingresos de Finanzas.
// Despliégala con el nombre «stripe» y «Verify JWT» APAGADO (Stripe llama al webhook sin sesión).
//
// · Webhook (POST con cabecera Stripe-Signature): payout.paid → crea el ingreso; payout.failed / payout.canceled → lo quita.
// · {accion:"sincronizar", desde?:"YYYY-MM-DD"} (Finanzas, PM o desarrollador): trae los depósitos pagados desde esa fecha
//   (por omisión, 1 de enero del año) y registra los que falten. Sirve para el arranque y por si se perdió un aviso.
// · {accion:"estado"}: si está conectada.
// Cada ingreso lleva data.stripe_id (índice único, migración 032): nunca se registra dos veces el mismo depósito.
//
// Secretos: STRIPE_SECRET_KEY (de preferencia una llave restringida con permiso de solo lectura en Payouts) y
// STRIPE_WEBHOOK_SECRET (whsec_…, del endpoint del webhook en Stripe).
import { createClient } from "npm:@supabase/supabase-js@2.45.4";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const env = (k: string, d = "") => Deno.env.get(k) || d;
const KEY = env("STRIPE_SECRET_KEY"), WHSEC = env("STRIPE_WEBHOOK_SECRET");
const TZ = "America/Mexico_City";
const json = (b: unknown, s = 200) => new Response(JSON.stringify(b), { status: s, headers: { ...cors, "Content-Type": "application/json" } });
const fechaMx = (seg: number) => new Intl.DateTimeFormat("en-CA", { timeZone: TZ }).format(new Date(seg * 1000));

type Payout = { id: string; amount: number; currency: string; arrival_date: number; status: string; description?: string | null; statement_descriptor?: string | null };

// Verifica la firma de Stripe: v1 = HMAC-SHA256(secreto, "t.cuerpo"), con 5 minutos de tolerancia
async function firmaValida(cuerpo: string, cabecera: string) {
  const partes = Object.fromEntries(cabecera.split(",").map((x) => x.split("=", 2) as [string, string]));
  const t = partes.t, firmas = cabecera.split(",").filter((x) => x.startsWith("v1=")).map((x) => x.slice(3));
  if (!t || !firmas.length || Math.abs(Date.now() / 1000 - Number(t)) > 300) return false;
  const k = await crypto.subtle.importKey("raw", new TextEncoder().encode(WHSEC), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const mac = Array.from(new Uint8Array(await crypto.subtle.sign("HMAC", k, new TextEncoder().encode(`${t}.${cuerpo}`)))).map((b) => b.toString(16).padStart(2, "0")).join("");
  return firmas.includes(mac);
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "Método no permitido." }, 405);
  const admin = createClient(env("SUPABASE_URL"), env("SUPABASE_SERVICE_ROLE_KEY"), { auth: { persistSession: false, autoRefreshToken: false } });
  const crudo = await req.text();

  async function registrar(p: Payout) {
    const { data: ya } = await admin.from("ingresos").select("id").eq("data->>stripe_id", p.id).maybeSingle();
    if (ya) return false;
    const moneda = (p.currency || "mxn").toUpperCase();
    const { error } = await admin.from("ingresos").insert({
      fecha: fechaMx(p.arrival_date),
      concepto: `Depósito de Stripe${p.description ? " · " + p.description : ""}`.slice(0, 200),
      monto: p.amount / 100,
      area: "general",
      categoria: "Stripe",
      data: { fuente: "Stripe", referencia: p.id, stripe_id: p.id, origen: "stripe", moneda, ...(moneda !== "MXN" ? { nota: `Monto en ${moneda}` } : {}) },
      registrado_por: null,
    });
    if (error && !/duplicate|23505/.test(error.message + (error.code || ""))) throw new Error(error.message);
    return !error;
  }

  // ---------- Webhook de Stripe ----------
  const firma = req.headers.get("stripe-signature");
  if (firma) {
    if (!WHSEC || !(await firmaValida(crudo, firma))) return json({ error: "Firma no válida." }, 400);
    const ev = JSON.parse(crudo);
    const p = ev?.data?.object as Payout;
    try {
      if (ev.type === "payout.paid" && p?.id) await registrar(p);
      if ((ev.type === "payout.failed" || ev.type === "payout.canceled") && p?.id) await admin.from("ingresos").delete().eq("data->>stripe_id", p.id);
    } catch (e) { return json({ error: (e as Error).message }, 500); }
    return json({ ok: true });
  }

  // ---------- Acciones desde la app (Finanzas, PM o desarrollador) ----------
  let body: Record<string, unknown> = {};
  try { body = JSON.parse(crudo || "{}"); } catch { body = {}; }
  const jwt = (req.headers.get("Authorization") || "").replace(/^Bearer\s+/i, "");
  const { data: { user } } = await admin.auth.getUser(jwt);
  if (!user) return json({ error: "Tu sesión expiró. Vuelve a entrar." }, 401);
  const { data: yo } = await admin.from("perfiles").select("rol,finanzas").eq("id", user.id).single();
  if (!yo || !(yo.finanzas || ["pm", "desarrollador"].includes(yo.rol))) return json({ error: "Solo Finanzas puede conectar Stripe." }, 403);

  if (body.accion === "estado") return json({ conectado: !!KEY, webhook: !!WHSEC });
  if (body.accion !== "sincronizar") return json({ error: "Acción desconocida." }, 400);
  if (!KEY) return json({ error: "Falta el secreto STRIPE_SECRET_KEY de la función «stripe»." }, 400);

  const desde = /^\d{4}-\d{2}-\d{2}$/.test(String(body.desde || "")) ? String(body.desde) : `${new Date().getFullYear()}-01-01`;
  const gte = Math.floor(new Date(desde + "T00:00:00-06:00").getTime() / 1000);
  let nuevos = 0, revisados = 0, despues = "";
  for (let i = 0; i < 20; i++) {
    const q = new URLSearchParams({ limit: "100", status: "paid", "arrival_date[gte]": String(gte) });
    if (despues) q.set("starting_after", despues);
    const r = await fetch(`https://api.stripe.com/v1/payouts?${q}`, { headers: { Authorization: `Bearer ${KEY}` } });
    const j = await r.json();
    if (!r.ok) return json({ error: j?.error?.message || "Stripe no respondió." }, 400);
    for (const p of (j.data || []) as Payout[]) { revisados++; try { if (await registrar(p)) nuevos++; } catch (e) { return json({ error: (e as Error).message }, 500); } }
    if (!j.has_more || !j.data?.length) break;
    despues = j.data[j.data.length - 1].id;
  }
  return json({ ok: true, nuevos, revisados, desde });
});
