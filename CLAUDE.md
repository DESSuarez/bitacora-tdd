# CLAUDE.md · Bitácora Tiempo de Dios

Contexto para Claude Code. Todo en español: interfaz, textos, commits y comentarios.

## Propósito
Plataforma sencilla para que las áreas de **Formación**, **Música**, **Audiovisual** y **Operativo** de Tiempo de Dios registren su trabajo:
- Pendientes semanales con tareas y subtareas.
- La hora exacta en que se completa cada cosa.
- Logros con liga y testimonios.

La **Project Manager** ve todo, desde lo que se hizo cada día hasta lo que se logró en el mes y en el año. También descarga PDFs semanales, mensuales y anuales.

Dueña del proyecto: Ceci (líder de Formación).

## Arquitectura actual
- `app/index.html`: una sola página con HTML, CSS y JS sin framework ni build. Usa estas librerías desde CDN:
  - `@supabase/supabase-js@2.45.4` (UMD)
  - `jspdf@2.5.1` (UMD) para generar los PDF en el navegador
- `app/config.publico.js` (versionado): `window.BITACORA_CONFIG = {supabaseUrl, supabaseAnonKey}` con la anon key, que es pública por diseño. `app/config.js` (no versionado, opcional) lo reemplaza si existe.
- `supabase/schema.sql`: tablas `perfiles`, `tareas` y `logros`, con RLS, triggers, realtime y el bucket `fotos`.
- `supabase/migraciones/`: cambios para proyectos ya creados (002: foto de perfil, cada quien edita su nombre/foto, trigger `proteger_rol`; 003: rol `desarrollador`; 004: `usuario`; 005: lectura en el bucket `fotos` para borrar la foto anterior; 006: bucket privado `entregables`; 007: área `operativo`, columna `perfiles.areas` y función `puede_area()`; 008: tabla `avisos_enviados` y cron de avisos; 009: `perfiles.bio`; 010: el cron llama a `bright-task`; 011: cada quien edita solo su propio perfil (nombre, usuario, foto, bio; ni la PM) y las fotos solo en su carpeta; 012: tabla `entradas_formacion` y bucket privado `entradas-formacion`; 021: paso 15 «Subir canción a plataformas (DistroKid)» después del splitsheet (checklist de 24 pasos, `pasos_version = 3`, reacomoda canciones y pendientes); 020: `ligas_artistas.slug` (dirección fija `/cancion/<ministerio>`, la pone un trigger una sola vez y no se puede cambiar) y RPC `liga_resolver(l)` (por dirección o id); 019: tabla `activos` (tipo, nombre, valor, cantidad, área, responsable, ubicación, `fecha_valor`, `data` con detalle/estado/notas; ver todos, editar `puede_finanzas()`); 018: Samply: el paso 11 se divide en dos escuchas (checklist de 23 pasos; `canciones.pasos_version` y reacomodo de canciones, archivos y pendientes), tablas `samply_eventos` (avisos del webhook) y `samply_config` (solo service role); 017: Finanzas: tablas `gastos` (solicitudes: pendiente → aprobada/rechazada → pagada, `fecha_pago`, `data` con beneficiario, método, cuenta, archivos, pago e historial) e `ingresos`, bucket privado `finanzas` (`<uid>/<gasto>/…`), `perfiles.finanzas` y `puede_finanzas()` (finanzas o desarrollador); además, Música sube documentos a `canciones/equipo/<canción>/…`; 016: `perfiles.saludo` ('hijo'|'hija') para el saludo del Dashboard; 015: `canciones.ministerio` y `canciones.lanzamiento`, y el trigger solo crea "Agendar producción" para canciones que llegan por liga; 014: `perfiles.portada`, imagen de portada que solo cambia la persona dueña; 013: tablas `eventos`, `ligas_artistas` y `canciones`, bucket privado `canciones` y trigger `cancion_nueva` que crea la tarea "Agendar producción" para Ariel con subtareas para Memo).
- Fotos: cada subida usa un nombre nuevo (`fotos/<id>/<timestamp>.jpg`) **sin upsert**, porque sobrescribir en Storage exige además permiso de lectura.
- `supabase/functions/avisos/index.ts`: Edge Function de correos automáticos, **desplegada en Supabase como `bright-task`** (`FN_AVISOS` en la app; el cron la llama así desde la migración 010) (pg_cron diario 14:00 UTC, migración 008). Envía por SMTP de Hostinger (`npm:nodemailer`, secretos `SMTP_USER`/`SMTP_PASS`). El logo va incrustado como adjunto `cid:` porque los buzones bloquean imágenes externas. Avisa un día antes del vencimiento, cada día mientras esté atrasada y, los sábados, manda a la PM lo que quedó sin completar. Tabla `avisos_enviados` evita duplicados. `{prueba:true}` (solo PM/desarrollador) manda ejemplos al propio correo.
- `supabase/functions/samply/index.ts`: Edge Function `samply` (Verify JWT apagado; revisa la sesión ella misma y solo deja pasar a Música, PM y desarrollador). Guarda el token como secreto `SAMPLY_TOKEN`. Acciones: `proyectos`, `carpetas`, `cancion` (versiones, escuchas con % escuchado y comentarios de la carpeta), `liga` (crea un player) y `webhook` (registra el webhook; el secreto `whsec_` se guarda en `samply_config`). Los avisos firmados (Standard Webhooks) se guardan en `samply_eventos`. En la app, `panelSamply(c)` es un acceso directo compacto: al vincular se elige proyecto, carpeta y pista, y se crea una liga (player) solo con esa pista (`boxids`). Se guarda `data.samply = {projectid, proyecto, folderid, carpeta, boxid, pista, playerUrl}`; el tablero por ministerio muestra ▶ para abrirla. (La acción `cancion` de la función también trae escuchas y comentarios, aunque la app ya no los muestra.)
- `supabase/functions/equipo/index.ts`: Edge Function (solo PM) con las acciones `listar`, `invitar`, `reenviar` y `quitar`. Usa la service_role key del entorno de Supabase. Nombre, rol y área se editan directo en `perfiles` (la RLS ya lo permite a la PM).
- `app/entrada/index.html`: formulario público "Entrada nueva de formación" (sin sesión, liga `pm.tiempodedios.mx/entrada/`). Usa `../config.publico.js` y `../campos-entrada.js`. Sube los archivos a `entradas-formacion/<uuid>/<nn>-<nombre>` y luego inserta `{id, data, archivos}` (cada archivo: `{nombre, ruta, tamano, tipo, campo}`; `campo` = "archivosMateriales" o "archivos"). Tiene un campo oculto contra bots.
- `app/campos-entrada.js`: única fuente de las preguntas (`CAMPOS_ENTRADA`, con `si:{k,v}` para condicionales) y de los estados (`ESTADOS_ENTRADA`). Lo usan el formulario y la pestaña Entradas.
- `app/cancion/index.html`: formulario privado de canciones en `/cancion/<ministerio>` (regla en `.htaccess`; rutas absolutas a `/config.publico.js` y `/campos-cancion.js`) o la vieja `cancion/?l=<id>`. Valida la liga con la RPC `liga_resolver` (security definer), sube a `canciones/<liga>/<uuid>/<nn>-<nombre>` e inserta `{id, liga, data, archivos}`. `app/campos-cancion.js` tiene las preguntas (`CAMPOS_CANCION`), las etapas (`ETAPAS_CANCION`), el checklist de 14 pasos (`CHECKLIST_CANCION`) y los días de la semana de producción.
- `app/evangelio.php`: lee del lado del servidor las lecturas del día. Evangelio, primera y segunda lectura (los domingos vienen separadas por «Primera/Segunda lectura») de Vatican News (`/es/evangelio-de-hoy/AAAA/MM/DD.html`); el salmo responsorial, que Vatican News no publica, de dominicos.org con su respuesta (`respuesta`; las estrofas que terminan en «R/.» la repiten), y si no está (días futuros) del servicio de Evangelio del Día (`feed.evangelizo.org`, `content=PS`, sin respuesta y sin su pie). La respuesta se ve en negritas y en azul claro (`.evresp`); toda la letra de las lecturas es del mismo tamaño. Devuelve `{fecha, url, lecturas:[{tipo, nombre, titulo, cita, parrafos[]}]}` en orden Evangelio → Primera lectura → Salmo → Segunda lectura (más `titulo/cita/parrafos` del evangelio por compatibilidad) y guarda una copia por día (`tdd-lecturas-v3-<fecha>.json`). La app lo pide como `evangelio.php?v=<LECTURAS_V>&fecha=…` y lo guarda en localStorage (`bitacora-lecturas<LECTURAS_V>-<fecha>`): sube `LECTURAS_V` cuando cambie el PHP, porque el servidor guarda copias por dirección y lo muestra como carrusel con flechas, puntos y deslizar con el dedo (`evangelioHTML`, `lecturaIdx`); los textos largos se recortan con «Leer completo».
- Toda la app y sus formularios llevan `noindex` (meta y cabecera `X-Robots-Tag` en `.htaccess`); los formularios además `referrer: no-referrer` para no filtrar la liga.
- `.htaccess`: Hostinger clona el repo completo en `public_html/pm`; esto sirve solo `app/`.
- `prototipo/`: la versión original como artifact de Claude. Es la referencia visual: no se despliega.

