# Estrategia de correo y WhatsApp · Comunidad de Tiempo de Dios

Para Operativo. Cómo invitamos, confirmamos y damos seguimiento a quienes vienen a los cenáculos y eventos. Todo sale de la Bitácora: **Operativo → Personas → Correos y WhatsApp**.

## 1. Objetivo

Que cada persona que se acerca a un cenáculo:

1. Vuelva.
2. Se sienta conocida, por su nombre y por su cumpleaños.
3. Con el tiempo, se sume a la misión, también como donador.

Escribimos poco y a tiempo, con un tono cercano y personal, sin presionar.

## 2. A quién le escribimos

| Grupo | Quiénes son | Qué reciben |
|---|---|---|
| **Comunidad** | Todos los que aceptan correos | Invitaciones a cenáculos y newsletter mensual |
| **Registrados** a una fecha | Se registraron a ese cenáculo o evento | Recordatorio por WhatsApp 2 días antes |
| **Primera vez** | Vinieron y siguen como «Sin contactar» | Mensaje personal de su responsable de 1 a 3 días después |
| **Interesados en donar** | Estado «Interesado en donar» | Conversación personal, nunca un correo masivo |
| **Donadores** | Tienen una donación recibida | Agradecimiento personal y el newsletter con lo que su apoyo hizo posible |

La app ya separa estos grupos. «Vinieron y nadie los ha contactado» e «Interesados en donar» aparecen en el **Resumen**.

## 3. Calendario de envíos por evento

| Cuándo | Canal | Qué | Automático |
|---|---|---|---|
| 15 días antes | Correo | Invitación con botón «Sí, quiero ir» | Sí, si el evento tiene «Invitar por correo» |
| 7 días antes | Correo | Segunda invitación | Sí (nadie recibe más de una invitación por semana) |
| 2 días antes | WhatsApp | Recordatorio con botones «Sí voy» y «No podré» | Sí, cuando WhatsApp esté conectado. Mientras, botón 💬 en el pase de lista |
| El día | En persona | Pase de lista y alta en la puerta | — |
| 1 a 3 días después | WhatsApp o llamada | Gracias y primer contacto con quien vino por primera vez | No: lo hace su responsable |
| Una vez al mes | Correo | Newsletter | Se manda desde la app |

**Cenáculos semanales:** si el cenáculo es cada martes, se activan las invitaciones solo en los que quieras promover, por ejemplo uno especial al mes. Si no, la comunidad recibiría un correo cada semana. La app ya limita a una invitación por persona cada 6 días.

## 4. Plantillas

Las invitaciones y el newsletter ya tienen diseño en la función `crm`: banda negra con franja Sol, logo y botón. `{nombre}` se cambia por el primer nombre de cada persona.

### 4.1 Invitación · 15 días antes (automática)

- **Asunto:** `Cenáculo: aparta el martes 2 de diciembre`
- **Cuerpo:**
  > Hola, {nombre}:
  >
  > Queremos invitarte al **Cenáculo**, el **martes 2 de diciembre a las 7:00 p. m.** en **Capilla Tiempo de Dios**.
  >
  > Será un tiempo para encontrarnos con Dios y en comunidad. Nos daría mucho gusto verte.
  >
  > Regístrate con un clic para apartar tu lugar:
  >
  > **[Sí, quiero ir]**

### 4.2 Invitación · 7 días antes (automática)

- **Asunto:** `{nombre}, te esperamos el martes 2 de diciembre: Cenáculo`
- **Cuerpo:** el mismo, con la frase de entrada «Ya casi es el Cenáculo…».

El botón lleva a la liga personal de cada quien, que registra con un clic sin volver a escribir sus datos.

### 4.3 Mensaje por WhatsApp a los inscritos · antes del cenáculo

Se manda desde **Operativo → Personas → Cenáculos → «💬 Enviar»**: abre WhatsApp con el mensaje y el nombre de cada quien, y queda marcado «✓ Enviado». Cuando la API esté conectada, sale solo 2 días antes con la plantilla `recordatorio_evento` (mismo texto, más botones «Sí voy» / «No podré»).

> ¡Hola, {nombre}! 🤍
>
> Te esperamos en nuestro cenáculo con Tiempo de Dios
>
> Este martes 24 de noviembre a las 8:00 p. m.
>
> Sembradora: Priscila Oceguera
> 📍 Villa Verona 7500, Int. F13
>
> ¿Nos confirmas si vienes?

