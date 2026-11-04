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
  - `lider` y `colaborador`: ven todo y editan solo su área.
- Los cambios aparecen en vivo en todas las pantallas abiertas.

## Puesta en marcha (unos 20 minutos)

### 1. Crear la base de datos
1. Crea una cuenta y un proyecto nuevo en supabase.com (región: la más cercana, por ejemplo *us-east*).
2. Ve a **SQL Editor → New query**, pega todo el contenido de `supabase/schema.sql` y toca **Run**.
3. En **Authentication → Sign In / Providers**, desactiva *Allow new users to sign up*. Así solo entra quien tú invites.
4. En **Authentication → URL Configuration**, pon en **Site URL** tu subdominio, por ejemplo `https://bitacora.tiempodedios.mx`.

### 2. Configurar la app
1. Copia `app/config.example.js` como `app/config.js`.
2. Pega ahí la **Project URL** y la **anon public key**. Están en Supabase → Project Settings → API.

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

## Seguridad
- La *anon key* puede ir en el navegador. Lo que protege los datos son las reglas de `schema.sql`: sin sesión no se ve nada, y cada quien solo escribe en su área.
- Nunca subas la *service_role key* a la app.

## Siguientes pasos sugeridos
Están detallados en `CLAUDE.md`. En resumen:
1. Pasar el `index.html` único a un proyecto con componentes (por ejemplo, Vite + React) cuando la app crezca.