### Capa de datos
La UI se escribió sobre una API de colecciones estilo Firestore: `col.doc(id).set(body)`, `col.doc(id).delete()` y `col.onSnapshot(next, fail)`.

`makeCol(table)` en `index.html` adapta esa API a Supabase:
- `upsert({id, area, data})` sobre una columna `data jsonb`.
- Una carga inicial con `select`.
- Una suscripción a `postgres_changes`.

Si se migra a columnas normalizadas, conviene mantener esa interfaz o reescribir la UI completa a la vez.

### Modelo (contenido de `data`)
- **Tarea:**
  `{area, titulo, proyecto, responsable, responsable_id, semana:"YYYY-MM-DD" (lunes), vence?:"YYYY-MM-DD" (si falta, viernes de su semana: `venceDe`), creada:ISO, creada_por, hecha:ISO|null, orden:number, nota, ligas:[{id, url, titulo, creada}], archivos:[{id, path, nombre, tipo, tam, subido:ISO, por, por_nombre}], subtareas:[{id, titulo, responsable, responsable_id, hecha:ISO|null, nota, ligas, archivos}]}`
  - **Entregables:** archivos en el bucket privado `entregables`, ruta `<área>/<id tarea>/<timestamp>-<nombre>` (máx. 25 MB). Se abren con `createSignedUrl` (1 h). Aparecen en el Reporte diario, en "Entregables subidos esta semana", en las tarjetas de la PM y en el PDF semanal (solo nombres).
  - `responsable_id` es el uuid de `perfiles`; `responsable` guarda el nombre para reportes y PDF. Las tareas viejas solo traen nombre y se relacionan con perfiles por nombre (`personaDe`, `asignadoA`).
  - Personas sin cuenta: `responsable_id` es null y solo se guarda el nombre. En las listas su valor es `txt:<nombre>` ("✎ Escribir otro nombre…").
  - La fecha y hora de `hecha` se puede corregir al abrir la tarea (campo "Hecha el"); no se aceptan fechas futuras.
  - Al marcar la tarea padre se completan todas sus subtareas abiertas.
  - Al completar todas las subtareas, la tarea se marca sola.
