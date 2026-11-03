# Bitácora Tiempo de Dios

Web app para registrar pendientes, avances diarios y logros de las áreas de **Formación**, **Música** y **Audiovisual**, con un panel para la **Project Manager** y reportes en PDF por semana, mes y año.

## Qué hay en esta carpeta

```
bitacora-tdd/
├── app/                      La web app que subes a tu subdominio
│   ├── index.html            Toda la interfaz (HTML, estilos y lógica)
│   └── config.example.js     Plantilla de configuración → cópiala como config.js
├── supabase/
│   └── schema.sql            Base de datos, roles y permisos
├── prototipo/
│   └── bitacora-prototipo-claude.html   Versión original hecha en Claude (referencia de diseño)
├── CLAUDE.md                 Contexto del proyecto para seguir trabajando en Claude Code
└── README.md
```

## Cómo funciona

- **Frontend:** una sola página estática (no necesita servidor propio ni compilar nada).
- **Base de datos, inicio de sesión y tiempo real:** [Supabase](https://supabase.com) (Postgres). El plan gratuito alcanza para un equipo de este tamaño.
- **Roles:**
  - `pm`: ve y edita todas las áreas y entra directo al panel de Project Manager.
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

### 4. Invitar al equipo
1. En Supabase, ve a **Authentication → Users → Invite user** y escribe el correo de cada persona.
2. Cada persona recibe un correo, toca el enlace y crea su contraseña en la app.
3. Asigna rol y área a cada persona en **SQL Editor**. Al final de `schema.sql` hay ejemplos listos para copiar.

## Seguridad
- La *anon key* puede ir en el navegador. Lo que protege los datos son las reglas de `schema.sql`: sin sesión no se ve nada, y cada quien solo escribe en su área.
- Nunca subas la *service_role key* a la app.

## Siguientes pasos sugeridos
Están detallados en `CLAUDE.md`. En resumen:
1. Que la PM pueda asignar tareas a una persona del equipo, y que cada quien vea una vista de **"Mis tareas"**.
2. Una pantalla para administrar al equipo (invitar, cambiar rol y área) sin entrar a Supabase.
3. Una opción para mover una tarea a otra área.
4. Pasar el `index.html` único a un proyecto con componentes (por ejemplo, Vite + React) cuando la app crezca.
