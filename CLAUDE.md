# CLAUDE.md · Bitácora Tiempo de Dios

Contexto para Claude Code. Todo en español: interfaz, textos, commits y comentarios.

## Propósito
Plataforma sencilla para que las áreas de **Formación**, **Música** y **Audiovisual** de Tiempo de Dios registren su trabajo:
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
- `supabase/migraciones/`: cambios para proyectos ya creados (002: foto de perfil, cada quien edita su nombre/foto, trigger `proteger_rol`; 003: rol `desarrollador`).
- `supabase/functions/equipo/index.ts`: Edge Function (solo PM) con las acciones `listar`, `invitar`, `reenviar` y `quitar`. Usa la service_role key del entorno de Supabase. Nombre, rol y área se editan directo en `perfiles` (la RLS ya lo permite a la PM).
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
  `{area, titulo, proyecto, responsable, responsable_id, semana:"YYYY-MM-DD" (lunes), creada:ISO, creada_por, hecha:ISO|null, orden:number, subtareas:[{id, titulo, responsable, responsable_id, hecha:ISO|null}]}`
  - `responsable_id` es el uuid de `perfiles`; `responsable` guarda el nombre para reportes y PDF. Las tareas viejas solo traen nombre y se relacionan con perfiles por nombre (`personaDe`, `asignadoA`).
  - Al marcar la tarea padre se completan todas sus subtareas abiertas.
  - Al completar todas las subtareas, la tarea se marca sola.
- **Logro:**
  `{area, tipo, titulo, fecha:"YYYY-MM-DD", liga, responsable, nota, testimonios:[{id, texto, autor, creado}], creado}`
  - Todos los logros entran a los resúmenes del mes y del año.
- **Perfil:** `perfiles {id, nombre, rol, area, foto}`. La foto se sube recortada a 512 px a Storage `fotos/<id>/foto.jpg`.

### Tipos de logro por área (`AREAS` en index.html)
- **Formación:** Curso, Taller, Retiros / camps, Material creado
- **Música:** Canciones publicadas, Presentaciones en vivo, Eventos, Colaboraciones
- **Audiovisual:** Video en vivo, Podcast, Video musical, Reels, Videos de formación
- Siempre se puede agregar uno nuevo con "Otro…".

### Rutas (hash)
`#formacion`, `#musica`, `#audiovisual`, `#pm`, `#equipo` (directorio con fotos) y `#persona/<id>` (perfil con sus pendientes).
- Cada área tiene las pestañas Pendientes, Reporte diario, Mes y Logros.
- El panel de la PM tiene las pestañas Semana, Mes, Año, Tareas (asignar y editar en las tres áreas) y Equipo (administración). Tareas y Equipo solo las ve la PM.
- Al abrir una tarea (botón +) se editan título, proyecto y responsable; la PM además cambia área y semana.

### Roles (RLS)
- `pm` y `desarrollador`: leen y escriben todo y administran el equipo (`es_pm()` en SQL, `esPM()` y `ACCESO_TOTAL` en la app). Solo cambia la etiqueta: "Project Manager" o "Desarrollador web".
- `lider` y `colaborador`: leen todo y escriben solo filas de su `area`.
- La UI oculta los formularios cuando no hay permiso (`canEdit`).

## Identidad visual
- **Colores:**
  - Night `#1B1C1A`
  - White `#FFFFFF`
  - Flame `#FF3D1A` (Música, PM)
  - Baby blue `#98D5E0` (Audiovisual)
  - Deep sea green `#457A7F` (Formación)
- **Tipografía:** Archivo (display y texto, pesos 800–900, ligeramente expandida) e IBM Plex Mono (fechas y horas).
- **Encabezado:** banda Night con una franja inferior del color del área y una etiqueta pequeña del área sobre el título "La semana en orden".
- Soporta modo claro y oscuro mediante tokens CSS.

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