La sembradora y el lugar se ponen al programar el cenáculo. «Este» cambia solo a «Hoy», «Mañana» o «El» según la fecha.

### 4.4 Gracias por venir · 1 a 3 días después (personal, por WhatsApp)

> Hola {nombre}, soy {tu nombre} de Tiempo de Dios. ¡Gracias por venir al cenáculo del martes! ¿Cómo te sentiste? Nos encantaría verte de nuevo.

Después, registra la conversación en su perfil y define la próxima acción.

### 4.5 Cumpleaños (personal, por WhatsApp)

> ¡Feliz cumpleaños, {nombre}! 🎂 Hoy damos gracias a Dios por tu vida. Un abrazo de toda la comunidad de Tiempo de Dios.

Los cumpleaños del día llegan en el resumen diario de Operativo y salen en el Resumen de la app.

### 4.6 Newsletter mensual

- **Asunto:** corto y concreto, por ejemplo `Lo que Dios hizo en noviembre 🙌`.
- **Estructura** (unas 250 palabras):
  1. **Saludo**: «Hola {nombre}:» y una frase del mes.
  2. **Lo que pasó**: 2 o 3 historias breves, por ejemplo cuántos vinieron a los cenáculos, un testimonio o una canción nueva.
  3. **Lo que viene**: fechas del mes, con la liga `pm.tiempodedios.mx/registro/cenaculo`.
  4. **Cómo sumarte**: oración, servicio o donación, en una sola frase sin presión.
  5. **Botón**: una sola acción, por ejemplo «Regístrate al cenáculo».
- **Antes de enviarlo:** «Enviarme prueba», revisarlo en el celular y luego «Enviar».

### 4.7 Agradecimiento a un donador (personal)

> {nombre}, gracias de corazón por tu donativo para {destino}. Gracias a personas como tú, {lo que hizo posible}. Te tenemos presente en nuestra oración.

- **Lo escribe su responsable,** no un correo masivo.
- **No incluyas** datos fiscales ni montos en mensajes de WhatsApp.
- **El comprobante fiscal,** si aplica, lo maneja Finanzas.

## 5. Buenas prácticas de envío

- **Hostinger por ahora.** Los correos salen de `bitacora@tiempodedios.mx` con el nombre «Tiempo de Dios».
  - La función manda como máximo `CRM_MAX_DIA` correos por día, 150 por omisión, y el newsletter en tandas de 40.
  - Revisa en Hostinger el límite diario de tu plan. Si la comunidad pasa de unas 300 personas, conviene mover el envío a Brevo o Resend: solo cambian los secretos SMTP de la función `crm`.
- **Dominio.** En Hostinger → Correo → Configuración de DNS, revisa que tiempodedios.mx tenga **SPF**, **DKIM** y **DMARC**. Sin eso, Gmail manda los correos a spam.
- **Horario.** La corrida diaria sale a las 9:00 de México. El newsletter, de martes a jueves entre 9 y 11.
- **Baja con un clic.** Cada correo trae «Ya no quiero recibir correos», y quien se da de baja ya no recibe invitaciones ni newsletter.
- **Lista limpia.** Si un correo rebota varias veces, corrígelo o quítalo en el perfil.

## 6. Privacidad

- **El formulario pide permiso** para mandar correos: la casilla viene marcada y dice que se pueden dar de baja. Explica que los datos se usan solo para los eventos y la comunidad.
- **Aviso de privacidad.** Recomendado: publicar uno en tiempodedios.mx y ligarlo desde el formulario, como pide la Ley Federal de Protección de Datos Personales.
- **Acceso a datos personales.** Solo Operativo, la PM y el desarrollador ven la base. Los montos de donaciones, solo Finanzas, la PM y el desarrollador.

## 7. Qué medir cada mes

En el Resumen y en el pase de lista:

| Indicador | Dónde |
|---|---|
| Registrados contra los que vinieron, por fecha | Pase de lista |
| Personas nuevas en el mes, por registro y en la puerta | Personas (columna Registro) |
| Primeras visitas con seguimiento en 3 días | Resumen: «Vinieron y nadie los ha contactado» debe quedar en cero |
| Personas que pasan a «Interesado» y a «Relación activa» | Personas, filtros por estado |
| Donaciones recibidas y comprometidas | Resumen (Finanzas y PM) |
| Bajas de correo | Correos y WhatsApp |