- **Logro:**
  `{area, tipo, titulo, fecha:"YYYY-MM-DD", liga, responsable, nota, testimonios:[{id, texto, autor, creado}], creado}`
  - Todos los logros entran a los resúmenes del mes y del año.
- **Perfil:** `perfiles {id, nombre, usuario, rol, area, areas[], foto, bio, portada}`. La portada se sube sin recortar (máx. 1800 px por lado) a `fotos/<id>/portada-<fecha>.jpg` (`subirPortada`) y se acomoda arrastrando hacia arriba o abajo ("↕ Ajustar", `ajustarPortada`); la posición vertical va en la misma URL como `#y=0…100` (`portadaY`); sin portada se usa el degradado de sus áreas. El perfil es una carta de presentación (`cartaPersona`): portada con el color de sus áreas, foto grande, rol, áreas, correo y "Sobre mí" (`bio`, máx. 600, migración 009). `areas` son áreas adicionales donde también participa (aparece en sus listas de responsables y puede editarlas; `enArea()` en la app, `puede_area()` en SQL). La PM las marca en Equipo → "También en". Diego (desarrollador) está en Música y Operativo. `nombre` es como se ve la persona; `usuario` es su identificador único en minúsculas (`^[a-z0-9._]{2,30}$`, índice único sin mayúsculas, lo propone `usuario_libre()` desde el correo). La foto se sube recortada a 512 px a Storage `fotos/<id>/foto.jpg`.

