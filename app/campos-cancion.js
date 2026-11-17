// Preguntas del formulario privado "Registra tu canción" (una liga por artista).
// Lo usan cancion/index.html (para pedir los datos) e index.html (Música → Canciones).
// Para agregar o cambiar una pregunta, edítala solo aquí.
// si: { k, v } muestra la pregunta solo cuando el campo k (multi o chips) incluye la opción v.
// tipo: text | email | tel | area (texto largo) | chips (opción única) | multi (varias opciones) | files (archivos)
//       personas (lista que crece: nombre + % opcional; se guarda como texto en k y como lista en k+"Lista")
//       lista (renglones que crecen con los subcampos de «sub»; texto en k y lista en k+"Lista")
//       ministerio (selector con los ministerios del colectivo y «Otro…»)
window.CAMPOS_CANCION = [
  { id: "artista", titulo: "Sobre ti", intro: "Para saber quién comparte la canción y cómo contactarte.", campos: [
    { k: "nombre", l: "Nombre completo", req: true },
    { k: "nombreArtistico", l: "Artista o ministerio", tipo: "ministerio", ayuda: "Elige tu ministerio del colectivo. Si no aparece, elige «Otro…» y escribe cómo quieres que aparezca en la canción." },
    { k: "correo", l: "Correo", tipo: "email", req: true },
    { k: "telefono", l: "Teléfono o WhatsApp", tipo: "tel", req: true },
    { k: "ciudad", l: "Ciudad" },
    { k: "redes", l: "Redes o plataformas", ayuda: "Instagram, Spotify, YouTube… (ligas o usuarios)." }
  ]},
  { id: "cancion", titulo: "La canción", intro: "Lo esencial de la canción que quieres producir.", campos: [
    { k: "titulo", l: "Título de la canción", req: true },
    { k: "tipo", l: "¿Qué es?", tipo: "chips", ops: ["Canción original", "Cover o versión", "Adaptación o traducción"], req: true },
    { k: "original", l: "¿De qué canción es la versión y quién es el autor?", req: true, si: { k: "tipo", v: "Cover o versión" } },
    { k: "compositores", l: "Compositores", tipo: "personas", req: true, ayuda: "Nombre completo de cada persona que escribió letra o música y, si lo sabes, su porcentaje. Usa «+ Agregar otro compositor» para sumar a alguien más." },
    { k: "idioma", l: "Idioma", tipo: "chips", ops: ["Español", "Inglés", "Bilingüe", "Otro"] },
    { k: "letra", l: "Letra completa", tipo: "area", req: true, ayuda: "Marca las partes si puedes: [Verso 1], [Coro], [Puente]…" },
    { k: "mensaje", l: "¿De qué habla la canción y por qué es importante para ti?", tipo: "area" }
  ]},
  { id: "musical", titulo: "Datos musicales", intro: "Si no sabes algún dato, escribe uno aproximado o déjalo en blanco.", campos: [
    { k: "bpm", l: "BPM (tempo)", req: true, ayuda: "Ej. 72. Si no lo sabes, escribe «lenta», «media» o «rápida»." },
    { k: "tonalidad", l: "Tonalidad", ayuda: "Ej. Re mayor, La menor." },
    { k: "compas", l: "Compás", tipo: "chips", ops: ["4/4", "3/4", "6/8", "No sé"] },
    { k: "genero", l: "Género o estilo", ayuda: "Ej. pop, worship, balada, urbano, folk." },
    { k: "duracion", l: "Duración aproximada", ayuda: "Ej. 4:30" },
    { k: "estructura", l: "Estructura", tipo: "area", ayuda: "Ej. Intro, Verso 1, Coro, Verso 2, Coro, Puente, Coro x2, Final." }
  ]},
  { id: "referencias", titulo: "Referencias y arreglo", intro: "Cómo te imaginas que suene.", campos: [
    { k: "referencias", l: "Canciones de referencia", tipo: "lista", req: true, add: "+ Agregar otra referencia",
      ayuda: "Pega la liga de cada canción (YouTube o Spotify) y dinos qué te gusta de ella.",
      sub: [{ k: "liga", l: "Liga", ph: "https://open.spotify.com/… o https://youtube.com/…" }, { k: "gusta", l: "¿Qué te gusta?", ph: "El sonido, la voz, el ritmo, la batería…" }] },
    { k: "instrumentos", l: "Instrumentos que imaginas", tipo: "multi", ops: ["Piano o teclado", "Guitarra acústica", "Guitarra eléctrica", "Bajo", "Batería", "Percusiones", "Cuerdas", "Sintetizadores", "Vientos", "Otro"] },
    { k: "voces", l: "Voces", tipo: "chips", ops: ["Solista", "Dueto", "Coros o grupo", "Por definir"] },
    { k: "arreglo", l: "Ideas de arreglo o producción", tipo: "area", ayuda: "Momentos clave, dinámicas, cómo empieza o termina, algo que no debe faltar." }
  ]},
  { id: "archivos", titulo: "Demo y archivos", intro: "Todo lo que nos ayude a escucharla: demo, nota de voz, letra, partitura o cifrado.", campos: [
    { k: "archivos", l: "Sube tus archivos", tipo: "files" },
    { k: "ligaDemo", l: "Liga a tu demo (opcional)", ayuda: "Si tu archivo pesa más de 50 MB, súbelo a Drive o Dropbox y pega la liga aquí." }
  ]},
  { id: "fechas", titulo: "Fechas", intro: "Para planear la semana de producción con el ministerio.", campos: [
    { k: "tipoProduccion", l: "¿Qué tipo de producción buscas?", tipo: "chips", req: true, ops: ["Acústica o live (2 días)", "Full band (1 semana)", "Producción grande (2 semanas)", "No lo sé todavía"],
      ayuda: "Al enviar tu canción te llevamos a la agenda para que elijas tus fechas de producción. Si no sabes, el equipo de Música lo ve contigo." },
    { k: "disponibilidad", l: "¿Algo que debamos saber de tus fechas?", tipo: "area", ayuda: "Opcional: semanas que no puedes, viajes, fechas importantes…" },
    { k: "lanzamiento", l: "¿Tienes una fecha ideal de lanzamiento?", ayuda: "Ej. marzo 2027, o «sin prisa»." },
    { k: "comentarios", l: "¿Algo más que debamos saber?", tipo: "area" }
  ]}
];

