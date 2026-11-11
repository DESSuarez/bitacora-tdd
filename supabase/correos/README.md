# Correos de la bitácora

Plantillas en español para Supabase → **Authentication → Emails → Templates**. Copia el contenido de cada archivo en **Message body** (pestaña Source) y usa estos asuntos:

| Plantilla en Supabase | Archivo | Asunto |
|---|---|---|
| Invite user | `invitacion.html` | Te invitaron a la Bitácora de Tiempo de Dios |
| Reset password | `recuperar.html` | Restablece tu contraseña · Bitácora Tiempo de Dios |

`{{ .ConfirmationURL }}` es la liga que genera Supabase: no la cambies. La app reconoce la invitación y la recuperación por esa liga y abre la pantalla para crear contraseña.

El logo se carga desde `https://pm.tiempodedios.mx/apple-touch-icon.png`.