### Tipos de logro por área (`AREAS` en index.html)
- **Formación:** Curso, Taller, Retiros / camps, Material creado
- **Música:** Canciones publicadas, Presentaciones en vivo, Eventos, Colaboraciones
- **Audiovisual:** Video en vivo, Podcast, Video musical, Reels, Videos de formación
- **Operativo:** Eventos organizados, Logística, Procesos y administración, Apoyo a otras áreas
- Siempre se puede agregar uno nuevo con "Otro…".

### Rutas (hash)
`#finanzas` (pestañas Solicitudes de gasto, Ingresos y egresos y Activos (`vistaActivos`: total, líquido vs. bienes, por tipo y área, aviso de saldos con más de 45 días, CSV); todos ven, cualquiera pide, solo `puedeFin()` aprueba, paga y registra ingresos; un gasto pagado es egreso del mes de `fecha_pago`; CSV del mes; casilla 💰 Finanzas en Equipo), `#dashboard` (título «Bienvenido/a <primer nombre>, hijo/hija de Dios» con `saludoH1()`: usa `perfiles.saludo` y, si no hay, lo deduce del nombre con `saludoDe()`; lecturas del día arriba (Evangelio primero; flechas a Primera lectura, Salmo y Segunda lectura), con cita corta tipo «Lc 17, 20-25» (`citaCorta`); vistas Día, Semana (predeterminada), Mes y Año (`dashView`). **El calendario muestra solo eventos** (producciones, retiros, reuniones…), nunca los pendientes de las personas: esos viven en cada área y en Mi trabajo. Calendario con eventos repetidos, disponibilidad de producción de 12 semanas, con flechas para moverse a semanas futuras (`dispOff`); tabla `eventos` vía `makeCol`, `ocurrencias()` expande las repeticiones y `excepciones` quita un solo día), `#formacion`, `#musica`, `#audiovisual`, `#operativo`, `#pm`, `#equipo` (directorio con fotos) y `#persona/<id>` (perfil con sus pendientes).
- Cada área tiene las pestañas Pendientes, Reporte diario, Mes y Logros. Formación tiene además **Entradas** (solo PM y quien está en Formación, `puedeEntradas()`): respuestas del formulario público con filtros por estado (nueva, revisión, diseño, diseñado, descartada), detalle armado desde `campos-entrada.js`, estado y notas internas (`notas`), documentos con URL firmada de 1 h, PDF (`entradaPDF`) y tiempo real. No se redibuja mientras se escriben notas (`esperaRender`). Solo la PM ve el botón de borrar.
- Música tiene además **Canciones** (solo PM y quien está en Música, `puedeMusica()`): ligas por artista, tablero por etapas (intake → completado, más bloqueado), detalle con etapa, notas, checklist de 14 pasos y archivos (bucket `canciones`). Agendar su semana crea un evento de tipo producción (lunes a viernes) ligado con `cancion_id`, guarda `semana`, marca el paso 5 y la pasa a "Agendada". La tarea automática trae `cancion_id` y muestra "🎵 Ver canción".
- **Canciones, avance y pendientes:** `CHECKLIST_CANCION` (24 pasos: 16 de producción y registro, con las dos escuchas del master en Samply y «Subir canción a plataformas (DistroKid)» después del splitsheet, + 8 de Marketing D-Day con días respecto al lanzamiento) es el checklist definitivo; el avance (`avance()`) va de 0 a 100 %. Cada canción tiene un solo pendiente abierto: su siguiente paso (`crearPendiente`, id de tarea `cancion-<id>-p<n>`, con `cancion_id` y `paso`), asignado según el responsable del paso (`personaPorNombre`; "Marketing" queda como nombre libre). Completar la tarea (`toggleTask`/`toggleSub` → `pasoDeTarea`) o el paso en el detalle marca el checklist, avanza la etapa con `ETAPA_POR_PASO` y crea el siguiente pendiente. «Tiempo de Dios» (`MIN_TDD`) es un ministerio fijo para canciones de todo el colectivo: va primero en la lista, su tarjeta va primero en «Por ministerio» y no se ofrece como colaborador. Colaboraciones: `data.colaboran` (lista de ministerios) además del ministerio principal; `ministeriosDe(c)`/`creditoDe(c)` («A × B»). La vista "Por ministerio" pone cada canción en el tablero de su ministerio y de cada colaborador, agrupando por `canciones.ministerio` (o el nombre de la liga) e incluye las ligas activas sin canciones. Pasos con documento obligatorio (5.º elemento de `CHECKLIST_CANCION`: 13 INDAUTOR/SACM y 14 splitsheet): no se completan, ni en el detalle ni en Pendientes, sin subir el archivo (`pedirDocPaso`, se guarda en `archivos` con `campo:"paso<n>"`). La barra de avance es de un solo color según el porcentaje, del naranja #FF3D1A (0 %) al verde Spotify #1DB954 (100 %) (`colorAvance`). "✎ Editar datos" en el detalle edita las respuestas con las mismas preguntas de `campos-cancion.js` (`formEditarCancion`; los archivos no se editan; no se redibuja mientras se edita). La vista "Por etapa" acomoda las 8 etapas en filas (sin desplazamiento lateral). "+ Agregar canción" da de alta canciones en proceso (marca los pasos hasta el elegido). La fecha de lanzamiento crea el evento `lanz-<id>` (tipo lanzamiento) en el calendario.
- Perfiles: cada quien edita solo el suyo (nombre, @usuario, foto, bio); la PM administra rol, área y "También en" en Equipo.
- El panel de la PM tiene las pestañas Semana, Mes, Año, Tareas (asignar y editar en las tres áreas) y Equipo (administración). Tareas y Equipo solo las ve la PM.
- Al abrir una tarea (botón +) se editan título, proyecto, responsable y semana (incluye "A la próxima semana →"); solo la PM cambia el área.
- En Pendientes y en Tareas de la PM, las completadas bajan al final bajo "Completadas · N" (`listaTareas`).
- Las tareas pendientes se ordenan arrastrando el asa ⋮⋮ (mouse, dedo o flechas del teclado; `reordenar`, pointer events). El orden (`orden`) es el mismo para todo el equipo dentro de cada área y semana; solo se guardan las tareas que cambiaron de lugar.
- En Tareas, la PM puede elegir "Todas las áreas" (crea una tarea por área) y agregar una liga común (Drive, Sheets…).
- El perfil (`#persona/<id>`) muestra "Asignado por la Project Manager": tareas del mes creadas por `pm`/`desarrollador` (`creada_por`), con % de avance, atrasadas y avance por área (`resumenPM`).
- Las ligas también cuentan como entregables en los reportes y en el PDF semanal (con su URL).
- Íconos: `app/favicon.png`, `app/apple-touch-icon.png` e `app/icono-512.png` (logo de Tiempo de Dios sin ©).

