// Edge Function "samply": conecta la Bitácora con Samply (https://docs.samply.app/api/introduction.html).
// El token de Samply vive solo aquí, como secreto SAMPLY_TOKEN: nunca llega al navegador.
// Despliégala con "Verify JWT" APAGADO: la función revisa la sesión ella misma, y Samply necesita
// poder mandar sus webhooks sin sesión (esos se verifican con la firma "Standard Webhooks").
//
// Desde la app (POST con la sesión de alguien de Música o de la PM):
//   {accion:"proyectos"}                                → proyectos de Samply
//   {accion:"carpetas", projectid}                      → carpetas de un proyecto
//   {accion:"cancion", projectid, folderid?}            → versiones, escuchas y comentarios de la canción
//   {accion:"liga", projectid, folderid?, nombre}       → crea una liga (player) para compartir
//   {accion:"webhook"}  (solo PM o desarrollador)       → registra el webhook de esta función en Samply
// Desde Samply (webhook firmado): guarda el evento en samply_eventos (subida terminada, comentario nuevo).
import { createClient } from "npm:@supabase/supabase-js@2.45.4";

const API = "https://samply.app/api/v0";
const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });

const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
  auth: { persistSession: false, autoRefreshToken: false },
});

async function samply(path: string, init: RequestInit = {}) {
  const token = Deno.env.get("SAMPLY_TOKEN");
  if (!token) throw new Error("Falta el secreto SAMPLY_TOKEN en Supabase (Edge Functions → Secrets).");
  const r = await fetch(API + path, {
    ...init,
    headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json", ...(init.headers || {}) },
  });
  const txt = await r.text();
  let data: any = null;
  try { data = txt ? JSON.parse(txt) : null; } catch { data = txt; }
  if (!r.ok) {
    const msg = (data && (data.error?.message || data.message || data.error)) || txt || r.statusText;
    throw new Error(r.status === 401 ? "Samply rechazó el token (revisa SAMPLY_TOKEN)." : `Samply respondió ${r.status}: ${String(msg).slice(0, 200)}`);
  }
  return data;
}
// Las respuestas de lista pueden venir como arreglo o como {data:[…]}
const lista = (x: any) => (Array.isArray(x) ? x : Array.isArray(x?.data) ? x.data : Array.isArray(x?.items) ? x.items : []);
const texto = (html: string) => String(html || "").replace(/<br\s*\/?>/gi, "\n").replace(/<[^>]+>/g, "").replace(/&nbsp;/g, " ")
  .replace(/&amp;/g, "&").replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&quot;/g, '"').replace(/&#39;/g, "'").trim();

// ---------- Webhook de Samply (Standard Webhooks) ----------
async function secretoWebhook() {
  const env = Deno.env.get("SAMPLY_WEBHOOK_SECRET");
  if (env) return env;
  const { data } = await admin.from("samply_config").select("valor").eq("clave", "webhook_secret").maybeSingle();
  return data?.valor || "";
}
async function firmaValida(req: Request, cuerpo: string) {
  const id = req.headers.get("webhook-id") || "", ts = req.headers.get("webhook-timestamp") || "", firmas = req.headers.get("webhook-signature") || "";
  const secreto = await secretoWebhook();
  if (!secreto || !id || !ts || !firmas) return false;
  if (Math.abs(Date.now() / 1000 - Number(ts)) > 300) return false;  // más de 5 minutos: posible repetición
  const clave = Uint8Array.from(atob(secreto.replace(/^whsec_/, "")), (c) => c.charCodeAt(0));
  const k = await crypto.subtle.importKey("raw", clave, { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const sig = new Uint8Array(await crypto.subtle.sign("HMAC", k, new TextEncoder().encode(`${id}.${ts}.${cuerpo}`)));
  const esperada = btoa(String.fromCharCode(...sig));
  return firmas.split(" ").some((f) => f.split(",")[1] === esperada);
}
async function recibirWebhook(req: Request) {
  const cuerpo = await req.text();
  if (!(await firmaValida(req, cuerpo))) return json({ error: "Firma inválida." }, 400);
  const ev = JSON.parse(cuerpo || "{}");
  const despues = ev?.data?.after || {};
  await admin.from("samply_eventos").upsert({
    id: ev.id || req.headers.get("webhook-id"),
    tipo: ev.type || "",
    projectid: ev.projectid || null,
    boxid: ev.boxid || null,
    box_nombre: ev.boxName || despues.name || null,
    mensaje: despues.object === "comment" ? texto(despues.message).slice(0, 2000) : null,
    autor: despues.creator?.displayName || null,
    payload: ev,
  }, { onConflict: "id", ignoreDuplicates: true });
  return json({ ok: true });
}

// ---------- Datos de una canción (carpeta o proyecto completo) ----------
async function datosCancion(projectid: string, folderid?: string) {
  const [todos, insights] = await Promise.all([
    samply(`/projects/${projectid}/all`),
    samply(`/projects/${projectid}/insights?limit=100`).catch(() => []),
  ]);
  const cajas = lista(todos);
  const porId = new Map(cajas.map((b: any) => [b.id, b]));
  // Cajas que pertenecen a la canción: todo lo que cuelga de su carpeta (o todo el proyecto)
  const dentro = new Set<string>();
  const agregar = (id: string) => {
    if (dentro.has(id)) return; dentro.add(id);
    const b: any = porId.get(id); (b?.children || []).forEach((c: any) => agregar(c.id));
  };
  if (folderid) agregar(folderid); else cajas.forEach((b: any) => dentro.add(b.id));
  const vivas = cajas.filter((b: any) => dentro.has(b.id) && !b.trashed && b.id !== folderid);
  const enStack = new Set(vivas.filter((b: any) => b.object === "stack").flatMap((s: any) => (s.children || []).map((c: any) => c.id)));
  const archivos = [
    ...vivas.filter((b: any) => b.object === "stack").map((s: any) => ({
      id: s.id, nombre: s.name, tipo: "stack",
      versiones: (s.children || []).map((c: any) => ({ id: c.id, nombre: c.name, duracion: (porId.get(c.id) as any)?.duration || null, creado: (porId.get(c.id) as any)?.timeCreated || null })),
    })),
    ...vivas.filter((b: any) => b.object === "file" && !enStack.has(b.id)).map((f: any) => ({
      id: f.id, nombre: f.name, tipo: "file", versiones: [{ id: f.id, nombre: f.name, duracion: f.duration || null, creado: f.timeCreated || null }],
    })),
  ];
  const idsArchivos = archivos.flatMap((a) => a.versiones.map((v: any) => v.id));
  const ids = new Set([...idsArchivos, ...archivos.map((a) => a.id)]);
  const escuchas = lista(insights).filter((i: any) => !i.boxid || ids.has(i.boxid) || !folderid).map((i: any) => ({
    tipo: i.type, quien: i.userName || null, completo: typeof i.completion === "number" ? Math.round(i.completion * 100) : null,
    archivo: i.name || (porId.get(i.boxid) as any)?.name || "", ciudad: [i.city, i.country].filter(Boolean).join(", "), cuando: i.timeCreated,
  }));
  // Comentarios de las versiones más recientes (máx. 8 archivos para no tardar)
  const recientes = archivos.map((a) => a.versiones[a.versiones.length - 1]?.id).filter(Boolean).slice(0, 8);
  const coms = await Promise.all(recientes.map((fid: string) =>
    samply(`/projects/${projectid}/files/${fid}/comments`).then((cs: any) => lista(cs).map((c: any) => ({
      archivo: (porId.get(fid) as any)?.name || "", texto: texto(c.message).slice(0, 1000), autor: c.creator?.displayName || "Alguien",
      segundo: typeof c.audioTimestamp === "number" ? c.audioTimestamp : null, resuelto: !!c.completed, respuesta: !!c.isReply, cuando: c.timeCreated,
    }))).catch(() => [])));
  return { archivos, escuchas, comentarios: coms.flat().sort((a: any, b: any) => (b.cuando || 0) - (a.cuando || 0)) };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "Método no permitido." }, 405);
  if (req.headers.get("webhook-signature")) return recibirWebhook(req);

  // Quién llama: alguien de Música (o PM / desarrollador)
  const jwt = (req.headers.get("Authorization") || "").replace(/^Bearer\s+/i, "");
  const { data: { user } } = await admin.auth.getUser(jwt);
  if (!user) return json({ error: "Tu sesión expiró. Vuelve a entrar." }, 401);
  const { data: yo } = await admin.from("perfiles").select("rol,area,areas").eq("id", user.id).single();
  const total = ["pm", "desarrollador"].includes(yo?.rol);
  if (!total && yo?.area !== "musica" && !(yo?.areas || []).includes("musica")) return json({ error: "Solo el equipo de Música puede usar Samply." }, 403);

  const body = await req.json().catch(() => ({}));
  try {
    if (body.accion === "proyectos") {
      const ps = lista(await samply("/projects"));
      return json({ proyectos: ps.map((p: any) => ({ id: p.id, nombre: p.name, color: p.color || null, portada: p.artwork || null, modificado: p.timeModified || null })) });
    }
    if (body.accion === "carpetas") {
      const fs = lista(await samply(`/projects/${encodeURIComponent(body.projectid)}/folders`));
      return json({ carpetas: fs.filter((f: any) => !f.trashed).map((f: any) => ({ id: f.id, nombre: f.name })) });
    }
    if (body.accion === "cancion") {
      return json(await datosCancion(encodeURIComponent(body.projectid), body.folderid ? String(body.folderid) : undefined));
    }
    if (body.accion === "liga") {
      const p = await samply("/players", { method: "POST", body: JSON.stringify({
        name: String(body.nombre || "Canción").slice(0, 120), projectid: body.projectid, ...(body.folderid ? { folderid: body.folderid } : {}),
        options: { comments: true, downloads: false, stacks: true },
      }) });
      return json({ id: p.id, playerUrl: p.playerUrl });
    }
    if (body.accion === "webhook") {
      if (!total) return json({ error: "Solo la PM o el desarrollador registran el webhook." }, 403);
      const url = `${Deno.env.get("SUPABASE_URL")}/functions/v1/${body.funcion || "samply"}`;
      const w = await samply("/webhooks", { method: "POST", body: JSON.stringify({ label: "Bitácora Tiempo de Dios", url, events: ["upload.completed", "comment.created"] }) });
      if (w?.secret) await admin.from("samply_config").upsert({ clave: "webhook_secret", valor: w.secret });
      return json({ ok: true, id: w?.id, url });
    }
    return json({ error: "Acción desconocida." }, 400);
  } catch (e) {
    return json({ error: (e as Error).message }, 502);
  }
});