// Etapas del flujo de producción (en orden). "bloqueado" es la salida desde cualquier etapa.
window.ETAPAS_CANCION = [
  ["intake", "Intake", "El artista registra la canción y Memo la aprueba."],
  ["preproduccion", "Pre-producción", "Asesorías, aprobación de la composición y contrato."],
  ["agendada", "Agendada", "Semana confirmada con Memo, Diego y el artista."],
  ["produccion", "En producción", "Semana completa: master WAV, versión sin voz y stems."],
  ["registro", "Registro pendiente", "INDAUTOR/SACM, créditos y splitsheet firmado."],
  ["marketing", "Listo para Marketing", "Se entrega al board de Marketing."],
  ["completado", "Completado", "Canción lanzada y reportada."],
  ["bloqueado", "Bloqueado", "Algo detiene el proceso; anota el motivo en las notas."]
];

// Checklist definitivo: 15 pasos de producción (con las dos escuchas del master en Samply) + 8 de marketing (pipeline D-Day).
// La migración 018 reacomodó los números de las canciones que ya existían (antes eran 22 pasos) y la 021 agregó
// «Subir canción a plataformas (DistroKid)» después del splitsheet (24 pasos).
// [paso, fase, responsable, días respecto al lanzamiento (solo marketing), documento obligatorio para completarlo]
// El avance de cada canción (0 a 100 %) es cuántos de estos pasos están completos.
// Ojo: el orden importa (el avance guardado usa el número de paso); agrega pasos nuevos al final.
window.CHECKLIST_CANCION = [
  ["Primera sesión de asesoría", "Pre-producción", "Ariel"],
  ["Aprobación de la composición", "Pre-producción", "Ariel"],
  ["Contrato generado", "Pre-producción", "Memo"],
  ["Contrato firmado", "Pre-producción", "Memo"],
  ["Semana de producción agendada", "Agendada", "Memo"],
  ["Lunes · Maqueteo", "Producción", "Memo"],
  ["Martes · Instrumentación", "Producción", "Memo"],
  ["Miércoles · Creación de contenido", "Producción", "Memo"],
  ["Jueves · Cierre de instrumentación y voces", "Producción", "Memo"],
  ["Viernes · Edición, mezcla y master", "Producción", "Memo"],
  ["Primera escucha del master (Samply)", "Escuchas", "Memo"],
  ["Segunda escucha y aprobación del master por el artista", "Escuchas", "Memo"],
  ["Registro INDAUTOR / SACM", "Registro", "Ariel", null, "el comprobante del registro INDAUTOR / SACM"],
  ["Splitsheet firmado", "Registro", "Memo", null, "el splitsheet firmado"],
  ["Subir canción a plataformas (DistroKid)", "Registro", "Memo"],
  ["Handoff a Marketing", "Marketing", "Memo"],
  ["D-42 · Brief creativo", "Marketing", "Marketing", -42],
  ["D-35 · Briefing de artwork", "Marketing", "Marketing", -35],
  ["D-28 · DistroKid y pre-save", "Marketing", "Marketing", -28],
  ["D-14 · Copies", "Marketing", "Marketing", -14],
  ["D-7 · Artwork final", "Marketing", "Marketing", -7],
  ["D0 · Lanzamiento en Spotify y plataformas", "Lanzamiento", "Marketing", 0],
  ["D+7 · Carrusel y reels", "Lanzamiento", "Marketing", 7],
  ["D+30 · Reporte", "Lanzamiento", "Marketing", 30]
];

