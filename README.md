# Bitácora Tiempo de Dios

Web app para registrar pendientes, avances diarios y logros de las áreas de **Formación**, **Música** y **Audiovisual**, con un panel para la **Project Manager** y reportes en PDF por semana, mes y año.

## Qué hay en esta carpeta

```
bitacora-tdd/
├── app/                      La web app que subes a tu subdominio
│   ├── index.html            Toda la interfaz (HTML, estilos y lógica)
│   └── config.example.js     Plantilla de configuración → cópiala como config.js
├── supabase/
│   ├── schema.sql            Base de datos, roles y permisos
│   └── functions/equipo/     Edge Function para invitar y quitar personas (solo PM)
├── prototipo/
│   └── bitacora-prototipo-claude.html   Versión original hecha en Claude (referencia de diseño)
├── CLAUDE.md                 Contexto del proyecto para seguir trabajando en Claude Code
└── README.md
```

## Cómo funciona

- **Frontend:** una sola página estática (no necesita servidor propio ni compilar nada).
- **Base de datos, inicio de sesión y tiempo real:** [Supabase](https://supabase.com) (Postgres). El plan gratuito alcanza para un equipo de este tamaño.
- **Roles:**
  - `pm` y `desarrollador`: ven y editan todas las áreas, administran el equipo y entran directo al panel de Project Manager.
  - `lider` y `colaborador`: ven todo y editan solo su área (y las áreas adicionales de `perfiles.areas`).
- Los cambios aparecen en vivo en todas las pantallas abiertas.

## Puesta en marcha (unos 20 minutos)

### 1. Crear la base de datos
1. Crea una cuenta y un proyecto nuevo en supabase.com (región: la más cercana, por ejemplo *us-east*).
2. Ve a **SQL Editor → New query**, pega todo el contenido de `supabase/schema.sql` y toca **Run**.
3. En **Authentication → Sign In / Providers**, desactiva *Allow new users to sign up*. Así solo entra quien tú invites.
4. En **Authentication → URL Configuration**, pon en **Site URL** tu subdominio, por ejemplo `https://bitacora.tiempodedios.mx`.

### 2. Configurar la app
Pon la **Project URL** y la **anon public key** en `app/config.publico.js` (Supabase → Project Settings → Data API y API Keys → Legacy). Este archivo sí se sube a GitHub: la anon key es pública por diseño. Nunca pongas ahí la *service_role key*.

### 3. Subirla a tu subdominio
Sube el contenido de la carpeta `app/` (`index.html` y `config.js`) a cualquier hosting de archivos estáticos:
- **Netlify** o **Vercel:** arrastra la carpeta `app/` y luego conecta el subdominio en *Domain settings*.
- **Tu hosting actual (cPanel o similar):** crea el subdominio y sube los dos archivos a su carpeta.

Para probar en tu computadora antes de subirla: `cd app && python3 -m http.server 8000` y abre http://localhost:8000. Para esta prueba, agrega `http://localhost:8000` en *Redirect URLs* de Supabase.

### 4. Invitar al equipo (desde la app)
La PM administra al equipo en **Project Manager → Equipo**: invita por correo, cambia nombre, rol y área, reenvía invitaciones y quita accesos.

Para que funcione, despliega una sola vez la Edge Function `equipo`:
1. En Supabase, ve a **Edge Functions → Deploy a new function → Via Editor**.
2. Nómbrala exactamente `equipo`.
3. Borra el código de ejemplo, pega todo `supabase/functions/equipo/index.ts` y toca **Deploy**.
4. En **Authentication → URL Configuration → Redirect URLs**, agrega la URL de la app (por ejemplo `https://pm.tiempodedios.mx`). Ahí regresa el enlace de la invitación.

La función usa la *service_role key* que Supabase le da por dentro; nunca sale al navegador. Solo responde a usuarios con rol `pm`.

La primera PM se asigna a mano en **SQL Editor** (al final de `schema.sql` hay ejemplos). Desde ahí, todo lo demás se hace en la app.

### 5. Fotos de perfil (proyectos creados antes de noviembre 2026)
Si tu base de datos se creó con una versión anterior de `schema.sql`, corre una vez `supabase/migraciones/002_perfil_y_fotos.sql` en **SQL Editor**. Crea el espacio para las fotos y deja que cada persona edite su nombre y foto (pero no su rol ni su área).

### 6. Rol de desarrollador (proyectos creados antes de noviembre 2026)
Corre `supabase/migraciones/003_rol_desarrollador.sql` en **SQL Editor** y vuelve a desplegar la función `equipo` (pega otra vez `supabase/functions/equipo/index.ts` y toca **Deploy**). El desarrollador tiene el mismo acceso que la PM, con su propia etiqueta.

### 7. Nombre de usuario (proyectos creados antes de noviembre 2026)
Corre `supabase/migraciones/004_usuario.sql` en **SQL Editor**. Separa el **nombre** (como te ve el equipo, "Diego Suárez") del **usuario** (identificador único, "@diegosuarez"). A quien no tenga usuario se le asigna el de su correo; cada quien lo cambia en su perfil.

### 8. Borrar fotos anteriores (opcional)
Corre `supabase/migraciones/005_fotos_lectura.sql`. Sin ella las fotos se suben igual, pero las anteriores se quedan guardadas.

### 9. Archivos entregables en las tareas
Corre `supabase/migraciones/006_entregables.sql` en **SQL Editor**. Crea el espacio privado `entregables` (hasta 25 MB por archivo). Solo quien inició sesión puede abrir los archivos; sube y borra quien edita esa área, o la PM.

### 10. Área Operativo y personas en varias áreas
Corre `supabase/migraciones/007_operativo_y_varias_areas.sql` en **SQL Editor** y vuelve a desplegar la función `equipo` (pega otra vez `supabase/functions/equipo/index.ts` y toca **Deploy**). Agrega el área **Operativo** y la columna `areas` (áreas adicionales). En la pestaña Equipo, la PM marca en **También en** dónde más participa cada persona.

### 11. Avisos por correo (vencimientos y resumen del sábado)
1. **Edge Functions → Deploy a new function**, nombre `avisos`; pega `supabase/functions/avisos/index.ts` y toca **Deploy**.
2. En **Edge Functions → Secrets** agrega `SMTP_USER` = `bitacora@tiempodedios.mx` y `SMTP_PASS` = la contraseña de ese buzón.
3. Corre `supabase/migraciones/008_avisos_por_correo.sql` en **SQL Editor**. Programa el envío diario a las 8:00 (centro de México).
4. Prueba desde la app: pestaña **Equipo** → **Enviarme una prueba** (te llegan ejemplos a tu correo).

En producción la función quedó con el nombre `bright-task`: la app (`FN_AVISOS`) y el cron (migración `010_avisos_nombre_funcion.sql`) la llaman así. Si algún día se despliega como `avisos`, cambia esos dos lugares.

Reglas: una actividad vence el viernes de su semana o en la fecha que se elija al abrir la tarea. Un día antes se le avisa a su responsable; si se atrasa, recibe un correo cada mañana hasta completarla; los sábados la PM recibe lo que quedó sin completar. Las personas sin cuenta no reciben correo.

### 12. Carta de presentación en el perfil
Corre `supabase/migraciones/009_presentacion.sql`. Agrega el campo **Sobre mí** (`bio`) que cada quien escribe en su perfil.

### 13. Cada quien edita solo su perfil
Corre `supabase/migraciones/011_perfil_propio.sql`. Nombre, usuario, foto y "Sobre mí" solo los cambia la persona dueña del perfil (ni la PM). La PM sigue cambiando rol, área y "También en" en la pestaña **Equipo**.

### 14. Entradas de formación (formulario público)
1. Corre `supabase/migraciones/012_entradas_formacion.sql`. Crea la tabla `entradas_formacion`, el bucket privado `entradas-formacion`, sus permisos y el tiempo real.
2. El formulario queda en `https://pm.tiempodedios.mx/entrada/` (carpeta `app/entrada/`). No pide sesión: cualquiera con la liga puede enviar, pero solo la PM y Formación pueden leer las respuestas.
3. Las respuestas llegan a **Formación → Entradas**. Las preguntas están en `app/campos-entrada.js`, que comparten el formulario y la Bitácora: para cambiar una pregunta, edítala solo ahí.

### 15. Calendario (Dashboard) y canciones por producir
1. Corre `supabase/migraciones/013_calendario_y_canciones.sql`. Crea las tablas `eventos`, `ligas_artistas` y `canciones`, el bucket privado `canciones` (hasta 50 MB por archivo) y la tarea automática.
2. **Dashboard** (`#dashboard`): calendario semanal con fechas únicas, de varios días o repetidas (cada semana, cada 2 semanas, cada mes, cada año), disponibilidad de producción de las próximas 12 semanas y pendientes de la semana. Todo el equipo puede agendar.
3. **Música → Canciones**: crea una liga personal por artista (`pm.tiempodedios.mx/cancion/?l=…`). Lo que registren llega a un tablero por etapas, con checklist de 14 pasos, notas internas y archivos.
4. Cada canción registrada crea una tarea en Música, "Agendar producción", para Ariel, con subtareas para Memo. Se buscan por usuario (`ariel`, `memo`) o por nombre que empiece así; si Memo no tiene cuenta, la subtarea queda con su nombre.

### 16. Portada en la carta de presentación
Corre `supabase/migraciones/014_portada.sql`. Agrega `perfiles.portada`: cada quien puede poner una imagen de portada en su perfil ("Poner portada"); si no pone ninguna, se usan los colores de sus áreas. Solo la persona dueña la cambia.

### 17. Ministerios, avance y pendiente de cada canción
1. Corre `supabase/migraciones/015_ministerios_y_lanzamiento.sql`. Agrega a `canciones` el ministerio y la fecha de lanzamiento, y permite agregar a mano canciones que ya están en proceso.
2. **Música → Canciones → Por ministerio:** un tablero por cada ministerio del colectivo (las ligas activas) con sus canciones activas, en producción y lanzadas, y el avance de 0 a 100 % de cada una.
3. **Checklist definitivo (22 pasos):** los 14 de producción y los 8 del pipeline de Marketing (D-42 a D+30). Las fechas de Marketing salen de la fecha de lanzamiento.
4. **Pendiente de cada canción:** siempre es su siguiente paso, asignado a quien le toca (Ariel, Memo o Marketing). Al completarlo, aquí o en Pendientes, se marca en el checklist, la etapa avanza sola y se crea el siguiente.

### 18. Saludo del Dashboard
Corre `supabase/migraciones/016_saludo.sql`. El Dashboard saluda «Bienvenido Diego, hijo de Dios» o «Bienvenida Ceci, hija de Dios». Cada quien lo confirma o cambia en su perfil («Cómo te saluda la Bitácora»); mientras no elija, se deduce del nombre.

### 19. Finanzas y documentos de registro de canciones
1. Corre `supabase/migraciones/017_finanzas.sql`. Crea las tablas `gastos` e `ingresos`, el bucket privado `finanzas`, la columna `perfiles.finanzas` y el permiso para que Música suba documentos de registro de canciones.
2. En **Equipo**, marca **💰 Finanzas** a Carla (y a quien se sume después). Solo ellas y el desarrollador aprueban, rechazan, pagan y registran ingresos; todo el equipo ve y cualquiera puede pedir un gasto.
3. **Finanzas → Solicitudes de gasto**: pedir, aprobar, rechazar y marcar «Pago realizado» (fecha, método, referencia y comprobante). **Ingresos y egresos**: registro mensual con balance, por categoría y CSV.
4. En Canciones, los pasos 12 (INDAUTOR/SACM) y 13 (splitsheet) solo se completan subiendo el documento.

### Correo para invitaciones
El correo integrado de Supabase solo manda unos 2 correos por hora. Para invitar a varias personas, configura un SMTP propio (por ejemplo, un buzón de Hostinger) en **Authentication → Emails → SMTP Settings** y sube el límite en **Authentication → Rate Limits**.

## Seguridad
- La *anon key* puede ir en el navegador. Lo que protege los datos son las reglas de `schema.sql`: sin sesión no se ve nada, y cada quien solo escribe en su área.
- Nunca subas la *service_role key* a la app.

## Siguientes pasos sugeridos
Están detallados en `CLAUDE.md`. En resumen:
1. Pasar el `index.html` único a un proyecto con componentes (por ejemplo, Vite + React) cuando la app crezca.
