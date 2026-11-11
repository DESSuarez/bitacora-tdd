// Edge Function "avisos": correos automáticos de la bitácora.
// La llama pg_cron cada día a las 8:00 (hora del centro de México); ver migración 008.
//   · A cada responsable: lo que vence mañana y lo que ya está atrasado (un correo al día hasta que lo complete).
//   · Los sábados, a la Project Manager: lo que no se completó en la semana y lo atrasado.
// Cada envío se registra en "avisos_enviados" (día, destino, tipo): si la función corre dos veces el mismo día, no repite.
// {prueba:true} con la sesión de una PM o desarrollador: manda a su propio correo un ejemplo de cada tipo, sin registrar nada.
//
// Secretos (Supabase → Edge Functions → Secrets): SMTP_USER y SMTP_PASS (buzón bitacora@tiempodedios.mx).
// Opcionales: SMTP_HOST (smtp.hostinger.com), SMTP_PORT (465), APP_URL (https://pm.tiempodedios.mx).
import { createClient } from "npm:@supabase/supabase-js@2.45.4";
import nodemailer from "npm:nodemailer@6.9.14";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const TZ = "America/Mexico_City";
const APP = (Deno.env.get("APP_URL") || "https://pm.tiempodedios.mx").replace(/\/+$/, "");
const AREAS: Record<string, string> = { formacion: "Formación", musica: "Música", audiovisual: "Audiovisual", operativo: "Operativo" };
const DIAS = ["domingo", "lunes", "martes", "miércoles", "jueves", "viernes", "sábado"];
const MESES = ["ene", "feb", "mar", "abr", "may", "jun", "jul", "ago", "sep", "oct", "nov", "dic"];
const ACCESO_TOTAL = ["pm", "desarrollador"];

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });
}
const esc = (s: unknown) => String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]!));

// Fechas como "YYYY-MM-DD" en la zona de México
const hoyMx = () => new Intl.DateTimeFormat("en-CA", { timeZone: TZ }).format(new Date());
const deKey = (k: string) => new Date(k + "T12:00:00Z");
const aKey = (d: Date) => d.toISOString().slice(0, 10);
const sumar = (k: string, n: number) => { const d = deKey(k); d.setUTCDate(d.getUTCDate() + n); return aKey(d); };
const diaSemana = (k: string) => deKey(k).getUTCDay();
const lunesDe = (k: string) => sumar(k, -((diaSemana(k) + 6) % 7));
const corta = (k: string) => { const d = deKey(k); return `${DIAS[d.getUTCDay()]} ${d.getUTCDate()} ${MESES[d.getUTCMonth()]}`; };
const diasEntre = (a: string, b: string) => Math.round((deKey(b).getTime() - deKey(a).getTime()) / 864e5);

type Perfil = { id: string; nombre: string; rol: string; area: string | null };
type Item = { titulo: string; padre?: string; area: string; vence: string; persona?: Perfil; responsable: string };

