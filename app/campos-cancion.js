// Preguntas del formulario privado "Registra tu canción" (una liga por artista).
// Lo usan cancion/index.html (para pedir los datos) e index.html (Música → Canciones).
// Para agregar o cambiar una pregunta, edítala solo aquí.
// si: { k, v } muestra la pregunta solo cuando el campo k (multi o chips) incluye la opción v.
// tipo: text | email | tel | area (texto largo) | chips (opción única) | multi (varias opciones) | files (archivos)
window.CAMPOS_CANCION = [
  { id: "artista", titulo: "Sobre ti", intro: "Para saber quién comparte la canción y cómo contactarte.", campos: [
    { k: "nombre", l: "Nombre completo", req: true },
    { k: "nombreArtistico", l: "Nombre artístico o del ministerio", ayuda: "Como quieres que aparezca en la canción." },
    { k: "correo", l: "Correo", tipo: "email", req: true },
    { k: "telefono", l: "Teléfono o WhatsApp", tipo: "tel", req: true },
    { k: "ciudad", l: "Ciudad" },
    { k: "redes", l: "Redes o plataformas", ayuda: "Instagram, Spotify, YouTube… (ligas o usuarios)." }
  ]},
  { id: "cancion", titulo: "La canción", intro: "Lo esencial de la canción que quieres producir.", campos: [
    { k: "titulo", l: "Título de la canción", req: true },
    { k: "tipo", l: "¿Qué es?", tipo: "chips", ops: ["Canción original", "Cover o versión", "Adaptación o traducción"], req: true },
    { k: "original", l: "¿De qué canción es la versión y quién es el autor?", req: true, si: { k: "tipo", v: "Cover o versión" } },
    { k: "compositores", l: "Compositores", req: true, ayuda: "Nombre completo de cada persona que escribió letra o música y, si lo sabes, el porcentaje de cada una." },
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
    { k: "referencias", l: "Canciones de referencia", tipo: "area", req: true, ayuda: "Pega ligas de YouTube o Spotify y dinos qué te gusta de cada una (el sonido, la voz, el ritmo…)." },
    { k: "instrumentos", l: "Instrumentos que imaginas", tipo: "multi", ops: ["Piano o teclado", "Guitarra acústica", "Guitarra eléctrica", "Bajo", "Batería", "Percusiones", "Cuerdas", "Sintetizadores", "Vientos", "Otro"] },
    { k: "voces", l: "Voces", tipo: "chips", ops: ["Solista", "Dueto", "Coros o grupo", "Por definir"] },
    { k: "arreglo", l: "Ideas de arreglo o producción", tipo: "area", ayuda: "Momentos clave, dinámicas, cómo empieza o termina, algo que no debe faltar." }
  ]},
  { id: "archivos", titulo: "Demo y archivos", intro: "Todo lo que nos ayude a escucharla: demo, nota de voz, letra, partitura o cifrado.", campos: [
    { k: "archivos", l: "Sube tus archivos", tipo: "files" },
    { k: "ligaDemo", l: "Liga a tu demo (opcional)", ayuda: "Si tu archivo pesa más de 50 MB, súbelo a Drive o Dropbox y pega la liga aquí." }
  ]},
  { id: "fechas", titulo: "Fechas", intro: "Para planear la semana de producción con el ministerio.", campos: [
    { k: "disponibilidad", l: "¿Qué semanas o fechas podrías venir a producir?", tipo: "area", req: true, ayuda: "La producción dura una semana completa, de lunes a viernes." },
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

// Checklist definitivo: 14 pasos de producción + 8 de marketing (pipeline D-Day).
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
  ["Aprobación del master por el artista", "Producción", "Memo"],
  ["Registro INDAUTOR / SACM", "Registro", "Ariel", null, "el comprobante del registro INDAUTOR / SACM"],
  ["Splitsheet firmado", "Registro", "Memo", null, "el splitsheet firmado"],
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
window.ETAPA_POR_PASO = { 1: "preproduccion", 5: "agendada", 6: "produccion", 11: "registro", 14: "marketing", 22: "completado" };

// Semana de producción: lo que se hace cada día (lunes a viernes)
window.DIAS_PRODUCCION = ["Maqueteo", "Instrumentación", "Creación de contenido", "Cierre de instrumentación y voces", "Edición, mezcla y master"];
