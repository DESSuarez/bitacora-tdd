// Edge Function "crm": correos y WhatsApp de Operativo → Personas (migración 027).
// Despliégala con el nombre «crm» y con «Verify JWT» APAGADO (Meta llama al webhook sin sesión);
// la función revisa la sesión ella misma en las acciones privadas.
//
// Acciones (POST JSON {accion}):
//   · diario      → la llama pg_cron cada día a las 9:00 de México. No repite envíos (crm_mensajes.clave):
//                   1) invitación por correo 15 y 7 días antes de cada fecha de un cenáculo o evento con
//                      «invitar» (a quien acepta correos y no se ha registrado; máx. una invitación cada 6 días),
//                   2) recordatorio por WhatsApp 2 días antes a quien se registró (si WhatsApp está conectado),
//                   3) resumen para el equipo de Operativo: seguimientos de hoy y vencidos, cumpleaños,
//                   4) los lunes, a Finanzas: donaciones comprometidas que no han llegado.
//   · boletin     → {id, prueba?} manda un newsletter por tandas de 40 (la app la llama hasta terminar).
//   · prueba      → manda a tu correo un ejemplo de invitación.
//   · wa_recordar → {evento, fecha} manda ya el recordatorio de WhatsApp a quienes se registraron.
//   · wa_texto    → {persona, texto} responde por WhatsApp (solo dentro de las 24 h desde su último mensaje).
//   · estado      → qué está conectado (correo y WhatsApp).
// Webhook de WhatsApp (Meta): GET para verificar y POST con mensajes, botones y estados de entrega.
//
// Secretos: SMTP_USER y SMTP_PASS (los mismos de bright-task). Opcionales: SMTP_HOST, SMTP_PORT, APP_URL,
// CRM_REMITENTE (nombre que ve la gente; «Tiempo de Dios»), CRM_MAX_DIA (correos por corrida; 150).
// WhatsApp (Meta Cloud API): WA_TOKEN, WA_PHONE_ID, WA_VERIFY_TOKEN (lo inventas tú), WA_APP_SECRET (firma),
// WA_PLANTILLA (recordatorio_evento) y WA_IDIOMA (es_MX).
import { createClient } from "npm:@supabase/supabase-js@2.45.4";
import nodemailer from "npm:nodemailer@6.9.14";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
};
const env = (k: string, d = "") => Deno.env.get(k) || d;
const TZ = "America/Mexico_City";
const APP = env("APP_URL", "https://pm.tiempodedios.mx").replace(/\/+$/, "");
const REMITENTE = env("CRM_REMITENTE", "Tiempo de Dios");
const MAX_DIA = Number(env("CRM_MAX_DIA", "150"));
const WA = { token: env("WA_TOKEN"), phone: env("WA_PHONE_ID"), verify: env("WA_VERIFY_TOKEN"), secret: env("WA_APP_SECRET"),
  plantilla: env("WA_PLANTILLA", "recordatorio_evento"), idioma: env("WA_IDIOMA", "es_MX") };
const waListo = () => !!(WA.token && WA.phone);
const DIAS = ["domingo", "lunes", "martes", "miércoles", "jueves", "viernes", "sábado"];
const MESES = ["enero", "febrero", "marzo", "abril", "mayo", "junio", "julio", "agosto", "septiembre", "octubre", "noviembre", "diciembre"];