// Mismo diseño que las plantillas de supabase/correos
function correo(titulo: string, cuerpo: string, boton: string, liga: string) {
  return `<!doctype html><html lang="es"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>${esc(titulo)}</title></head>
<body style="margin:0;padding:0;background:#F4F7F7;font-family:Arial,Helvetica,sans-serif;color:#1B1C1A">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#F4F7F7;padding:32px 12px"><tr><td align="center">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:560px;background:#FFFFFF;border-radius:16px;overflow:hidden;border:1px solid #DDE5E5">
<tr><td style="background:#1B1C1A;padding:26px 32px 22px;border-bottom:6px solid #FF3D1A">
<img src="${APP}/apple-touch-icon.png" width="40" height="40" alt="Tiempo de Dios" style="display:block;border-radius:10px;margin-bottom:12px">
<div style="font-size:11px;letter-spacing:2px;text-transform:uppercase;color:#A3ADAC;font-weight:bold">Tiempo de Dios · Bitácora</div>
<div style="font-size:22px;line-height:1.25;font-weight:900;color:#FFFFFF;margin-top:6px">${esc(titulo)}</div></td></tr>
<tr><td style="padding:24px 32px 8px;font-size:15px;line-height:1.55">${cuerpo}
<table role="presentation" cellpadding="0" cellspacing="0" style="margin:22px 0 26px"><tr><td style="background:#FF3D1A;border-radius:10px">
<a href="${liga}" style="display:inline-block;padding:13px 24px;color:#FFFFFF;font-weight:bold;font-size:15px;text-decoration:none">${esc(boton)}</a></td></tr></table></td></tr>
<tr><td style="padding:14px 32px 22px;border-top:1px solid #DDE5E5;font-size:12px;color:#5E6766">Aviso automático de la bitácora · <a href="${APP}" style="color:#5E6766">pm.tiempodedios.mx</a></td></tr>
</table></td></tr></table></body></html>`;
}
function lista(items: Item[], hoy: string, conPersona = false) {
  return `<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="border-collapse:collapse;margin:6px 0 4px">${items.map((i) => {
    const atraso = diasEntre(i.vence, hoy);
    const cuando = atraso > 0 ? `<span style="color:#FF3D1A;font-weight:bold">Atrasada ${atraso} día${atraso > 1 ? "s" : ""}</span> · venció el ${corta(i.vence)}` : `Vence el ${corta(i.vence)}`;
    return `<tr><td style="padding:10px 0;border-bottom:1px solid #EEF2F2"><div style="font-weight:bold">${esc(i.titulo)}</div>
<div style="font-size:13px;color:#5E6766">${i.padre ? `Subtarea de ${esc(i.padre)} · ` : ""}${AREAS[i.area] || ""}${conPersona ? ` · ${esc(i.responsable || "Sin responsable")}` : ""} · ${cuando}</div></td></tr>`;
  }).join("")}</table>`;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "Método no permitido." }, 405);
  const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const body = await req.json().catch(() => ({}));

  // Modo prueba: solo PM o desarrollador, y todo va a su propio correo
  let prueba: { email: string } | null = null;
  if (body.prueba) {
    const jwt = (req.headers.get("Authorization") || "").replace(/^Bearer\s+/i, "");
    const { data: { user } } = await admin.auth.getUser(jwt);
    if (!user?.email) return json({ error: "Tu sesión expiró. Vuelve a entrar." }, 401);
    const { data: yo } = await admin.from("perfiles").select("rol").eq("id", user.id).single();
    if (!ACCESO_TOTAL.includes(yo?.rol)) return json({ error: "Solo la project manager puede mandar pruebas." }, 403);
    prueba = { email: user.email };
  }

  const smtpUser = Deno.env.get("SMTP_USER"), smtpPass = Deno.env.get("SMTP_PASS");
  if (!smtpUser || !smtpPass) return json({ error: "Faltan los secretos SMTP_USER y SMTP_PASS de la función avisos." }, 500);
  const smtp = nodemailer.createTransport({
    host: Deno.env.get("SMTP_HOST") || "smtp.hostinger.com",
    port: Number(Deno.env.get("SMTP_PORT") || 465),
    secure: Number(Deno.env.get("SMTP_PORT") || 465) === 465,
    auth: { user: smtpUser, pass: smtpPass },
  });
  const de = `"Bitácora Tiempo de Dios" <${smtpUser}>`;

  // Datos
  const [{ data: perfiles, error: e1 }, { data: filas, error: e2 }, { data: usuarios, error: e3 }] = await Promise.all([
    admin.from("perfiles").select("id,nombre,rol,area"),
    admin.from("tareas").select("id,area,data").limit(10000),
    admin.auth.admin.listUsers({ perPage: 1000 }),
  ]);
  if (e1 || e2 || e3) return json({ error: (e1 || e2 || e3)!.message }, 500);
  const correos = new Map(usuarios.users.map((u) => [u.id, u.email || ""]));
  const ps = (perfiles || []) as Perfil[];
  const personaDe = (id?: string | null, nombre?: string) =>
    (id && ps.find((p) => p.id === id)) || (nombre ? ps.find((p) => (p.nombre || "").trim().toLowerCase() === nombre.trim().toLowerCase()) : undefined);

  const hoy = hoyMx(), manana = sumar(hoy, 1);
  const pendientes: Item[] = [];
  for (const f of filas || []) {
    const t = f.data || {};
    if (!t.semana) continue;
    const area = AREAS[f.area] ? f.area : t.area;
    const vence = t.vence || sumar(t.semana, 4);
    if (!t.hecha) pendientes.push({ titulo: t.titulo, area, vence, persona: personaDe(t.responsable_id, t.responsable), responsable: t.responsable || "" });
    for (const s of t.subtareas || []) {
      if (s.hecha) continue;
      // Si la subtarea es de otra persona, también se le avisa; si es del mismo responsable, basta el aviso de la tarea
      const p = s.responsable_id || s.responsable ? personaDe(s.responsable_id, s.responsable) : undefined;
      if (!p || (!t.hecha && p.id === personaDe(t.responsable_id, t.responsable)?.id)) continue;
      pendientes.push({ titulo: s.titulo, padre: t.titulo, area, vence: s.vence || vence, persona: p, responsable: s.responsable || "" });
    }
  }

  // ¿Ya se mandó hoy? (en prueba no se registra)
  async function reservar(destino: string, tipo: string) {
    if (prueba) return true;
    const { error } = await admin.from("avisos_enviados").insert({ dia: hoy, destino, tipo });
    return !error; // choque con la llave primaria = ya se envió hoy
  }
  // Si el envío falla, se borra el registro para que el siguiente intento del día sí lo mande
  async function liberar(destino: string, tipo: string) {
    if (!prueba) await admin.from("avisos_enviados").delete().match({ dia: hoy, destino, tipo });
  }
  async function enviar(para: string, asunto: string, html: string) {
    await smtp.sendMail({ from: de, to: prueba ? prueba.email : para, subject: (prueba ? `[Prueba para ${para}] ` : "") + asunto, html });
  }

  let enviados = 0, personas = 0;
  const errores: string[] = [];

  // 1) A cada responsable: vence mañana + atrasadas
  const porPersona = new Map<string, Item[]>();
  for (const i of pendientes) {
    if (!i.persona || (i.vence !== manana && i.vence >= hoy)) continue;
    const l = porPersona.get(i.persona.id) || [];
    l.push(i);
    porPersona.set(i.persona.id, l);
  }
  let muestras = 0;
  for (const [pid, items] of porPersona) {
    const email = correos.get(pid);
    if (!email) continue;
    personas++;
    if (prueba && muestras >= 2) continue;
    if (!(await reservar(email, "personal"))) continue;
    const p = ps.find((x) => x.id === pid)!;
    const atr = items.filter((i) => i.vence < hoy).sort((a, b) => a.vence.localeCompare(b.vence)), man = items.filter((i) => i.vence === manana);
    const nombre = (p.nombre || "").split(" ")[0];
    const asunto = atr.length
      ? `Tienes ${atr.length} actividad${atr.length > 1 ? "es" : ""} atrasada${atr.length > 1 ? "s" : ""}${man.length ? ` y ${man.length} vence${man.length > 1 ? "n" : ""} mañana` : ""}`
      : man.length === 1 ? `Mañana vence: ${man[0].titulo}` : `Mañana vencen ${man.length} actividades`;
    const cuerpo = `<p style="margin:0 0 12px">Hola, ${esc(nombre)}:</p>` +
      (atr.length ? `<p style="margin:0">Estas actividades ya pasaron su fecha. Cuando puedas, complétalas o habla con la Project Manager para moverlas de semana:</p>${lista(atr, hoy)}` : "") +
      (man.length ? `<p style="margin:${atr.length ? "18px" : "0"} 0 0">${man.length > 1 ? "Estas actividades vencen" : "Esta actividad vence"} <b>mañana, ${corta(manana)}</b>:</p>${lista(man, hoy)}` : "") +
      `<p style="margin:14px 0 0;font-size:13px;color:#5E6766">Al marcarlas en la bitácora dejarás de recibir este aviso.</p>`;
    try { await enviar(email, asunto, correo(atr.length ? "Tienes actividades pendientes" : "Mañana vence una actividad", cuerpo, "Ver mis pendientes", `${APP}/#persona/${pid}`)); enviados++; muestras++; }
    catch (e) { errores.push(`${email}: ${(e as Error).message}`); await liberar(email, "personal"); }
  }

  // 2) Sábado: resumen para la Project Manager
  if (diaSemana(hoy) === 6 || prueba) {
    const lunes = lunesDe(hoy), viernes = sumar(lunes, 4);
    const abiertas = pendientes.filter((i) => i.vence <= viernes).sort((a, b) => (a.area || "").localeCompare(b.area || "") || a.vence.localeCompare(b.vence));
    const pms = ps.filter((p) => p.rol === "pm");
    const destinos = prueba ? [{ id: "", nombre: "Project Manager", rol: "pm", area: null } as Perfil] : pms;
    for (const pm of destinos) {
      const email = prueba ? prueba.email : correos.get(pm.id);
      if (!email || !(await reservar(email, "semanal"))) continue;
      const porArea = Object.keys(AREAS).map((a) => [a, abiertas.filter((i) => i.area === a)] as const).filter(([, l]) => l.length);
      const cuerpo = `<p style="margin:0 0 12px">Hola${pm.nombre && !prueba ? ", " + esc(pm.nombre.split(" ")[0]) : ""}:</p>` +
        (abiertas.length
          ? `<p style="margin:0">Esto quedó sin completar al cierre de la semana del ${corta(lunes)} al ${corta(viernes)}: <b>${abiertas.length} actividad${abiertas.length > 1 ? "es" : ""}</b>.</p>` +
            porArea.map(([a, l]) => `<h3 style="margin:22px 0 2px;font-size:15px">${AREAS[a]} · ${l.length}</h3>${lista(l as Item[], hoy, true)}`).join("")
          : `<p style="margin:0">Todas las actividades de la semana del ${corta(lunes)} al ${corta(viernes)} quedaron completas. 🎉</p>`);
      try { await enviar(email, abiertas.length ? `Semana del ${corta(lunes)}: ${abiertas.length} actividades sin completar` : `Semana del ${corta(lunes)}: todo completado`, correo("Resumen de la semana", cuerpo, "Abrir el panel de la PM", `${APP}/#pm`)); enviados++; }
      catch (e) { errores.push(`${email}: ${(e as Error).message}`); await liberar(email, "semanal"); }
    }
  }

  if (errores.length && !enviados) return json({ error: "No se pudo enviar: " + errores[0], errores }, 500);
  return json({ ok: true, hoy, enviados, personas, errores });
});
