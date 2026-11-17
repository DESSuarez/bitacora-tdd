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
| Funciones del servidor | Supabase Edge Functions (Deno): `equipo`, `bright-task` (avisos por correo) y `samply` |
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
  evangelio.php         Lecturas del día (Vatican News + salmo de dominicos.org)
supabase/
  schema.sql            Esquema base (proyectos nuevos)
  migraciones/NNN_*.sql Cambios para el proyecto que ya existe (se corren en orden)
  functions/            Edge Functions (equipo, avisos → «bright-task», samply)
  correos/              Plantillas de correo en español
docs/MANUAL.md          Este manual
.htaccess               Reescrituras: /cancion/<slug>, /agenda/<código> y todo lo demás → app/
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
| **024** | `agenda_reservar` guarda los días exactos (`dias`) de lo que aparta un artista |
| **023** | Liga fija de agenda por ministerio (`reutilizable`, `reservas`; códigos con guiones) |
| **022** | Áreas Legal y Marketing, permisos de canciones para Legal, Marketing y Audiovisual, pendientes del funnel por área, `agendas_artistas` y sus funciones públicas, `solicitudes_area` |

## 11. Seguridad

- La anon key es pública. Lo que protege es la RLS.
- La service_role key y los tokens (Samply, SMTP) viven solo en Supabase.
- Los formularios públicos (entrada, canción, agenda) usan funciones `security definer` que devuelven lo mínimo. Además llevan `noindex` y `no-referrer`.
- Un token que se haya compartido por chat o correo se **rota**.

## 12. Pendientes conocidos

- **Correo SMTP propio** en Supabase para las invitaciones (ver `CLAUDE.md`).
- **Restringir también la lectura** por área en la RLS de `tareas` y `logros`, si se quiere que el límite de acceso sea más que de interfaz.
- **Avisar por correo** al equipo de Música cuando un artista aparte fechas desde su enlace.
- **Normalizar datos** y **migrar a Vite + React** cuando el `index.html` crezca más (roadmap en `CLAUDE.md`).

## 13. Bitácora de cambios

Formato: fecha · qué cambió · dónde.

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
