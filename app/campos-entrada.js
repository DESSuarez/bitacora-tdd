// Preguntas del formulario "Entrada nueva · Formación".
// Lo usan entrada/index.html (el formulario público) e index.html (la pestaña Entradas de Formación).
// Para agregar o cambiar una pregunta, edítala solo aquí.
// si: { k, v } muestra la pregunta solo cuando el campo k (multi o chips) incluye la opción v.
// tipo: text | email | tel | area (texto largo) | chips (opción única) | multi (varias opciones) | modulos (temario) | files (documentos)
window.CAMPOS_ENTRADA = [
  { id: "formador", titulo: "Sobre ti", intro: "Para saber quién comparte esta propuesta y cómo contactarte.", campos: [
    { k: "nombre", l: "Nombre completo", req: true },
    { k: "correo", l: "Correo", tipo: "email", req: true },
    { k: "telefono", l: "Teléfono o WhatsApp", tipo: "tel" },
    { k: "organizacion", l: "Institución, comunidad o proyecto", ayuda: "Si colaboras con alguna." },
    { k: "experiencia", l: "Tu experiencia en este tema", tipo: "area", ayuda: "Tu formación, cuántas veces lo has impartido y con qué públicos." }
  ]},
  { id: "propuesta", titulo: "La propuesta", intro: "La idea general del curso o taller.", campos: [
    { k: "tipo", l: "¿Qué es?", tipo: "chips", ops: ["Curso", "Taller", "Retiro / camp", "Charla o conferencia", "Otro"], req: true },
    { k: "titulo", l: "Título tentativo", req: true },
    { k: "descripcion", l: "Descripción general", tipo: "area", req: true, ayuda: "¿De qué trata y por qué es importante?" },
    { k: "necesidad", l: "¿Qué necesidad o situación atiende?", tipo: "area" },
    { k: "objetivos", l: "Objetivos de aprendizaje", tipo: "area", req: true, ayuda: "Al terminar, los participantes podrán… Escribe uno por línea." }
  ]},
  { id: "participantes", titulo: "Participantes", intro: "A quién va dirigido.", campos: [
    { k: "perfil", l: "Perfil y características de los participantes", tipo: "area", req: true, ayuda: "Edad, ocupación, contexto, momento de vida o de fe." },
    { k: "edades", l: "Rango de edad", ayuda: "Ej. 15 a 22 años" },
    { k: "cupo", l: "Número ideal de participantes", ayuda: "Ej. 20 a 30" },
    { k: "previos", l: "Conocimientos o experiencia previa necesaria", tipo: "area" },
    { k: "consideraciones", l: "Consideraciones especiales", tipo: "area", ayuda: "Accesibilidad, idioma, nivel de lectura, temas sensibles…" }
  ]},
  { id: "formato", titulo: "Duración y formato", intro: "Cómo y cuánto tiempo se imparte.", campos: [
    { k: "modalidad", l: "Modalidad", tipo: "chips", ops: ["Presencial", "En línea en vivo", "En línea a su ritmo", "Híbrido"], req: true },
    { k: "duracion", l: "Duración total", req: true, ayuda: "Ej. 12 horas, un fin de semana, 6 semanas" },
    { k: "sesiones", l: "Número de sesiones" },
    { k: "duracionSesion", l: "Duración de cada sesión", ayuda: "Ej. 2 horas" },
    { k: "espacio", l: "Espacio o lugar ideal", ayuda: "Ej. salón con mesas, capilla, al aire libre, desde casa" }
  ]},
  { id: "metodologia", titulo: "Metodología", intro: "Cómo enseñas este tema. Entre más detalle, mejor podremos diseñarlo.", campos: [
    { k: "metodologia", l: "Describe tu metodología", tipo: "area", req: true, ayuda: "Enfoque, cómo se acomoda una sesión, momentos de oración, trabajo en equipo, práctica…" },
    { k: "actividades", l: "Actividades o dinámicas clave", tipo: "area", ayuda: "Las que no pueden faltar y por qué funcionan." },
    { k: "evaluacion", l: "¿Cómo sabes que aprendieron?", tipo: "area", ayuda: "Evaluación, productos finales, señales de cambio." }
  ]},
  { id: "recursos", titulo: "Recursos y materiales", intro: "Lo que se necesita para impartirlo y lo que habría que preparar.", campos: [
    { k: "recursosNecesarios", l: "¿Qué se necesita?", tipo: "multi", ayuda: "Marca todo lo que aplique.", ops: [
      "Presentación (diapositivas)", "Proyector", "Pantalla o TV", "Bocinas y audio", "Micrófono",
      "Instrumentos musicales", "Internet", "Pizarrón o rotafolio", "Material impreso para participantes",
      "Papelería y material para dinámicas", "Videos o música de apoyo", "Otro" ] },
    { k: "instrumentos", l: "¿Qué instrumentos musicales?", req: true, si: { k: "recursosNecesarios", v: "Instrumentos musicales" }, ayuda: "Ej. guitarra, teclado, cajón, batería, panderos. Indica cuántos si son varios." },
    { k: "recursosListos", l: "¿Qué materiales ya tienes listos?", tipo: "area", ayuda: "Presentaciones, cuadernillos, videos, canciones… Descríbelos aquí y súbelos justo abajo." },
    { k: "archivosMateriales", l: "Sube tus materiales", tipo: "files" },
    { k: "recursosCrear", l: "¿Qué materiales habría que crear?", tipo: "area", ayuda: "Ej. una presentación, un cuadernillo de trabajo, un video introductorio, instrumentos de evaluación." },
    { k: "recursosDetalle", l: "Detalles o algo más que se necesite", tipo: "area", ayuda: "Cantidades, especificaciones o lo que marcaste como «Otro»." }
  ]},
  { id: "contenido", titulo: "Contenido", intro: "Los temas, en el orden en que los impartes.", campos: [
    { k: "modulos", l: "Temario", tipo: "modulos", req: true },
    { k: "recursos", l: "Bibliografía, ligas y recursos", tipo: "area", ayuda: "Libros, documentos, videos o páginas en los que te basas." }
  ]},
  { id: "documentos", titulo: "Documentos de referencia", intro: "Lecturas, guías, manuales o investigaciones en las que te basas para este tema.", campos: [
    { k: "archivos", l: "Documentos", tipo: "files" },
    { k: "comentarios", l: "¿Algo más que debamos saber?", tipo: "area" }
  ]}
];

window.ESTADOS_ENTRADA = [
  ["nueva", "Nueva"],
  ["revision", "En revisión"],
  ["diseno", "En diseño"],
  ["disenado", "Diseñado"],
  ["descartada", "Descartada"]
];