const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });
const esc = (s: unknown) => String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]!));
const hoyMx = () => new Intl.DateTimeFormat("en-CA", { timeZone: TZ }).format(new Date());
const deKey = (k: string) => new Date(k + "T12:00:00Z");
const aKey = (d: Date) => d.toISOString().slice(0, 10);
const sumar = (k: string, n: number) => { const d = deKey(k); d.setUTCDate(d.getUTCDate() + n); return aKey(d); };
const larga = (k: string) => { const d = deKey(k); return `${DIAS[d.getUTCDay()]} ${d.getUTCDate()} de ${MESES[d.getUTCMonth()]}`; };
const hora12 = (h: string) => { if (!h) return ""; const [H, M] = h.split(":").map(Number); return `${((H + 11) % 12) + 1}:${String(M).padStart(2, "0")} ${H < 12 ? "a. m." : "p. m."}`; };
const primerNombre = (n: string) => String(n || "").trim().split(/\s+/)[0] || "";
// «Este martes 24 de noviembre a las 8:00 p. m.» (igual que cuandoMsg() en la app)
function cuandoMsg(d: Record<string, any>, f: string) {
  const dias = Math.round((deKey(f).getTime() - deKey(hoyMx()).getTime()) / 864e5), x = deKey(f);
  const pre = dias === 0 ? "Hoy, " : dias === 1 ? "Mañana, " : dias > 1 && dias < 7 ? "Este " : "El ";
  return `${pre}${DIAS[x.getUTCDay()]} ${x.getUTCDate()} de ${MESES[x.getUTCMonth()]}${d.hora ? " a las " + hora12(d.hora) : ""}`;
}

type Ev = { id: string; data: Record<string, any> };
// ¿El evento ocurre ese día? (misma regla que evento_ocurre en SQL y ocurrencias() en la app)
function ocurre(d: Record<string, any>, f: string) {
  const ini = d.fecha, rep = d.repetir || "";
  if (!ini || f < ini) return false;
  if (rep && d.hasta && f > d.hasta) return false;
  if ((d.excepciones || []).includes(f)) return false;
  const dias = Math.round((deKey(f).getTime() - deKey(ini).getTime()) / 864e5);
  if (!rep) return f === ini;
  if (rep === "semanal") return dias % 7 === 0;
  if (rep === "quincenal") return dias % 14 === 0;
  if (rep === "mensual") return f.slice(8) === ini.slice(8);
  if (rep === "anual") return f.slice(5) === ini.slice(5);
  return false;
}
const conRegistro = (d: Record<string, any>) => d.tipo === "cenaculo" || d.registro === true || d.registro === "true";

