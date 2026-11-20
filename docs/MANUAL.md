# Manual de construcción · Bitácora Tiempo de Dios

Este manual explica **cómo está construido el sistema y cómo seguir construyéndolo**: qué pieza hace qué, dónde se cambia cada cosa y en qué orden se despliega.
Se actualiza **con cada cambio**: al terminar una función nueva se agrega su entrada en la [Bitácora de cambios](#13-bitácora-de-cambios) y se corrige la sección que cambió.

> Para el contexto rápido (roles, rutas, modelo de datos al detalle) está `CLAUDE.md`. Para poner en marcha un proyecto nuevo de Supabase, `README.md`. Este manual une ambos y explica el porqué.

---

## 1. Qué es

Plataforma de trabajo de Tiempo de Dios en **pm.tiempodedios.mx**. Cada área registra pendientes, avances y logros; la Project Manager ve todo.

**Áreas:**

| Área | Color |
|---|---|
| Formación | `#457A7F` |
| Música | `#FF3D1A` |
| Audiovisual | `#98D5E0` |
| Operativo | `#F2B33D` |
| Legal | `#7E5BD0` |
| Marketing | `#D9558E` |

**Módulos grandes:**
- Dashboard: lecturas del día y calendario por área.
- Canciones: el funnel de producción repartido en Música, Legal y Marketing.
- Agenda de producción y el enlace para artistas.
- Finanzas: gastos, ingresos y activos.
- Entradas de Formación.
- Equipo y perfiles.

## 2. Stack

| Capa | Herramienta |
|---|---|
| Interfaz | `app/index.html`: HTML, CSS y JS en un solo archivo, **sin framework ni build** |
| Librerías (CDN) | `@supabase/supabase-js@2.45.4` (UMD) y `jspdf@2.5.1` (PDF en el navegador) |
| Base de datos, sesión, archivos y tiempo real | Supabase: Postgres con RLS, Auth, Storage, Realtime y pg_cron |
| Funciones del servidor | Supabase Edge Functions (Deno): `equipo`, `bright-task` (avisos por correo), `samply` y `crm` (correos y WhatsApp de Personas) |
| Lecturas del día | `app/evangelio.php`, que corre en Hostinger |
| Hosting | Hostinger: cada push a `main` se despliega solo. El `.htaccess` sirve únicamente `app/` |

## 3. Mapa del repositorio

```
app/
  index.html            La app completa
  config.publico.js     URL y anon key de Supabase (públicas por diseño)
  campos-entrada.js     Preguntas y estados del formulario de Entradas de Formación
  campos-cancion.js     Preguntas del formulario de canciones, etapas, checklists (estudio y live)
                        y qué área trabaja cada paso (AREA_PASO)
  agenda-reglas.js      Reglas de la agenda de producción (semanas, bloques, tipos, fijos)
                        → las comparten index.html y agenda/
  entrada/index.html    Formulario público de Formación (/entrada/)
  cancion/index.html    Formulario privado de canciones (/cancion/<ministerio>)
  agenda/index.html     Enlace de agenda para artistas (/agenda/<código>)
  registro/index.html   Registro público a cenáculos y eventos (/registro/cenaculo), liga personal
                        para confirmar (?t=…&e=…&f=…) y baja de correos (?baja=…)
  evangelio.php         Lecturas del día (Vatican News + salmo de dominicos.org)
supabase/
  schema.sql            Esquema base (proyectos nuevos)
  migraciones/NNN_*.sql Cambios para el proyecto que ya existe (se corren en orden)
  functions/            Edge Functions (equipo, avisos → «bright-task», samply, crm)
  correos/              Plantillas de correo en español
docs/MANUAL.md          Este manual
docs/ESTRATEGIA-CORREO.md  Estrategia de correo y WhatsApp para la comunidad (plantillas y calendario)
.htaccess               Reescrituras: /cancion/<slug>, /agenda/<código>, /registro/<evento> y todo lo demás → app/
```

## 4. Cómo trabajar

1. **Probar en local:** `cd app && python3 -m http.server 8000`, con un proyecto de Supabase de prueba en `config.js`, que no se versiona.
   - Para probar solo la interfaz sin red, se usa un `mock.js` que imita a Supabase. Se reemplaza el `<script>` de supabase-js por `mock.js` y se entra con `?como=<usuario>`.
2. **Cambios de base de datos:** van en una migración nueva, `supabase/migraciones/NNN_nombre.sql`, que:
   - debe poder correrse dos veces sin error (`if not exists`, `drop policy if exists`, `create or replace`);
   - se corre en Supabase → SQL Editor → **Run**. Si pregunta por RLS, elige «Run without RLS», porque la migración ya la activa.
3. **Desplegar:** `git push origin main` y Hostinger publica en segundos.
   - **Primero corre la migración y después haz el push**, si la app nueva depende de ella.
4. **Edge Functions:** se despliegan aparte en Supabase (Edge Functions → Deploy). Los secretos (`SAMPLY_TOKEN`, `SMTP_USER`, `SMTP_PASS`) van en Edge Functions → Secrets, **nunca en el código**.
5. **Convenciones:**
   - Todo en español: interfaz, comentarios y commits.
   - Commits descriptivos (qué cambió y para quién).
   - Si cambia `evangelio.php`, sube `LECTURAS_V` en `index.html`.

## 5. Arquitectura de `index.html`

- **Capa de datos:** `makeCol(tabla)` imita una API de colecciones estilo Firestore (`doc(id).set`, `delete`, `onSnapshot`) sobre tablas Supabase con una columna `data jsonb`. La usan `tareas`, `logros` y `eventos`. Las tablas nuevas (`canciones`, `gastos`, `activos`, `agendas_artistas`, `solicitudes_area`…) se leen directo con `sb.from()` y Realtime.
- **Render:** `render()` → `dibujar()` decide la vista según `route` (hash) y la pestaña (`areaView[área]`, `pmView`, `dashView`, `finView`).
  - `renderKeep()` no redibuja mientras alguien escribe (notas, arrastre, edición, ventanas).
  - `FORMS_VIVOS` guarda y restaura los formularios abiertos cuando llega un cambio en tiempo real.
- **Permisos en la app:** `esPM()` (pm/desarrollador), `canEdit(área)`, `enArea(perfil, área)`, `puedeMusica()`, `puedeCanciones()`, `puedeFin()`. Siempre deben ir **de la mano** con la RLS en SQL: `es_pm()`, `puede_area()`, `puede_canciones()`, `puede_finanzas()`.
- **Escrituras:** `write(id, fn)` las pone en cola por documento, y los errores se muestran en la barra de estado.

## 6. Áreas y accesos

- **Cada quien ve solo sus áreas:** su `area` y sus `areas` adicionales. La PM y el desarrollador ven todas.
  - Las demás no aparecen en el menú. Si alguien entra por liga, ve «No estás en X» con un botón para **solicitar acceso** (tabla `solicitudes_area`).
  - La PM aprueba en **Project Manager → Equipo**: el área se agrega a `perfiles.areas`, o queda como su área si no tenía.
- Hoy el límite es de **interfaz**: la RLS de lectura de `tareas` y `logros` sigue abierta a todo el equipo, y la de escritura sí exige el área.
- **Para agregar un área nueva:**
  - **Migración:** amplía los `check` de `perfiles.area`, `perfiles.areas`, `tareas.area`, `logros.area` y `solicitudes_area.area`.
  - **`index.html`:**
    - entrada en `AREAS` (nombre, color, tipos de logro);
    - ícono en `AREA_ICON`;
    - variables de color `--x`, `--x-ink` y `--x-soft` en los tres temas: día, noche y retro;
    - `body[data-area="x"]`;
    - enlace en el menú `.areanav`;
    - `areaView`.

## 7. Canciones: un funnel, tres áreas

- **Checklist de estudio:** `CHECKLIST_CANCION` en `campos-cancion.js`, 24 pasos.
  - El número de paso es la llave guardada en `canciones.checklist`. **No reordenes**: agrega pasos al final o haz una migración que reacomode, como la 018 o la 021.
- **Qué área trabaja cada paso:** `AREA_PASO`.

  | Área | Pasos | Cuándo se abre |
  |---|---|---|
  | **Música** (producción) | 1–12 y 15 (DistroKid) | Siempre. Su avance es el que se ve en las barras y en las métricas de Música |
  | **Legal** | 13 INDAUTOR/SACM y 14 splitsheet, con documento obligatorio | Al aprobar la composición (paso 2). Si la canción tiene **un solo autor**, el 14 se marca solo |
  | **Marketing** | 16 handoff y 17–24 D-Day | Cuando Música llega al **100 %**. Antes sus pasos están bloqueados |

- **Pendientes automáticos:** cada área tiene **un solo pendiente abierto por canción**, su siguiente paso. El id es `cancion-<id>-p<n>`.
  - Al completarlo (en Pendientes o en el checklist) se marca el paso, avanza la etapa (`ETAPA_POR_PASO`) y se crea el siguiente (`crearPendiente` / `crearTareaPaso`).
  - Los pasos ya completados **no se listan** en Pendientes; viven en el checklist de la canción.
  - Al abrir la app se hace un barrido (`barrerPendientes`) para que las canciones que ya existían tengan su pendiente en cada área abierta.
- **Lives:** se manejan con `CHECKLIST_LIVE`, de 6 pasos, y todo vive en Música.
  - Grabación (4) y Post (5) crean además un pendiente en **Audiovisual** (`AV_PASO_LIVE`, id `…-p<n>-av`).
  - Si se completa cualquiera de los dos, se cierran ambos.
- **Vistas:** Música → Canciones (por ministerio, por etapa, ligas para nuevas canciones y agenda para artistas). Legal → Registros. Marketing → Lanzamientos. Desde cualquiera se abre el detalle de la canción.

## 8. Calendario y agenda de producción

- **Datos:** tabla `eventos`, con la forma `{titulo, tipo, fecha, fin?, hora?, horaFin?, repetir?, hasta?, excepciones[], area, notas, cancion_id?, tipoProd?}`.
  - `area` dice **de qué calendario** es: un área o `general` (de todos).
- **Calendarios por área:**
  - Cada quien ve el general y los de sus áreas.
  - La PM y el desarrollador ven todo, con filtros por área. La PM además tiene **Project Manager → Calendario**, con el nombre del calendario en cada evento.
- **Tipos:** producción, fecha fija, reunión, ensayo, evento, grabación, lanzamiento, cenáculo, día inhábil, actividad externa (viernes ocupado) y otro.
  - La **oración de los miércoles de 9 a 12** es fija: vive en `AGENDA.FIJOS`, no en la base.
- **Reglas (`agenda-reglas.js`):** son las mismas para la app y para el enlace de artistas.
  - **Horario laboral:** de 9:00 a 17:00.
  - **Semanas de cada mes:**
    - La 1.ª, 2.ª y 3.ª semana que **empiezan** en el mes son de producción.
    - La 4.ª (y la 5.ª, si la hay) es de **colchón**: contratiempos y grabaciones externas, como batería.
  - **Días de producción:**
    - Bloque **A** lunes-martes y bloque **B** jueves-viernes. El miércoles es para las demás áreas.
    - Si el viernes está ocupado por una actividad externa (tipo `externo`), el bloque B pasa a miércoles-jueves y ese viernes solo se trabaja de 9 a 11.
  - **Tipos de producción:**

    | Tipo | Días | Ocupa |
    |---|---|---|
    | Acústica o live | 2 | 1 bloque |
    | Full band | 5 | La semana completa: lun, mar, jue y vie (o lun a jue si el viernes está ocupado) |
    | Producción grande | 10 | 2 o más semanas completas |

  - **Días exactos:** cada producción guarda `dias` (`AGENDA.diasHabiles`): entre semana y sin el miércoles cuando ese viernes también se produce. Así el miércoles queda libre para las demás áreas.
  - **Disponibilidad en la app:**
    - En **acústica** se elige un bloque.
    - En **full band** y **grande** cada semana es una sola opción («Toda la semana»), y se pueden **marcar varias**: «Agendar N producciones full band» crea una por semana; «Agendar producción grande» crea una por semana, agrupadas con `grupo`.

  - **Qué ocupa producción:** eventos `produccion`, `inhabil` y `grabacion` ligados a una canción.
  - **Cenáculos y eventos:** no pueden caer entre 9 y 17 en un día con producción. Los atajos de horario son 19–21 y 20–22.
- **Dashboard de quien tiene Música:**
  - disponibilidad de 12 semanas por bloques, con selector de tipo;
  - **producción por mes** de los próximos 6 meses;
  - apartado de **Eventos**: cenáculos, eventos y viernes ocupados.
- **Enlace de agenda para artistas** (Música → Canciones → «Agenda para artistas»):
  - **Ministerios del colectivo:** cada uno tiene una **liga fija por tipo de producción**, `/agenda/<ministerio>-<acustica|fullband|grande>`. El ministerio es el mismo slug de su liga de canciones o, si no tiene, uno sacado del nombre.
    - Se crea la primera vez que se copia (`ligaFija`, con `reutilizable = true`).
    - Sirve para cada canción nueva: el artista puede escribir qué canción es y, al terminar, «Agendar otra canción».
  - **Artista invitado (fuera del colectivo):** generador de una liga especial de **un solo uso** con código aleatorio, que se cierra al apartar. Igual funciona el botón «🔗 Enlace de agenda» de cada canción, que liga la reserva a esa canción.
  - **Se guarda en** la tabla `agendas_artistas`: `token`, `tipo`, `nombre`, `reutilizable`, `reservado` (la última reserva) y `reservas` (todas).
  - El artista ve **12 meses** de disponibilidad desde el día en que abre la liga. Sus datos de contacto se llenan solos si ya los dio en ese dispositivo.
  - **Funciones públicas** (security definer):
    - `agenda_ver(t)`: devuelve el tipo y **solo las fechas ocupadas**, sin títulos ni notas;
    - `agenda_reservar(...)`: vuelve a revisar que las fechas sigan libres, crea el evento de producción y marca la canción como agendada.

## 9. Otras piezas

- **Lecturas del día:** las sirve `evangelio.php`, que guarda una copia por día en el servidor. La app guarda su copia en localStorage con la versión `LECTURAS_V`.
- **Samply:** Edge Function `samply`. Sirve para vincular una pista y abrirla con ▶. Si el proyecto no aparece en la lista, se pega la liga a mano.
- **Avisos por correo:** Edge Function `bright-task` con pg_cron diario.
- **Finanzas:**
  - tablas `gastos`, `ingresos` y `activos`;
  - bucket privado `finanzas`;
  - `puede_finanzas()`.
- **Entradas de Formación:** formulario público. Las preguntas viven en `campos-entrada.js`.
- **Temas:** Día, Noche, Retro y Auto. **Retro solo cambia la paleta** (neón sobre morado). Cualquier color nuevo se define en los tres temas.

## 9 bis. Trivia del día y Sugerencias

- **Trivia del día:**
  - **Preguntas:** viven en `app/trivia.js` (`TRIVIA_CATEGORIAS`, `TRIVIA`). Cada una lleva `{id, cat, q, ops[4], ok, exp, fuente}` y se verifica contra el Catecismo (vatican.va), la Biblia, documentos del Magisterio o fuentes de historia confiables.
  - **Para agregar preguntas:** súmalas al final con un `id` nuevo, sin cambiar los ids existentes.
  - **Criterio:** cada pregunta debe verificarse contra su fuente antes de entrar. Si un dato está en duda, no se pregunta.
  - **Cuáles salen:** 3 al día, iguales para todo el equipo (`preguntasDelDia`), recorriendo cada categoría en orden.
  - **Ventana:** sale sola una vez al día al entrar (`popupTrivia`). Se puede cerrar y jugar desde Mi trabajo.
  - **Respuestas y racha:** se guardan en `trivia_respuestas`, una por persona y día. La **racha 🔥** cuenta los días seguidos con la trivia hecha (`racha`, `mejorRacha`) y se ve en el perfil y en Equipo.
- **Sugerencias** (`#sugerencias`, menú General):
  - **Quién propone:** cualquiera propone una mejora, un error o una idea, con un máximo de 5 abiertas por persona (la RLS lo hace cumplir).
  - **Quién gestiona:** la PM y el desarrollador las aprueban o no, con una respuesta, y las mueven a «En proceso» y «Hecha». Quien la propuso recibe un aviso cuando cambia de estado.
  - **Para trabajarlas con Claude Code:** «📋 Copiar aprobadas» copia la lista lista para pegar.
- **Scripts pendientes:**
  - Solo el desarrollador ve en Sugerencias qué migraciones faltan. La app compara `app/migraciones.js` contra la tabla `migraciones_aplicadas`.
  - **Regla:** cada migración nueva se agrega a `migraciones.js` y termina con `insert into public.migraciones_aplicadas (nombre) values ('NNN_nombre') on conflict (nombre) do nothing;`. Así se registra sola al correrla.

- **Archivos:** cada sugerencia puede llevar archivos (capturas, documentos, .zip con prompts; 50 MB c/u) en el bucket privado `sugerencias` (`<usuario>/<sugerencia>/…`); se descargan con URL firmada de 1 h (028).

## 9 ter. Documentos

- **`#documentos`** (menú General) junta en un solo lugar todos los archivos y ligas subidos a tareas y subtareas.
- **Se arma solo** a partir de las tareas (`entregablesRange`): no hay que subir nada dos veces y se actualiza en vivo.
- **Buscador:** encuentra por nombre, tarea, proyecto o quién lo subió.
- **Filtros:** por tipo (archivos o ligas), por periodo y por área. Tocar el nombre de la tarea lleva a esa tarea en Pendientes.
- **Quién ve qué:** cada quien ve los de sus áreas y los de las tareas que tiene asignadas; la PM y el desarrollador, todos (`docsVisibles`).

## 9 quater. Operativo → Personas (asistentes, seguimiento y donadores)

Pestaña **Personas** en Operativo (`areaView.operativo = "crm"`, liga directa `#operativo/personas`). La ven Operativo (también como área adicional), la PM y el desarrollador (`puedeCrm()`; en SQL `puede_area('operativo')`). Migración **027**, Edge Function **`crm`**.

- **Tablas:**
  - `crm_personas`: un perfil único por persona (nombre, teléfono, correo, cumpleaños, empresa, cargo, ciudad, origen, responsable, `estado`, `proxima_accion`/`proxima_fecha`, notas, `acepta_correos`, `acepta_whatsapp`, `donador`, `token` para su liga personal). Índice único por correo; `tel_digitos` (últimos 10 dígitos) para buscar por teléfono.
  - `crm_asistencias`: persona × evento × fecha (`evento` = id en `eventos`; los cenáculos se repiten, por eso va la fecha). Estados: invitado, registrado, confirmo, asistio, no_asistio, cancelo. `origen`: formulario, puerta o manual.
  - `crm_seguimientos`: historial de conversaciones (medio, resumen, interés, próxima acción y fecha, estado al que pasó). Los cambios de estado hechos a mano quedan como `medio = 'sistema'`.
  - `crm_donaciones`: solo Finanzas, la PM y el desarrollador (`puede_finanzas() or es_pm()`). Estados comprometida / recibida / cancelada; **los totales solo suman las recibidas**.
  - **Finanzas es la fuente única del dinero (028):** una donación es el compromiso; al recibirse queda ligada a su ingreso de Finanzas (`crm_donaciones.ingreso` → `ingresos.id`) y el monto que cuenta es el del ingreso (`montoDon`, `recibidoDe`). «Marcar recibida» (solo quien tiene 💰 Finanzas) registra un ingreso nuevo categoría «Donativos» o liga uno que Finanzas ya había registrado (`formRecibir`). Un trigger impide «recibida» sin ingreso y la regresa a «comprometida» si en Finanzas se borra el ingreso. Las tablas de Finanzas no cambian. Un trigger pone `crm_personas.donador` para que Operativo vea 💛 sin ver montos.
  - `crm_mensajes`: correos y WhatsApp enviados y recibidos; `clave` única evita mandar dos veces lo mismo.
  - `crm_boletines`: newsletters (borrador → enviando → enviado).
- **Sin duplicados:** `crm_guardar_persona()` busca por correo y luego por teléfono (si alguno de los dos no tiene correo) y completa lo que falte. La usan el registro público y el alta en la puerta. Al dar de alta a mano, la app avisa si ya existe alguien con ese correo o teléfono (`crmDuplicado`).
- **Vistas** (`renderCrm`):
  - **Resumen:** indicadores (personas, donadores, recibido y comprometido solo para Finanzas/PM, sin contactar, seguimientos de hoy y vencidos) y listas: seguimientos de hoy, «vinieron y nadie los ha contactado», interesados, sin próxima acción, cumpleaños de la semana, donaciones comprometidas sin recibir y próximas fechas. Filtro por responsable.
  - **Personas:** buscador (nombre, teléfono, correo), filtros por estado y donadores, «+ Persona» y CSV de respaldo (montos solo para Finanzas/PM).
  - **Perfil** (`crmPersonaHTML`): contacto con botones de WhatsApp, llamada y correo; estado y responsable; registrar conversación (con próxima acción y fecha); historial cronológico (conversaciones + correos + WhatsApp); eventos; donaciones; datos generales. Solo la PM borra personas.
  - **Pase de lista** (`crmPaseLista`): elige la fecha (cenáculos y eventos con registro, 90 días atrás y 60 adelante), liga de registro para copiar, ✓ Vino / ✗ No vino por persona (tocar otra vez lo regresa a «Registrado»), **alta en la puerta** (`crm_puerta()`: la crea o la encuentra y la marca «Vino»), agregar a alguien de la base y, al final, «Marcar No vino» a quien no se marcó. Antes del evento, botón 💬 por persona con el mensaje y su liga para confirmar.
  - **Correos y WhatsApp** (`crmCorreos`): estado de las conexiones, calendario de envíos, invitaciones automáticas por evento (botón por evento), newsletter (borrador, vista previa, prueba a tu correo y envío en tandas de 40) y últimos mensajes de WhatsApp.
- **Calendario:** los cenáculos siempre tienen registro. En un evento normal se marca «Registro de asistentes» (`registro`) y, en ambos, «Invitar por correo 15 y 7 días antes» (`invitar`) y el **Lugar** (`lugar`).
- **Registro público** `app/registro/index.html`:
  - `/registro/cenaculo` muestra los próximos cenáculos; `/registro/<id del evento>` uno solo; `?e=<id>&f=<fecha>` preselecciona la fecha.
  - Pide nombre, teléfono, correo y cumpleaños, más la casilla de correos. Tiene campo trampa contra bots y recuerda los datos en ese navegador («No soy yo»).
  - Funciones públicas: `registro_eventos()` (solo título, fecha, hora y lugar), `registro_evento(...)`, `crm_responder(t, ev, f, r)` (liga personal: `info`, `registrar`, `si`, `no`) y `crm_baja(t)`. `evento_ocurre()` revisa en SQL que la fecha sí sea del evento (misma regla que `ocurrencias()`).
- **Edge Function `crm`** (`supabase/functions/crm/index.ts`; desplegar con **Verify JWT apagado**):
  - `diario` (pg_cron `bitacora-crm`, 9:00 de México): invitaciones por correo 15 y 7 días antes a quien acepta correos y no se ha registrado (máximo una invitación cada 6 días por persona y `CRM_MAX_DIA` correos por corrida); WhatsApp 2 días antes a los registrados; resumen por correo a cada persona de Operativo (sus seguimientos de hoy y vencidos, cumpleaños; a los líderes, lo que no tiene responsable); los lunes, a Finanzas, las donaciones comprometidas que ya pasaron su fecha.
  - `boletin`, `prueba`, `wa_recordar`, `wa_texto` y `estado` (solo Operativo, PM y desarrollador).
  - Webhook de WhatsApp: verifica con `WA_VERIFY_TOKEN`, revisa la firma con `WA_APP_SECRET`, guarda los mensajes, marca «Confirmó» o «Canceló» con los botones y actualiza el estado de entrega (enviado, entregado, leído).
  - Correos con remitente «Tiempo de Dios», logo incrustado y liga para darse de baja (también en la cabecera `List-Unsubscribe`).
- **Conectar WhatsApp (una sola vez):**
  1. En Meta Business (business.facebook.com) crea una app de tipo Business con el producto **WhatsApp** y agrega el número de la empresa. Ojo: el número pasa a la API (con la «coexistencia» de Meta se puede seguir usando la app de WhatsApp Business en el celular).
  2. Crea un **usuario del sistema** con token permanente (permisos `whatsapp_business_messaging` y `whatsapp_business_management`).
  3. Crea la plantilla **`recordatorio_evento`** (categoría Utilidad, idioma Español (MEX) `es_MX`). Cuerpo: «Hola {{1}}, te esperamos en {{2}} el {{3}} a las {{4}}. ¿Nos confirmas si vienes?». Dos botones de respuesta rápida: «Sí voy» y «No podré». Espera la aprobación.
  4. En Supabase → Edge Functions → `crm` → Secrets: `WA_TOKEN`, `WA_PHONE_ID` (Phone number ID), `WA_VERIFY_TOKEN` (una palabra que inventes), `WA_APP_SECRET` (App secret) y, si cambian, `WA_PLANTILLA` y `WA_IDIOMA`.
  5. En Meta → WhatsApp → Configuración → Webhook: URL `https://zhzqvetehynndfjbrzti.supabase.co/functions/v1/crm`, token de verificación = `WA_VERIFY_TOKEN`, y suscríbete a **messages**.
  6. En la app, Operativo → Personas → Correos y WhatsApp debe decir «Conectado».
- **Estrategia de correo y plantillas:** `docs/ESTRATEGIA-CORREO.md`.

## 10. Migraciones

| # | Qué hace |
|---|---|
| 002–011 | Perfiles, fotos, roles, usuario, entregables, Operativo y varias áreas, avisos, bio, perfil propio |
| 012 | Entradas de Formación |
| 013 | Eventos, ligas de artistas, canciones |
| 014–016 | Portada, ministerio y lanzamiento, saludo |
| 017 | Finanzas y documentos de Música |
| 018 | Samply y las dos escuchas |
| 019 | Activos |
| 020 | Ligas limpias `/cancion/<ministerio>` |
| 021 | Paso DistroKid (checklist de 24 pasos) |
| **028** | `crm_donaciones.ingreso` (donación recibida = ingreso de Finanzas, sin duplicar) y archivos en Sugerencias (`sugerencias.archivos`, bucket privado `sugerencias`, 50 MB) |
| **027** | Operativo → Personas: `crm_personas`, `crm_asistencias`, `crm_seguimientos`, `crm_donaciones`, `crm_mensajes`, `crm_boletines`; funciones públicas del registro; cron `bitacora-crm` que llama a la función `crm` |
| **026** | `trivia_respuestas`, `sugerencias`, `migraciones_aplicadas`; el responsable de una tarea la puede editar aunque sea de otra área; archivos entregables para áreas adicionales y responsables |
| **025** | Del registro de canción a la agenda: `ministerios_colectivo()`, `agenda_de_liga()`, `agendas_artistas.liga` y `agenda_reservar(..., c_id)` ligada a la canción |
| **024** | `agenda_reservar` guarda los días exactos (`dias`) de lo que aparta un artista |
| **023** | Liga fija de agenda por ministerio (`reutilizable`, `reservas`; códigos con guiones) |
| **022** | Áreas Legal y Marketing, permisos de canciones para Legal, Marketing y Audiovisual, pendientes del funnel por área, `agendas_artistas` y sus funciones públicas, `solicitudes_area` |

## 11. Seguridad

- La anon key es pública. Lo que protege es la RLS.
- La service_role key y los tokens (Samply, SMTP) viven solo en Supabase.
- Los datos de Personas solo los leen Operativo, la PM y el desarrollador; los montos de donaciones, solo Finanzas, la PM y el desarrollador. El registro público no puede leer la base: solo llama funciones que devuelven lo mínimo (título, fecha, hora y lugar del evento, o el primer nombre con la liga personal).
- Los formularios públicos (entrada, canción, agenda, registro) usan funciones `security definer` que devuelven lo mínimo. Además llevan `noindex` y `no-referrer`.
- Un token que se haya compartido por chat o correo se **rota**.

## 12. Pendientes conocidos

- **Correo SMTP propio** en Supabase para las invitaciones (ver `CLAUDE.md`).
- **Restringir también la lectura** por área en la RLS de `tareas` y `logros`, si se quiere que el límite de acceso sea más que de interfaz.
- **Avisar por correo** al equipo de Música cuando un artista aparte fechas desde su enlace.
- **Normalizar datos** y **migrar a Vite + React** cuando el `index.html` crezca más (roadmap en `CLAUDE.md`).

## 13. Bitácora de cambios

Formato: fecha · qué cambió · dónde.

- **2026-11-20**
  - **Donaciones y Finanzas:** lo recibido ya no se registra dos veces: cada donación recibida se liga a su ingreso de Finanzas y toma de ahí el monto (migración 028, `index.html`: `formRecibir`).
  - **Sugerencias con archivos:** capturas, documentos o .zip con prompts (hasta 50 MB), que se descargan con liga temporal. Al copiar las aprobadas salen los nombres de los archivos. Lo pidió Ceci (`index.html`, migración 028).
  - **Navegación:** los botones ‹ › miden lo mismo de alto que la etiqueta del área.
  - **Navegación:** botones ‹ › de atrás y adelante en la banda de todas las pantallas. Recuerdan sección, pestaña y detalle abierto, también entre pestañas de una misma área (`index.html`: `registrarNav`, `irNav`).
  - **Dashboard:** flechas ← → junto a Día/Semana/Mes/Año para moverse por el calendario, con «Hoy» para regresar (`index.html`: `calNav`).
  - **Personas:** el botón CSV es del mismo tamaño que «+ Persona».
  - **Operativo → Personas:** base de asistentes y donadores con perfil único, seguimiento (estados, conversaciones, próxima acción, responsable), cumpleaños, donaciones (montos solo Finanzas/PM), pase de lista por fecha de cenáculo o evento con alta en la puerta, y resumen con alertas (`index.html`: `renderCrm` y vecinas; migración 027).
  - **Registro público** `/registro/cenaculo` con nombre, teléfono, correo y cumpleaños; liga personal para confirmar o cancelar y baja de correos (`app/registro/`, `.htaccess`).
  - **Correos y WhatsApp:** invitaciones 15 y 7 días antes, newsletter en tandas, recordatorio por WhatsApp 2 días antes con botones (listo para conectar a la API de Meta) y resumen diario para Operativo (`supabase/functions/crm`, cron `bitacora-crm`).
  - **Calendario:** lugar, registro de asistentes e invitaciones por correo en cenáculos y eventos (`index.html`: editor de eventos).
  - **Estrategia de correo** con plantillas (`docs/ESTRATEGIA-CORREO.md`).
- **2026-11-19**
  - **Documentos:** nueva sección con todos los archivos y ligas de las tareas, con buscador y filtros. La pidió Ceci y se arma sola desde las tareas (`index.html`: `renderDocumentos`).
- **2026-11-17** (noche, 4)
  - **Trivia:** banco ampliado a **230 preguntas**: 60 de Catecismo, 48 de Historia, 65 de Nuevo Testamento y 57 de Apologética. Alcanza para unos 2½ meses sin repetir.
    - Las nuevas (ids `v…`) se verificaron contra el texto oficial del Catecismo y de la Biblia del Pueblo de Dios en vatican.va, documentos de la Santa Sede y la Catholic Encyclopedia.
    - Se quitaron 22 que repetían las del banco inicial.
    - Quedaron fuera los datos discutidos o sin fuente clara, como fechas inciertas de canonización o de patronazgos, y los temas pastoralmente delicados.
- **2026-11-17** (noche, 3)
  - **Trivia:** banco inicial de 53 preguntas con fuente: 15 de Catecismo, 14 de Historia, 12 de Nuevo Testamento y 12 de Apologética. Con él ya salen la ventana diaria y el botón en Mi trabajo. El banco ampliado y verificado se sumará después, conservando estos ids (`app/trivia.js`).
- **2026-11-17** (noche, 2)
  - **Trivia del día:** banco verificado en `trivia.js`, ventana una vez al día y racha 🔥 en el perfil y en Equipo.
  - **Sugerencias:** sección para proponer cambios, con aprobación y seguimiento de la PM y el desarrollador, y copia para Claude. El desarrollador ve ahí los scripts pendientes (`migraciones.js`).
  - **Tareas:** el responsable de una tarea (o de una subtarea) la puede editar y completar aunque sea de otra área. Los archivos entregables ya aceptan las áreas adicionales.
  - Todo esto con la migración 026.
- **2026-11-17** (noche)
  - **Mi trabajo:** tocar el nombre de un pendiente (o «+») abre ahí mismo el editor completo de la tarea: datos, notas, ligas, archivos y subtareas (`taskItem` dentro de `#personPend`).
  - **Inicio:** al entrar a la app siempre aparece el Dashboard, para todos los roles. Las ligas con `#área` o `#persona/…` siguen abriendo su página (`index.html`: `readHash` y arranque).
  - **Reabrir lo que se marcó por error:**
    - «Completado esta semana» (perfil y Mi trabajo) tiene casilla para desmarcar.
    - `puedeTarea(t)`: quien está en el área, o quien trabaja canciones para cualquier paso de canción. Así Música puede reabrir un paso de Legal o Marketing.
    - Al reabrir un paso de canción, también se desmarca en su checklist.
  - **Tareas:** completar una tarea ya no completa sus subtareas, que se marcan por separado. Si todas las subtareas quedan hechas, la tarea se marca sola (`index.html`: `toggleTask`, `toggleSub`).
- **2026-11-17** (tarde)
  - **Registro de canción:**
    - «Artista o ministerio» es un selector con los ministerios del colectivo (`ministerios_colectivo()`). El de la liga ya viene elegido y tiene «Otro…».
    - «Canciones de referencia» va en renglones con liga y «qué te gusta», más «+ Agregar otra referencia» (tipo `lista`, guardado en `referencias` y `referenciasLista`).
  - **Fechas:**
    - El artista elige el tipo de producción (`tipoProduccion`).
    - Al enviar, pasa a la liga fija de agenda de su ministerio para ese tipo (`agenda_de_liga()`) con `?c=<canción>`. Lo que aparte queda ligado a la canción y cierra el pendiente «Agendar producción».
    - Si prefiere no elegir, el pendiente sigue abierto para que Música coordine.
    - Archivos: `campos-cancion.js`, `cancion/index.html`, `agenda/index.html` y migración 025.
- **2026-11-17**
  - **Registro de canción: «Compositores»** es una lista que crece. Empieza con un renglón (nombre y % opcional) y tiene «+ Agregar otro compositor». Valida que los porcentajes no pasen de 100 %.
    - Se guarda como texto en `compositores` y como lista en `compositoresLista`.
    - Con un solo compositor, `data.unAutor = true`, y Legal da por hecho el splitsheet.
    - Archivos: `campos-cancion.js` (tipo `personas`) y `cancion/index.html`.
  - **Formularios de artistas:**
    - Los datos de contacto (nombre, nombre artístico, correo, teléfono, ciudad, redes) se guardan en el dispositivo del artista al enviar y se llenan solos la siguiente vez, en el registro de canción y en la agenda. Hay un botón «No soy yo» para borrarlos. Nunca se leen de la base.
    - El nombre artístico se llena con el nombre del ministerio de la liga.
    - Archivos: `cancion/index.html` y `agenda/index.html`, clave `tdd-contacto-artista` en localStorage.
  - **Agenda para artistas:** muestra 12 meses de disponibilidad desde el día en que se abre la liga (`agenda/index.html`).
- **2026-11-16** (noche)
  - **Disponibilidad:** full band y grande se agendan por semana completa (lun, mar, jue, vie, o lun a jue con el viernes ocupado), con selección de varias semanas a la vez. Las producciones ya no ocupan el miércoles (`agenda-reglas.js`, `index.html`, migración 024).
- **2026-11-16** (tarde)
  - **Agenda:** liga fija por ministerio del colectivo y tipo de producción (`/agenda/surgit-iglessia-fullband`) y generador de ligas de un solo uso para artistas invitados (`index.html`, `agenda/index.html`, `.htaccess`, migración 023).
- **2026-11-16**
  - **Tema Retro solo colores:** sin letra pixelada ni efectos (`index.html`).
  - **Áreas Legal y Marketing:**
    - El funnel de canciones se reparte en tres áreas: Legal se abre con la composición aprobada y Marketing con Música al 100 %.
    - Hay un pendiente por área.
    - Los pasos completados ya no saturan Pendientes.
    - En los lives, Grabación y Post se comparten con Audiovisual.
    - Archivos: `campos-cancion.js` (`AREA_PASO`, `AV_PASO_LIVE`), `index.html` y migración 022.
  - **Calendario de producción con reglas:** 3 semanas de producción al mes, bloques lun–mar y jue–vie, semana 4 de colchón, tipos acústica / full band / grande, horario 9–17, oración fija de los miércoles, cenáculos, viernes ocupados, días inhábiles y vista del día por horas (`agenda-reglas.js`, `index.html`).
  - **Enlace de agenda para artistas** `/agenda/<código>` y resumen de producción por mes (`agenda/index.html`, `.htaccess`, migración 022).
  - **Accesos por área:** el menú muestra solo tus áreas; las demás se piden y la PM las aprueba. Calendarios por área y Calendario completo para la PM (`index.html`, migración 022).
  - **Este manual** (`docs/MANUAL.md`).
- **2026-11-13**
  - **Lecturas del día:** completas, en carrusel.
  - **Canciones:** live, un solo autor, borrar con confirmación, Tiempo de Dios como ministerio, paso DistroKid (021).
  - **Tareas:** comentario final «¿Cómo quedó?».
  - **Samply:** liga pegada a mano.
  - **Formularios:** los abiertos ya no se borran con el tiempo real.
- **2026-11-12**
  - **Dashboard:** calendario interno (día, semana, mes, año) y saludo personalizado.
  - **Canciones:** canciones por producir con checklist, avance y pendiente encadenado; colaboraciones; tablero por ministerio; ligas limpias (020).
  - **Finanzas y Activos** (017, 019).
  - **Samply** (018).
  - **Perfil:** portada ajustable.
  - **Tareas:** ordenar arrastrando.
  - **Entradas de Formación** (012).
- **2026-11-11**
  - **Menú y apariencia:** menú lateral estilo tablero, modo día y noche.
  - **Correo:** avisos por correo (008, 010) y plantillas de correo.
  - **Perfiles y áreas:** carta de presentación (009), área Operativo y varias áreas (007).
  - **Sesión:** cierre tras 24 h sin actividad.
- **2026-11-05**
  - **Tareas:** entregables en tareas (006), fecha de realizado editable y responsables sin cuenta.
- **2026-11-03**
  - **Primera versión.**
  - **Perfiles y equipo:** perfiles con foto, @usuario, rol desarrollador, pestaña Equipo y Edge Function `equipo`.
  - **Despliegue** en Hostinger.