### Roles (RLS)
- `pm` y `desarrollador`: leen y escriben todo y administran el equipo (`es_pm()` en SQL, `esPM()` y `ACCESO_TOTAL` en la app). Solo cambia la etiqueta: "Project Manager" o "Desarrollador web".
- `lider` y `colaborador`: leen todo y escriben solo filas de su `area` o de sus `areas` adicionales.
- La UI oculta los formularios cuando no hay permiso (`canEdit`).
- **Sesión:** se cierra sola tras 24 h sin actividad en ese navegador (`bitacora-actividad` en localStorage, `INACTIVO_MS`); al volver muestra el motivo en el login.

## Identidad visual
- **Colores:**
  - Night `#1B1C1A`
  - White `#FFFFFF`
  - Flame `#FF3D1A` (Música, PM)
  - Baby blue `#98D5E0` (Audiovisual)
  - Deep sea green `#457A7F` (Formación)
  - Sol `#F2B33D` (Operativo; propuesta, no viene del manual de marca)
- **Tipografía:** Archivo (display y texto, pesos 800–900, ligeramente expandida) e IBM Plex Mono (fechas y horas).
- **Encabezado:** banda Night con una franja inferior del color del área y una etiqueta pequeña del área sobre el título "La semana en orden".
- **Navegación:** menú lateral izquierdo estilo tablero (Mi trabajo, Áreas con pendientes por área, General: Equipo y Project Manager; abajo el botón Día/Noche y la cuenta). Sigue el tema claro/oscuro. En pantallas de 900 px o menos se abre como cajón con el botón ☰ (`menuLateral`). En computadora se puede ocultar como en Arc (botón arriba del menú o ⌘\ / Ctrl+\): queda fuera de vista y se asoma flotando al llevar el mouse a la orilla izquierda (`ocultarLateral`, `bitacora-lateral` en localStorage, `data-lateral="oculta"` en `<html>`). Las pestañas de cada vista siguen arriba, en la banda.
- Modo **Día / Noche / Auto**: botón de sol/luna junto a la cuenta y selector "Apariencia" en el menú. Se guarda por navegador (`bitacora-tema` en localStorage) y se aplica en `<head>` antes de pintar (`data-theme` en `<html>`).
- Paleta por persona: en Project Manager, Equipo y el propio perfil, la app toma el color del área de quien inició sesión (`miArea()`: su `area`, o la primera de `areas`, o Flame). Cada área conserva su color en su propia página; el perfil de otra persona usa el área de esa persona.