// ---------- Plantilla de correo para la comunidad (no la de la bitácora) ----------
// Logo incrustado (cid): muchos buzones bloquean las imágenes externas. Es el mismo de bright-task.
const LOGO_CID = "logo-tdd";
const LOGO_URL = `${APP}/icono-512.png`;
function plantilla(o: { titulo: string; previa?: string; cuerpo: string; boton?: string; liga?: string; imagen?: string; token?: string; tipo: string }) {
  const baja = o.token ? `${APP}/registro/?baja=${o.token}` : "";
  return `<!doctype html><html lang="es"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>${esc(o.titulo)}</title></head>
<body style="margin:0;padding:0;background:#F4F7F7;font-family:Arial,Helvetica,sans-serif;color:#1B1C1A">
<div style="display:none;max-height:0;overflow:hidden">${esc(o.previa || "")}</div>
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#F4F7F7;padding:28px 12px"><tr><td align="center">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:580px;background:#FFFFFF;border-radius:16px;overflow:hidden;border:1px solid #DDE5E5">
<tr><td style="background:#1B1C1A;padding:24px 32px 20px;border-bottom:6px solid #F2B33D">
<img src="cid:${LOGO_CID}" width="44" height="44" alt="Tiempo de Dios" style="display:block;border-radius:10px;margin-bottom:12px">
<div style="font-size:11px;letter-spacing:2px;text-transform:uppercase;color:#A3ADAC;font-weight:bold">Tiempo de Dios · ${esc(o.tipo)}</div>
<div style="font-size:24px;line-height:1.25;font-weight:900;color:#FFFFFF;margin-top:6px">${esc(o.titulo)}</div></td></tr>
${o.imagen ? `<tr><td><img src="${esc(o.imagen)}" width="580" alt="" style="display:block;width:100%;height:auto"></td></tr>` : ""}
<tr><td style="padding:24px 32px 8px;font-size:16px;line-height:1.6">${o.cuerpo}
${o.boton && o.liga ? `<table role="presentation" cellpadding="0" cellspacing="0" style="margin:22px 0 26px"><tr><td style="background:#FF3D1A;border-radius:10px">
<a href="${esc(o.liga)}" style="display:inline-block;padding:14px 26px;color:#FFFFFF;font-weight:bold;font-size:16px;text-decoration:none">${esc(o.boton)}</a></td></tr></table>` : `<div style="height:18px"></div>`}</td></tr>
<tr><td style="padding:14px 32px 22px;border-top:1px solid #DDE5E5;font-size:12px;line-height:1.5;color:#5E6766">Recibes este correo porque te registraste en un evento de Tiempo de Dios.${baja ? ` <a href="${baja}" style="color:#5E6766">Ya no quiero recibir correos</a>.` : ""}</td></tr>
</table></td></tr></table></body></html>`;
}
// Texto del newsletter: párrafos separados por línea en blanco, **negritas**, ligas y {nombre}
function textoAHtml(t: string, nombre: string) {
  return String(t || "").replace(/\{nombre\}/g, nombre || "").split(/\n{2,}/).map((p) => p.trim()).filter(Boolean).map((p) =>
    `<p style="margin:0 0 14px">${esc(p).replace(/\*\*(.+?)\*\*/g, "<b>$1</b>").replace(/(https?:\/\/[^\s<]+)/g, '<a href="$1" style="color:#FF3D1A">$1</a>').replace(/\n/g, "<br>")}</p>`).join("");
}
function invitacion(p: any, ev: Ev, f: string, dias: number) {
  const d = ev.data, n = primerNombre(p.nombre);
  const liga = `${APP}/registro/?e=${encodeURIComponent(ev.id)}&f=${f}&t=${p.token}`;
  const cuando = `${larga(f)}${d.hora ? ` a las ${hora12(d.hora)}` : ""}`;
  return {
    asunto: dias <= 7 ? `${n ? n + ", t" : "T"}e esperamos el ${larga(f)}: ${d.titulo}` : `${d.titulo}: aparta el ${larga(f)}`,
    html: plantilla({ tipo: d.tipo === "cenaculo" ? "Cenáculo" : "Invitación", titulo: d.titulo || "Te invitamos", previa: `${cuando}${d.lugar ? " · " + d.lugar : ""}. Regístrate con un clic.`, token: p.token,
      cuerpo: `<p style="margin:0 0 14px">Hola${n ? ", " + esc(n) : ""}:</p>
<p style="margin:0 0 14px">${dias <= 7 ? "Ya casi es el" : "Queremos invitarte al"} <b>${esc(d.titulo)}</b>, el <b>${esc(cuando)}</b>${d.lugar ? ` en <b>${esc(d.lugar)}</b>` : ""}.</p>
${d.invitacion ? textoAHtml(d.invitacion, n) : `<p style="margin:0 0 14px">Será un tiempo para encontrarnos con Dios y en comunidad. Nos daría mucho gusto verte.</p>`}
<p style="margin:0">Regístrate con un clic para apartar tu lugar:</p>`,
      boton: "Sí, quiero ir", liga }),
  };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  const url = new URL(req.url);
  const admin = createClient(env("SUPABASE_URL"), env("SUPABASE_SERVICE_ROLE_KEY"), { auth: { persistSession: false, autoRefreshToken: false } });

  // ---------- Webhook de WhatsApp: verificación ----------
  if (req.method === "GET") {
    if (url.searchParams.get("hub.mode") === "subscribe" && WA.verify && url.searchParams.get("hub.verify_token") === WA.verify)
      return new Response(url.searchParams.get("hub.challenge") || "", { status: 200 });
    return new Response("No autorizado", { status: 403 });
  }
  if (req.method !== "POST") return json({ error: "Método no permitido." }, 405);
  const crudo = await req.text();
  let body: any = {};
  try { body = JSON.parse(crudo || "{}"); } catch { body = {}; }

  // ---------- Webhook de WhatsApp: mensajes, botones y estados ----------
  if (body.object === "whatsapp_business_account") {
    if (WA.secret) {
      const firma = (req.headers.get("x-hub-signature-256") || "").replace(/^sha256=/, "");
      const k = await crypto.subtle.importKey("raw", new TextEncoder().encode(WA.secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
      const mac = Array.from(new Uint8Array(await crypto.subtle.sign("HMAC", k, new TextEncoder().encode(crudo)))).map((b) => b.toString(16).padStart(2, "0")).join("");
      if (mac !== firma) return new Response("Firma no válida", { status: 401 });
    }
    for (const en of body.entry || []) for (const ch of en.changes || []) {
      const v = ch.value || {};
      for (const s of v.statuses || []) await admin.from("crm_mensajes").update({ estado: s.status, error: (s.errors?.[0]?.title || "").slice(0, 1000) }).eq("wa_id", s.id);
      for (const m of v.messages || []) {
        const tel = String(m.from || "").replace(/\D/g, "").slice(-10);
        const { data: ps } = await admin.from("crm_personas").select("id").eq("tel_digitos", tel).order("creado").limit(1);
        const pid = ps?.[0]?.id || null;
        const payload = m.button?.payload || m.interactive?.button_reply?.id || "";
        const texto = m.text?.body || m.button?.text || m.interactive?.button_reply?.title || `[${m.type}]`;
        let nota = "";
        const r = /^(si|no)\|([0-9a-f-]{36})$/.exec(payload);
        if (r) {
          const { data: a } = await admin.from("crm_asistencias").select("id,estado,evento,fecha,persona").eq("id", r[2]).maybeSingle();
          if (a && ["invitado", "registrado", "confirmo", "cancelo"].includes(a.estado)) {
            await admin.from("crm_asistencias").update({ estado: r[1] === "si" ? "confirmo" : "cancelo", marcado_por: null }).eq("id", a.id);
            nota = r[1] === "si" ? " → confirmó" : " → no podrá ir";
          }
        }
        await admin.from("crm_mensajes").insert({ persona: pid, canal: "whatsapp", direccion: "entrada", tipo: r ? "respuesta" : "texto",
          texto: (texto + nota + (pid ? "" : ` (de +${m.from})`)).slice(0, 4000), wa_id: m.id, estado: "recibido", creado_por: null });
      }
    }
    return json({ ok: true });
  }

  // ---------- Sesión (para las acciones privadas) ----------
  async function quien() {
    const jwt = (req.headers.get("Authorization") || "").replace(/^Bearer\s+/i, "");
    const { data: { user } } = await admin.auth.getUser(jwt);
    if (!user) return null;
    const { data: p } = await admin.from("perfiles").select("id,nombre,rol,area,areas").eq("id", user.id).single();
    const ok = p && (["pm", "desarrollador"].includes(p.rol) || p.area === "operativo" || (p.areas || []).includes("operativo"));
    return ok ? { ...p, email: user.email || "" } : null;
  }

  // ---------- Correo ----------
  const smtpUser = env("SMTP_USER"), smtpPass = env("SMTP_PASS");
  const smtp = smtpUser && smtpPass ? nodemailer.createTransport({ pool: true, maxConnections: 2,
    host: env("SMTP_HOST", "smtp.hostinger.com"), port: Number(env("SMTP_PORT", "465")), secure: Number(env("SMTP_PORT", "465")) === 465,
    auth: { user: smtpUser, pass: smtpPass } }) : null;
  let logo: Uint8Array | null = null;
  async function enviar(para: string, asunto: string, html: string, token?: string) {
    if (!smtp) throw new Error("Faltan los secretos SMTP_USER y SMTP_PASS.");
    if (!logo) { try { logo = new Uint8Array(await (await fetch(LOGO_URL)).arrayBuffer()); } catch { logo = new Uint8Array(); } }
    const baja = token ? `${APP}/registro/?baja=${token}` : "";
    await smtp.sendMail({ from: `"${REMITENTE}" <${smtpUser}>`, to: para, subject: asunto, html,
      headers: baja ? { "List-Unsubscribe": `<${baja}>` } : undefined,
      attachments: logo && logo.length ? [{ filename: "logo.png", content: logo, cid: LOGO_CID }] : [] });
  }
  // Reserva el envío (clave única); si ya existe, no se manda de nuevo
  async function reservar(fila: Record<string, unknown>) {
    const { data, error } = await admin.from("crm_mensajes").insert({ creado_por: null, ...fila }).select("id").single();
    return error ? null : data.id as string;
  }
  const fallo = (id: string, e: unknown) => admin.from("crm_mensajes").update({ estado: "error", error: String((e as Error).message || e).slice(0, 1000) }).eq("id", id);

  // ---------- WhatsApp ----------
  const waNumero = (t: string) => { const d = String(t || "").replace(/\D/g, ""); if (d.length === 10) return "52" + d; if (d.length === 13 && d.startsWith("521")) return "52" + d.slice(3); return d; };
  async function wa(to: string, payload: Record<string, unknown>) {
    const r = await fetch(`https://graph.facebook.com/v21.0/${WA.phone}/messages`, { method: "POST",
      headers: { Authorization: `Bearer ${WA.token}`, "Content-Type": "application/json" },
      body: JSON.stringify({ messaging_product: "whatsapp", to: waNumero(to), ...payload }) });
    const j = await r.json().catch(() => ({}));
    if (!r.ok) throw new Error(j?.error?.error_data?.details || j?.error?.message || r.statusText);
    return (j.messages?.[0]?.id || "") as string;
  }
  async function recordatorios(evs: Ev[], f: string, soloEv?: string) {
    let enviados = 0; const errores: string[] = [];
    if (!waListo()) return { enviados, errores: ["WhatsApp no está conectado."] };
    for (const ev of evs) {
      if (soloEv && ev.id !== soloEv) continue;
      if (!ocurre(ev.data, f)) continue;
      const { data: as } = await admin.from("crm_asistencias").select("id,persona,estado").eq("evento", ev.id).eq("fecha", f).eq("estado", "registrado");
      if (!as?.length) continue;
      const { data: ps } = await admin.from("crm_personas").select("id,nombre,telefono,acepta_whatsapp").in("id", as.map((a) => a.persona));
      for (const a of as) {
        const p = ps?.find((x) => x.id === a.persona);
        if (!p || !p.acepta_whatsapp || String(p.telefono).replace(/\D/g, "").length < 10) continue;
        const id = await reservar({ persona: p.id, canal: "whatsapp", tipo: "recordatorio", evento: ev.id, fecha_evento: f, clave: `wa2|${a.id}`,
          texto: `¡Hola, ${primerNombre(p.nombre)}! 🤍 Te esperamos en nuestro cenáculo con Tiempo de Dios. ${cuandoMsg(ev.data, f)}. Sembradora: ${ev.data.sembradora || "—"}. 📍 ${ev.data.lugar || "—"}. ¿Nos confirmas si vienes?` });
        if (!id) continue;
        try {
          const wid = await wa(p.telefono, { type: "template", template: { name: WA.plantilla, language: { code: WA.idioma }, components: [
            // Plantilla: ¡Hola, {{1}}! 🤍 / Te esperamos en nuestro cenáculo con Tiempo de Dios / {{2}} / Sembradora: {{3}} / 📍 {{4}} / ¿Nos confirmas si vienes?
            { type: "body", parameters: [primerNombre(p.nombre) || "hola", cuandoMsg(ev.data, f), ev.data.sembradora || "Tiempo de Dios", ev.data.lugar || "por confirmar"].map((t) => ({ type: "text", text: t })) },
            { type: "button", sub_type: "quick_reply", index: "0", parameters: [{ type: "payload", payload: `si|${a.id}` }] },
            { type: "button", sub_type: "quick_reply", index: "1", parameters: [{ type: "payload", payload: `no|${a.id}` }] },
          ] } });
          await admin.from("crm_mensajes").update({ wa_id: wid }).eq("id", id); enviados++;
        } catch (e) { errores.push(`${p.nombre}: ${(e as Error).message}`); await fallo(id, e); }
      }
    }
    return { enviados, errores };
  }

  const accion = body.accion || "diario";
  const { data: evRows } = await admin.from("eventos").select("id,data");
  const evs = ((evRows || []) as Ev[]).filter((e) => e.data && conRegistro(e.data));

  if (accion === "estado") {
    if (!(await quien())) return json({ error: "Sin permiso." }, 403);
    return json({ correo: !!smtp, whatsapp: waListo(), plantilla: WA.plantilla, max: MAX_DIA });
  }

  if (accion === "wa_recordar") {
    if (!(await quien())) return json({ error: "Solo Operativo puede mandar recordatorios." }, 403);
    const r = await recordatorios(evs, String(body.fecha || ""), String(body.evento || ""));
    return json({ ok: true, ...r });
  }

  if (accion === "wa_texto") {
    const yo = await quien(); if (!yo) return json({ error: "Solo Operativo puede escribir por WhatsApp." }, 403);
    if (!waListo()) return json({ error: "WhatsApp no está conectado todavía." }, 400);
    const { data: p } = await admin.from("crm_personas").select("id,telefono").eq("id", body.persona).single();
    const texto = String(body.texto || "").trim().slice(0, 4000);
    if (!p || !texto) return json({ error: "Falta la persona o el mensaje." }, 400);
    try {
      const wid = await wa(p.telefono, { type: "text", text: { body: texto } });
      await admin.from("crm_mensajes").insert({ persona: p.id, canal: "whatsapp", tipo: "texto", texto, wa_id: wid, creado_por: yo.id });
      return json({ ok: true });
    } catch (e) {
      const m = (e as Error).message;
      return json({ error: /24|re-engage|window/i.test(m) ? "Pasaron más de 24 horas desde su último mensaje: WhatsApp solo deja mandar plantillas aprobadas. Escríbele desde el celular." : m }, 400);
    }
  }

  if (accion === "prueba") {
    const yo = await quien(); if (!yo) return json({ error: "Sin permiso." }, 403);
    const hoy = hoyMx();
    const ev = evs.find((e) => [...Array(60)].some((_, i) => ocurre(e.data, sumar(hoy, i)))) || { id: "ejemplo", data: { titulo: "Cenáculo", tipo: "cenaculo", hora: "19:00", lugar: "" } };
    const f = [...Array(60)].map((_, i) => sumar(hoy, i)).find((k) => ocurre(ev.data, k)) || sumar(hoy, 7);
    const ej = { nombre: yo.nombre, token: "00000000-0000-0000-0000-000000000000" };
    try {
      const a = invitacion(ej, ev, f, 15), b = invitacion(ej, ev, f, 7);
      await enviar(yo.email, "[Prueba · 15 días antes] " + a.asunto, a.html);
      await enviar(yo.email, "[Prueba · 7 días antes] " + b.asunto, b.html);
      return json({ ok: true, para: yo.email });
    } catch (e) { return json({ error: (e as Error).message }, 500); }
  }

  if (accion === "boletin") {
    const yo = await quien(); if (!yo) return json({ error: "Solo Operativo puede mandar newsletters." }, 403);
    const { data: b } = await admin.from("crm_boletines").select("*").eq("id", body.id).single();
    if (!b) return json({ error: "No encontré ese newsletter." }, 404);
    const armar = (p: any) => plantilla({ tipo: "Newsletter", titulo: b.titulo || b.asunto, previa: String(b.cuerpo || "").slice(0, 140), imagen: b.imagen,
      cuerpo: textoAHtml(b.cuerpo, primerNombre(p.nombre)), boton: b.boton_texto, liga: b.boton_liga, token: p.token });
    if (body.prueba) {
      try { await enviar(yo.email, "[Prueba] " + b.asunto, armar({ nombre: yo.nombre, token: "" })); return json({ ok: true, prueba: true, para: yo.email }); }
      catch (e) { return json({ error: (e as Error).message }, 500); }
    }
    const { data: ps } = await admin.from("crm_personas").select("id,nombre,correo,token").eq("acepta_correos", true).neq("correo", "").limit(20000);
    const { data: ya } = await admin.from("crm_mensajes").select("persona").like("clave", `bol|${b.id}|%`).limit(20000);
    const hechos = new Set((ya || []).map((x) => x.persona));
    const faltan = (ps || []).filter((p) => !hechos.has(p.id));
    let enviados = 0; const errores: string[] = [];
    for (const p of faltan.slice(0, 40)) {
      const id = await reservar({ persona: p.id, canal: "correo", tipo: "boletin", texto: b.asunto, evento: b.id, clave: `bol|${b.id}|${p.id}` });
      if (!id) continue;
      try { await enviar(p.correo, b.asunto, armar(p), p.token); enviados++; }
      catch (e) { errores.push(`${p.correo}: ${(e as Error).message}`); await fallo(id, e); }
    }
    const resta = Math.max(0, faltan.length - 40);
    await admin.from("crm_boletines").update({ estado: resta ? "enviando" : "enviado", enviados: hechos.size + enviados, total: (ps || []).length,
      ...(resta ? {} : { enviado_en: new Date().toISOString() }) }).eq("id", b.id);
    return json({ ok: true, enviados, faltan: resta, errores });
  }

  if (accion !== "diario") return json({ error: "Acción desconocida." }, 400);

  // ================= Corrida diaria =================
  const hoy = hoyMx(), res: Record<string, unknown> = { hoy };
  const errores: string[] = [];
  const { data: personas } = await admin.from("crm_personas").select("id,nombre,correo,telefono,token,acepta_correos,nacimiento,responsable,estado,proxima_fecha,proxima_accion").limit(20000);
  const P = personas || [];

  // 1) Invitaciones por correo 15 y 7 días antes
  let invitados = 0;
  if (smtp) {
    const desde = new Date(Date.now() - 6 * 864e5).toISOString();
    const { data: recientes } = await admin.from("crm_mensajes").select("persona").in("tipo", ["invitacion15", "invitacion7"]).gte("creado", desde).limit(20000);
    const reciente = new Set((recientes || []).map((x) => x.persona));
    for (const dias of [7, 15]) {
      const f = sumar(hoy, dias);
      for (const ev of evs.filter((e) => e.data.invitar && ocurre(e.data, f))) {
        const { data: regs } = await admin.from("crm_asistencias").select("persona").eq("evento", ev.id).eq("fecha", f);
        const ya = new Set((regs || []).map((r) => r.persona));
        for (const p of P) {
          if (invitados >= MAX_DIA) break;
          if (!p.acepta_correos || !p.correo || ya.has(p.id) || reciente.has(p.id)) continue;
          const id = await reservar({ persona: p.id, canal: "correo", tipo: `invitacion${dias}`, texto: `Invitación: ${ev.data.titulo} (${larga(f)})`, evento: ev.id, fecha_evento: f, clave: `inv${dias}|${ev.id}|${f}|${p.id}` });
          if (!id) continue;
          reciente.add(p.id);
          const c = invitacion(p, ev, f, dias);
          try { await enviar(p.correo, c.asunto, c.html, p.token); invitados++; }
          catch (e) { errores.push(`${p.correo}: ${(e as Error).message}`); await fallo(id, e); }
        }
      }
    }
  }
  res.invitaciones = invitados;

  // 2) WhatsApp 2 días antes a quien se registró
  const r2 = waListo() ? await recordatorios(evs, sumar(hoy, 2)) : { enviados: 0, errores: [] as string[] };
  res.recordatorios = r2.enviados; errores.push(...r2.errores);

  // 3) Resumen para Operativo (una vez al día por persona; tabla avisos_enviados de la migración 008)
  if (smtp) {
    const [{ data: perfiles }, { data: usuarios }] = await Promise.all([
      admin.from("perfiles").select("id,nombre,rol,area,areas,finanzas"), admin.auth.admin.listUsers({ perPage: 1000 })]);
    const correos = new Map((usuarios?.users || []).map((u) => [u.id, u.email || ""]));
    const md = hoy.slice(5);
    const cumple = P.filter((p) => p.nacimiento && String(p.nacimiento).slice(5) === md);
    const abiertos = (p: any) => !["no_interesado"].includes(p.estado);
    const equipo = (perfiles || []).filter((x) => x.area === "operativo" || (x.areas || []).includes("operativo"));
    const fila = (p: any, extra: string) => `<tr><td style="padding:9px 0;border-bottom:1px solid #EEF2F2"><b>${esc(p.nombre)}</b><div style="font-size:13px;color:#5E6766">${extra}</div></td></tr>`;
    for (const yo of equipo) {
      const email = correos.get(yo.id); if (!email) continue;
      const mios = P.filter((p) => p.responsable === yo.id && p.proxima_fecha && p.proxima_fecha <= hoy && abiertos(p));
      const sinResp = yo.rol === "lider" ? P.filter((p) => !p.responsable && p.proxima_fecha && p.proxima_fecha <= hoy && abiertos(p)) : [];
      if (!mios.length && !sinResp.length && !cumple.length) continue;
      const { error } = await admin.from("avisos_enviados").insert({ dia: hoy, destino: email, tipo: "crm" });
      if (error) continue;
      const tabla = (l: any[]) => `<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="border-collapse:collapse;margin:4px 0 14px">${l.join("")}</table>`;
      const cuerpo = `<p style="margin:0 0 12px">Hola, ${esc(primerNombre(yo.nombre))}:</p>` +
        (mios.length ? `<p style="margin:0"><b>Tus seguimientos para hoy</b> (${mios.length}):</p>${tabla(mios.map((p) => fila(p, `${p.proxima_fecha < hoy ? '<span style="color:#FF3D1A;font-weight:bold">Vencido</span> · ' : ""}${esc(p.proxima_accion || "Dar seguimiento")}`)))}` : "") +
        (sinResp.length ? `<p style="margin:0"><b>Sin responsable</b> (${sinResp.length}):</p>${tabla(sinResp.map((p) => fila(p, esc(p.proxima_accion || "Asignar a alguien"))))}` : "") +
        (cumple.length ? `<p style="margin:0">🎂 <b>Cumplen años hoy</b>:</p>${tabla(cumple.map((p) => fila(p, esc(p.telefono || p.correo || ""))))}` : "");
      try {
        await enviar(email, mios.length ? `Tienes ${mios.length} seguimiento${mios.length > 1 ? "s" : ""} para hoy` : cumple.length ? `🎂 Hoy cumple${cumple.length > 1 ? "n" : ""} años ${cumple.map((p) => primerNombre(p.nombre)).join(", ")}` : "Personas sin responsable",
          plantilla({ tipo: "Operativo", titulo: "Personas: lo de hoy", cuerpo, boton: "Abrir Personas", liga: `${APP}/#operativo` }));
      } catch (e) { errores.push(`${email}: ${(e as Error).message}`); await admin.from("avisos_enviados").delete().match({ dia: hoy, destino: email, tipo: "crm" }); }
    }
    // 4) Lunes: donaciones comprometidas que no han llegado → Finanzas
    if (deKey(hoy).getUTCDay() === 1) {
      const { data: dons } = await admin.from("crm_donaciones").select("persona,monto,fecha,destino").eq("estado", "comprometida").lt("fecha", hoy);
      if (dons?.length) {
        const fin = (perfiles || []).filter((x) => x.finanzas || x.rol === "desarrollador");
        const MXN = new Intl.NumberFormat("es-MX", { style: "currency", currency: "MXN" });
        for (const f of fin) {
          const email = correos.get(f.id); if (!email) continue;
          const { error } = await admin.from("avisos_enviados").insert({ dia: hoy, destino: email, tipo: "crm-don" }); if (error) continue;
          const cuerpo = `<p style="margin:0 0 12px">Estas donaciones comprometidas ya pasaron su fecha y no se han marcado como recibidas:</p><table role="presentation" width="100%" cellpadding="0" cellspacing="0">${dons.map((d) => {
            const p = P.find((x) => x.id === d.persona); return fila({ nombre: p?.nombre || "—" }, `${MXN.format(Number(d.monto))} · ${esc(d.destino || "sin destino")} · desde el ${larga(d.fecha)}`); }).join("")}</table>`;
          try { await enviar(email, `${dons.length} donación${dons.length > 1 ? "es" : ""} comprometida${dons.length > 1 ? "s" : ""} sin recibir`, plantilla({ tipo: "Finanzas", titulo: "Donaciones por recibir", cuerpo, boton: "Abrir Personas", liga: `${APP}/#operativo` })); }
          catch (e) { errores.push(`${email}: ${(e as Error).message}`); }
        }
      }
    }
  }
  return json({ ok: true, ...res, errores });
});