// Al completar estos pasos, la canción avanza sola a la etapa indicada (nunca retrocede ni sale de "Bloqueado")
window.ETAPA_POR_PASO = { 1: "preproduccion", 5: "agendada", 6: "produccion", 12: "registro", 16: "marketing", 24: "completado" };

// ---------- Canciones Live (grabación en vivo de un día, audio y video) ----------
// Cada canción es «estudio» (CHECKLIST_CANCION, arriba) o «live» (este checklist). Se elige al agregarla (data.formato).
// [paso, fase, responsable, días respecto al lanzamiento, documento obligatorio, liga obligatoria]
window.CHECKLIST_LIVE = [
  ["Solicitud: artista, canción o canciones y aprobación", "Solicitud", "Ariel / Memo"],
  ["Preparación: arreglo acústico definido, músicos confirmados y ensayo hecho", "Preparación", "Memo"],
  ["Fecha de grabación confirmada con el artista y con Audiovisual", "Agendada", "Memo"],
  ["Grabación: sesión en un solo día, en audio y video", "Grabación", "Memo / Audiovisual"],
  ["Post: mezcla de audio y edición de video (hasta 2 ajustes)", "Post", "Memo / Audiovisual"],
  ["Listo para publicar: entrega a Marketing con liga a Drive", "Listo para publicar", "Memo", null, "", "la liga de Drive con el material final"]
];
// Al completar estos pasos, la canción live avanza sola a la etapa indicada
window.ETAPA_POR_PASO_LIVE = { 1: "preproduccion", 3: "agendada", 4: "registro", 5: "marketing", 6: "completado" };
// En las canciones live, las mismas etapas se llaman así
window.ETAPAS_LIVE = {
  intake: ["Solicitud", "Artista, canción o canciones y aprobación."],
  preproduccion: ["Preparación", "Arreglo acústico, músicos confirmados y ensayo."],
  agendada: ["Agendada", "Fecha de grabación confirmada con el artista y con Audiovisual."],
  produccion: ["Grabación", "Sesión grabada en un solo día, en audio y video."],
  registro: ["Post", "Mezcla de audio y edición de video, con hasta 2 ajustes."],
  marketing: ["Listo para publicar", "Entrega a Marketing con liga a Drive."],
  completado: ["Publicado", "La canción live ya se publicó."],
  bloqueado: ["Bloqueado", "Algo detiene el proceso; anota el motivo en las notas."]
};

// Semana de producción: lo que se hace cada día (lunes a viernes)
window.DIAS_PRODUCCION = ["Maqueteo", "Instrumentación", "Creación de contenido", "Cierre de instrumentación y voces", "Edición, mezcla y master"];

// ---------- Áreas de cada paso (estudio) ----------
// El checklist es uno solo, pero se trabaja en tres áreas: Música (producción), Legal y Marketing.
// Legal (INDAUTOR/SACM y splitsheet) corre aparte y se abre cuando se aprueba la composición (paso 2).
// Marketing (handoff y pipeline D-Day) se abre cuando todos los pasos de Música están completos (100 %).
// Los pasos que no aparecen aquí son de Música.
window.AREA_PASO = { 13: "legal", 14: "legal", 16: "marketing", 17: "marketing", 18: "marketing", 19: "marketing", 20: "marketing", 21: "marketing", 22: "marketing", 23: "marketing", 24: "marketing" };
// Canciones live: Grabación (4) y Post (5) crean además un pendiente en Audiovisual (es el mismo paso: al completarlo cualquiera, se cierran los dos).
window.AV_PASO_LIVE = [4, 5];

// Respuesta del formulario («¿Qué tipo de producción buscas?») → tipo de producción de la agenda (agenda-reglas.js)
window.TIPO_PROD_RESPUESTA = { "Acústica o live (2 días)": "acustico", "Full band (1 semana)": "fullband", "Producción grande (2 semanas)": "grande" };