## Pendientes de configuración (fuera del código)
- **Correo SMTP propio en Supabase** (noviembre 2026): el correo integrado de Supabase solo manda ~2 correos por hora y frenó las invitaciones ("email rate limit exceeded"). Plan: buzón `bitacora@tiempodedios.mx` en Hostinger → Supabase → Authentication → Emails → SMTP Settings (`smtp.hostinger.com`, puerto 465) y subir Rate Limits de correos a ~30/hora. Plantillas en español listas en `supabase/correos/` (invitación y recuperar contraseña). Mientras tanto, crear usuarios en Authentication → Users → Add user (Auto Confirm) y asignar rol y área en la pestaña Equipo.

## Roadmap acordado / sugerido
1. ✅ **Asignación de tareas** (hecho: `responsable_id`, pestaña Tareas de la PM, perfil con "Mis pendientes"). Pendiente:
   - Opcional: notificación por correo al asignar.
2. ~~**Administración del equipo**~~ ✅ Hecho: pestaña Equipo + Edge Function `equipo`.
3. ✅ **Mover tareas entre áreas** (la PM cambia el área al editar la tarea).
4. **Historial:** guardar quién completó cada cosa (`completada_por`).
5. **Normalizar datos** cuando haya volumen: tablas `subtareas` y `testimonios`, índices por `semana` y `fecha`. Hoy la carga inicial trae todo (límite de 10 000 filas).
6. Migrar a **Vite + React** (o similar) si el `index.html` se vuelve difícil de mantener. Conservar el diseño del prototipo.
7. **PWA** para usarla como app en el celular.

## Cómo probar
- `cd app && python3 -m http.server 8000`, con `config.js` apuntando a un proyecto de Supabase de prueba.
- Crea usuarios de prueba con distintos roles y verifica que un colaborador de Música no pueda escribir en Formación.

## Despliegue
- Producción: https://pm.tiempodedios.mx (Hostinger, carpeta `public_html/pm`).
- Repo: github.com/DESSuarez/bitacora-tdd, rama `main`. Hostinger está conectado por su integración con GitHub: cada push a `main` se despliega.
- La configuración va en `app/config.publico.js` (versionado). El `config.js` del servidor es opcional y ya no hace falta.
- La Edge Function `equipo` se despliega aparte, en Supabase (ver README).
