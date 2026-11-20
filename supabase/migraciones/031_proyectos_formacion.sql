-- Bitácora Tiempo de Dios · migración 031: Formación → Proyectos (planeación en 6 pasos)
-- Viene del paquete «modulo-proyectos-tdd» (03-proyectos.sql + 04-datos-iniciales-proyectos.sql), adaptado:
-- · Permisos con puede_area(area): la PM, el desarrollador y quien está en el área (también como área adicional).
-- · Los datos del piloto (Eleva tu música, Plataforma de formación, Cursos masivos de formación y el equipo
--   guardado «Equipo base») se cargan solo si no existen: volver a correrla no borra cambios.
-- Ejecútala una vez en Supabase → SQL Editor → Run. Se puede volver a correr sin error.


create table if not exists public.proyectos (
  id text primary key,
  area text not null default 'formacion' check (area in ('formacion','musica','audiovisual','operativo','legal','marketing')),
  data jsonb not null check (pg_column_size(data) < 900000),
  actualizado timestamptz not null default now(),
  actualizado_por uuid default auth.uid()
);

alter table public.proyectos drop constraint if exists proyectos_area_check;
alter table public.proyectos add constraint proyectos_area_check check (area in ('formacion','musica','audiovisual','operativo','legal','marketing'));
drop trigger if exists proyectos_actualizado on public.proyectos;
create trigger proyectos_actualizado before update on public.proyectos
for each row execute function public.marcar_actualizado();

alter table public.proyectos enable row level security;

-- Todos con sesión los ven; editan la PM y el equipo del área del proyecto
drop policy if exists proyectos_leer on public.proyectos;
create policy proyectos_leer on public.proyectos for select to authenticated using (true);
drop policy if exists proyectos_escribir on public.proyectos;
create policy proyectos_escribir on public.proyectos for all to authenticated
  using (public.puede_area(area))
  with check (public.puede_area(area));

do $$ begin
  alter publication supabase_realtime add table public.proyectos;
exception when duplicate_object then null; end $$;

-- ============ Equipos guardados ============
-- Equipos que se reutilizan entre proyectos (Charter → Equipos guardados).
create table if not exists public.equipos (
  id text primary key,
  area text not null default 'formacion' check (area in ('formacion','musica','audiovisual','operativo','legal','marketing')),
  data jsonb not null,
  actualizado timestamptz not null default now(),
  actualizado_por uuid default auth.uid()
);
alter table public.equipos drop constraint if exists equipos_area_check;
alter table public.equipos add constraint equipos_area_check check (area in ('formacion','musica','audiovisual','operativo','legal','marketing'));
drop trigger if exists equipos_actualizado on public.equipos;
create trigger equipos_actualizado before update on public.equipos
for each row execute function public.marcar_actualizado();
alter table public.equipos enable row level security;
drop policy if exists equipos_leer on public.equipos;
create policy equipos_leer on public.equipos for select to authenticated using (true);
drop policy if exists equipos_escribir on public.equipos;
create policy equipos_escribir on public.equipos for all to authenticated
  using (public.puede_area(area))
  with check (public.puede_area(area));
do $$ begin
  alter publication supabase_realtime add table public.equipos;
exception when duplicate_object then null; end $$;

-- ============ Eventos de los proyectos (para el calendario) ============
-- Cada proyecto marcado como evento en su Project Charter aparece aquí como una fila.
-- El calendario de la Bitácora puede leer esta vista directamente.
create or replace view public.eventos_proyectos with (security_invoker = true) as
select
  p.id                                         as proyecto_id,
  p.area,
  p.data->>'nombre'                            as titulo,
  (p.data->'charter'->>'eventoInicio')::date   as inicio,
  coalesce(nullif(p.data->'charter'->>'eventoFin','')::date,
           (p.data->'charter'->>'eventoInicio')::date) as fin,
  nullif(p.data->'charter'->>'eventoLugar','')   as lugar,
  nullif(p.data->'charter'->>'eventoHorario','') as horario,
  p.actualizado
from public.proyectos p
where (p.data->'charter'->>'esEvento')::boolean is true
  and nullif(p.data->'charter'->>'eventoInicio','') is not null;

grant select on public.eventos_proyectos to authenticated;

-- ============ Datos del piloto ============
insert into public.proyectos (id, area, data) values
('cursos-masivos-de-formacion', 'formacion', $tdd${"area": "formacion", "charter": {}, "cierre": {"objetivos": {}}, "creado": "2026-11-19T22:00:02.000Z", "equipo": [], "indicadores": [], "items": [], "nombre": "Cursos masivos de formación"}$tdd$::jsonb),
('eleva-tu-musica', 'formacion', $tdd${"actualizado": "2026-11-20T16:39:23.000Z", "area": "formacion", "charter": {"beneficiarios": "A los músicos o ministerios de música con un proyecto de evangelización que están en proceso de profesionalización. ", "entregablesClave": "Campamento de 1 fin de semana jueves a domingo", "esEvento": true, "eventoFin": "2027-10-17", "eventoHorario": "jueves 2 pm a domingo 3 pm", "eventoInicio": "2027-10-08", "eventoLugar": "Tapalpa, Guadalajara", "excluye": "1. Transporte del aeropuerto al punto de reunión. \n2. Vuelos o traslados para llegar a la sede. \n3. Hospedaje del domingo. ", "exito": "Si llenamos el cupo del campamento, con el nivel de satisfacción de los ministerios que asistan, si salen o no prospectos para el colectivo de Tiempo de Dios. ", "fin": "2027-10-29", "guardado": "2026-11-20T15:52:46.428Z", "incluye": "1. Hospedaje\n2. Alimentación\n3. Transporte \n4. Instrumentos y equipo de audio\n5. Materiales\n6. Actividades creativas\n7. Mentorías\n", "inicio": "2027-01-11", "lider": "Ceci Gómez", "listo": true, "objetivo": "Ser un campamento experiencial, en el que músicos o ministerios de música con proyectos de evangelización puedan continuar su profesionalización y hacer comunidad entre ellos. ", "objetivosEsp": "1. Crear comunidad entre músicos que están en un camino de profesionalización. \n2. Encontrar ministerios de música que puedan empezar un proceso de acompañamiento para discernir si podrían formar parte del colectivo. ", "patrocinador": "", "presupuesto": "", "proposito": "El ETM existe como un semillero para hacer comunidad con posibles músicos o ministerio de evangelización que puedan participar en el colectivo de Tiempo de Dios, es decir, que puedan comenzar el proceso de discernimiento y empezar a formarse para eventualmente poder producir música y videos y colaborar con Tiempo de Dios. ", "riesgos": "Que los ministerios de música no puedan asistir ese fin de semana, que los costos sean demasiado altos. ", "supuestos": "Que va a haber ministerios de música interesados en asistir. "}, "cierre": {"cerrado": false, "objetivos": {}}, "creado": "2026-11-19T22:00:00.000Z", "equipo": [{"id": "fmohus2f0tcl", "nombre": "Ceci Gómez", "rol": "Project Manager"}, {"id": "gc3d9ivv1hlq", "nombre": "Rosy Ruesga", "rol": "Seguimiento músicos", "roles": ["Seguimiento músicos"]}, {"id": "4onj0g1p1x7a", "nombre": "Diego Suárez", "rol": "Desarrollador web, Formador", "roles": ["Desarrollador web", "Formador"]}, {"id": "6hat8jti60jw", "nombre": "Memo Reyes", "rol": "Formador", "roles": ["Formador"]}, {"id": "ejfua4wd6pgm", "nombre": "Ale Suárez", "rol": "Formadora, Diseñadora instruccional", "roles": ["Formadora", "Diseñadora instruccional"]}, {"id": "sz0bhb8e6xb1", "nombre": "Ariel González", "rol": "Formador", "roles": ["Formador"]}, {"id": "qm4901l38a2m", "nombre": "Willy Gálvez", "rol": "Coordinador audiovisual", "roles": ["Coordinador audiovisual"]}, {"id": "zgjqu0xn8icc", "nombre": "Karla Flores", "rol": "Formadora, Seguimiento formadores", "roles": ["Formadora", "Seguimiento formadores"]}, {"id": "dpibwu7h2cgq", "nombre": "Ricardo Bañuelos", "rol": "Finanzas", "roles": ["Finanzas"]}], "indicadores": [{"actual": 3, "id": "a16uklierhd5", "meta": "", "nombre": "", "unidad": ""}, {"actual": "", "id": "tdm51r3aeiiz", "meta": "", "nombre": "", "unidad": ""}], "items": [{"estado": "pendiente", "id": "wblr926o8cy8", "nombre": "Definición del evento", "parent": null, "raci": {}}, {"estado": "pendiente", "fin": "2027-01-22", "hito": false, "id": "tu0xemu1oi2a", "ini": "2027-01-11", "nombre": "Confirmar fecha exacta y sede del Eleva", "parent": "wblr926o8cy8", "raci": {}}, {"estado": "pendiente", "fin": "2027-01-22", "hito": false, "id": "wn10740ypbrm", "ini": "2027-01-11", "nombre": "Definir cupo y perfil de los asistentes", "parent": "wblr926o8cy8", "raci": {}}, {"estado": "pendiente", "id": "0yoxk0tfouvd", "nombre": "Diseño de la experiencia ETM", "parent": null, "raci": {}}, {"estado": "pendiente", "fin": "2027-02-05", "hito": false, "id": "q9dk5d7jp0np", "ini": "2027-01-25", "nombre": "Diagnóstico de necesidades formativas y experienciales", "parent": "0yoxk0tfouvd", "raci": {"4onj0g1p1x7a": "I", "ejfua4wd6pgm": "R", "fmohus2f0tcl": "A", "gc3d9ivv1hlq": "R"}}, {"estado": "pendiente", "fin": "2027-02-19", "hito": false, "id": "xfguuh7cp42u", "ini": "2027-02-08", "nombre": "Diseño propuesta de actividades", "parent": "0yoxk0tfouvd", "raci": {"ejfua4wd6pgm": "R", "fmohus2f0tcl": "R"}}, {"estado": "pendiente", "fin": "2027-03-05", "hito": false, "id": "hy3nefpgp736", "ini": "2027-02-22", "nombre": "Propuesta de itinerario", "parent": "0yoxk0tfouvd", "raci": {"fmohus2f0tcl": "R"}}, {"estado": "pendiente", "id": "p71gezjv9eyz", "nombre": "Formadores y mentorías", "parent": null, "raci": {}}, {"estado": "pendiente", "fin": "2027-02-19", "hito": false, "id": "5hg9zxdtb9jc", "ini": "2027-02-08", "nombre": "Contactar formadores", "parent": "p71gezjv9eyz", "raci": {}}, {"estado": "pendiente", "fin": "2027-05-14", "hito": false, "id": "3cgx4czcc63i", "ini": "2027-04-19", "nombre": "Guiones instruccionales o planeaciones de temas", "parent": "p71gezjv9eyz", "raci": {}}, {"estado": "pendiente", "fin": "2027-06-25", "hito": false, "id": "u0dy27zaaamx", "ini": "2027-05-31", "nombre": "Diseño de material formativo para las mentorías y master classes", "parent": "p71gezjv9eyz", "raci": {}}, {"estado": "pendiente", "id": "4g00hra5dcip", "nombre": "Convocatoria y selección de ministerios", "parent": null, "raci": {}}, {"estado": "pendiente", "fin": "2027-03-05", "hito": false, "id": "9k3v22ixe9ta", "ini": "2027-02-22", "nombre": "Definir criterios de elección de ministerios", "parent": "4g00hra5dcip", "raci": {}}, {"estado": "pendiente", "fin": "2027-03-19", "hito": false, "id": "lbspb91pehf9", "ini": "2027-03-08", "nombre": "Definir comité de selección de ministerios", "parent": "4g00hra5dcip", "raci": {}}, {"estado": "pendiente", "fin": "2027-04-02", "hito": false, "id": "ve3cbl2yesih", "ini": "2027-03-22", "nombre": "Evaluar si es necesario un curso de estandarización en la plataforma", "parent": "4g00hra5dcip", "raci": {}}, {"estado": "pendiente", "fin": "2027-04-16", "hito": false, "id": "9qjasfnefnzb", "ini": "2027-04-05", "nombre": "Crear espacio en la plataforma para la aplicación de ministerios", "parent": "4g00hra5dcip", "raci": {}}, {"estado": "pendiente", "fin": "2027-04-30", "hito": false, "id": "jzzn1zmxfwmf", "ini": "2027-04-19", "nombre": "Definir periodo para aplicar", "parent": "4g00hra5dcip", "raci": {}}, {"estado": "pendiente", "fin": "2027-05-17", "hito": true, "id": "rx0pb8fei25t", "ini": "2027-05-17", "nombre": "Abrir convocatoria", "parent": "4g00hra5dcip", "raci": {}}, {"estado": "pendiente", "fin": "2027-07-02", "hito": true, "id": "9w3xbputg939", "ini": "2027-07-02", "nombre": "Cerrar aplicaciones", "parent": "4g00hra5dcip", "raci": {}}, {"estado": "pendiente", "fin": "2027-07-23", "hito": false, "id": "2wi8khjsgcm0", "ini": "2027-07-12", "nombre": "Evaluar aplicaciones", "parent": "4g00hra5dcip", "raci": {}}, {"estado": "pendiente", "id": "75bjopy8o9q0", "nombre": "Campaña de difusión", "parent": null, "raci": {}}, {"estado": "pendiente", "fin": "2027-03-19", "hito": false, "id": "a1zn5qjsbzqt", "ini": "2027-03-08", "nombre": "Objetivos específicos de comunicación", "parent": "75bjopy8o9q0", "raci": {"fmohus2f0tcl": "A", "gc3d9ivv1hlq": "R"}}, {"estado": "pendiente", "fin": "2027-04-02", "hito": false, "id": "mkz4yvzmc7b5", "ini": "2027-03-22", "nombre": "Planeación de contenido", "parent": "75bjopy8o9q0", "raci": {"ejfua4wd6pgm": "R", "fmohus2f0tcl": "A", "qm4901l38a2m": "R"}}, {"estado": "pendiente", "fin": "2027-04-16", "hito": false, "id": "pft910cecgzw", "ini": "2027-04-05", "nombre": "Programar grabación de contenido", "parent": "75bjopy8o9q0", "raci": {"qm4901l38a2m": "R"}}, {"estado": "pendiente", "fin": "2027-04-30", "hito": false, "id": "4i8r6jizyu9w", "ini": "2027-04-19", "nombre": "Grabar contenido", "parent": "75bjopy8o9q0", "raci": {}}, {"estado": "pendiente", "fin": "2027-05-14", "hito": false, "id": "8inunddvcnwp", "ini": "2027-05-03", "nombre": "Editar y entregar contenido", "parent": "75bjopy8o9q0", "raci": {"fmohus2f0tcl": "A", "qm4901l38a2m": "R"}}, {"estado": "pendiente", "fin": "2027-05-14", "hito": false, "id": "c6320ji1czo5", "ini": "2027-05-03", "nombre": "Calendarización de publicaciones y pauta", "parent": "75bjopy8o9q0", "raci": {"qm4901l38a2m": "I", "sz0bhb8e6xb1": "R"}}, {"estado": "pendiente", "fin": "2027-05-17", "hito": true, "id": "ht6rmfytutpf", "ini": "2027-05-17", "nombre": "Lanzamiento de la campaña", "parent": "75bjopy8o9q0", "raci": {}}, {"estado": "pendiente", "id": "3xmucac1brvr", "nombre": "Logística y operación", "parent": null, "raci": {}}, {"estado": "pendiente", "fin": "2027-06-11", "hito": false, "id": "e4lnqp1loq48", "ini": "2027-05-31", "nombre": "Hacer lista de necesidades operativas y logísticas", "parent": "3xmucac1brvr", "raci": {}}, {"estado": "pendiente", "fin": "2027-06-25", "hito": false, "id": "wuuq0226p6c0", "ini": "2027-06-14", "nombre": "Crear sheet con las necesidades operativas", "parent": "3xmucac1brvr", "raci": {}}, {"estado": "pendiente", "fin": "2027-08-06", "hito": false, "id": "ycpeohgxkslu", "ini": "2027-07-26", "nombre": "Reservar hospedaje y alimentación", "parent": "3xmucac1brvr", "raci": {}}, {"estado": "pendiente", "fin": "2027-08-27", "hito": false, "id": "rrjxw7zodbmi", "ini": "2027-08-23", "nombre": "Contratar transporte", "parent": "3xmucac1brvr", "raci": {}}, {"estado": "pendiente", "fin": "2027-09-03", "hito": false, "id": "i4swba4rp2i9", "ini": "2027-08-30", "nombre": "Asegurar instrumentos y equipo de audio", "parent": "3xmucac1brvr", "raci": {}}, {"estado": "pendiente", "fin": "2027-09-24", "hito": false, "id": "kmnid1ly7i4b", "ini": "2027-09-20", "nombre": "Preparar materiales y kits para asistentes", "parent": "3xmucac1brvr", "raci": {}}, {"estado": "pendiente", "fin": "2027-10-07", "hito": false, "id": "waiorhz1y8zj", "ini": "2027-10-04", "nombre": "Confirmación final con sede, proveedores y formadores", "parent": "3xmucac1brvr", "raci": {}}, {"estado": "pendiente", "id": "3un6bzvlv784", "nombre": "Comunicación con asistentes", "parent": null, "raci": {}}, {"estado": "pendiente", "fin": "2027-08-06", "hito": false, "id": "2r9ndwb6vgwy", "ini": "2027-07-26", "nombre": "Enviar mensaje de aceptación al campamento", "parent": "3un6bzvlv784", "raci": {}}, {"estado": "pendiente", "fin": "2027-08-13", "hito": false, "id": "cgxkegs7vsp7", "ini": "2027-08-09", "nombre": "Hacer llamada a los asistentes aceptados al camp", "parent": "3un6bzvlv784", "raci": {}}, {"estado": "pendiente", "fin": "2027-08-20", "hito": false, "id": "s1n0licuw257", "ini": "2027-08-16", "nombre": "Crear grupo de WhatsApp para asistentes", "parent": "3un6bzvlv784", "raci": {}}, {"estado": "pendiente", "fin": "2027-08-20", "hito": false, "id": "hxmyr2tb8553", "ini": "2027-08-16", "nombre": "Hacer plan de comunicación con asistentes", "parent": "3un6bzvlv784", "raci": {}}, {"estado": "pendiente", "fin": "2027-09-10", "hito": false, "id": "5zzhbb52sefi", "ini": "2027-09-06", "nombre": "Crear página con el itinerario", "parent": "3un6bzvlv784", "raci": {}}, {"estado": "pendiente", "fin": "2027-09-10", "hito": false, "id": "t8ly8nmds93t", "ini": "2027-09-06", "nombre": "Crear lista de qué llevar", "parent": "3un6bzvlv784", "raci": {}}, {"estado": "pendiente", "fin": "2027-09-17", "hito": false, "id": "a7yspsczuxi5", "ini": "2027-09-13", "nombre": "Crear formulario de registro de llevadas", "parent": "3un6bzvlv784", "raci": {}}, {"estado": "pendiente", "fin": "2027-10-01", "hito": false, "id": "atkhhd1u8ukc", "ini": "2027-09-27", "nombre": "Enviar material a los participantes", "parent": "3un6bzvlv784", "raci": {}}, {"estado": "pendiente", "id": "ah2kt8eehqla", "nombre": "Evento", "parent": null, "raci": {}}, {"estado": "pendiente", "fin": "2027-10-17", "hito": false, "id": "stln4fxcu4z3", "ini": "2027-10-08", "nombre": "Campamento Eleva tu música", "parent": "ah2kt8eehqla", "raci": {}}, {"estado": "pendiente", "id": "acrcu53t8nyy", "nombre": "Cierre y evaluación", "parent": null, "raci": {}}, {"estado": "pendiente", "fin": "2027-10-22", "hito": false, "id": "pjzhymluwonj", "ini": "2027-10-18", "nombre": "Encuesta de satisfacción a los asistentes", "parent": "acrcu53t8nyy", "raci": {}}, {"estado": "pendiente", "fin": "2027-10-29", "hito": false, "id": "2lo9lktg9ihn", "ini": "2027-10-18", "nombre": "Seguimiento a ministerios prospectos para el colectivo", "parent": "acrcu53t8nyy", "raci": {}}, {"estado": "pendiente", "fin": "2027-10-29", "hito": false, "id": "fani1chyojqj", "ini": "2027-10-25", "nombre": "Reporte de resultados y aprendizajes", "parent": "acrcu53t8nyy", "raci": {}}], "nombre": "Eleva tu música"}$tdd$::jsonb),
('plataforma-de-formacion', 'formacion', $tdd${"area": "formacion", "charter": {}, "cierre": {"objetivos": {}}, "creado": "2026-11-19T22:00:01.000Z", "equipo": [], "indicadores": [], "items": [], "nombre": "Plataforma de formación"}$tdd$::jsonb)
on conflict (id) do nothing;

insert into public.equipos (id, area, data) values
('fvlyafwp2pjh', 'formacion', $tdd${"actualizado": "2026-11-20T16:01:43.373Z", "area": "formacion", "miembros": [{"nombre": "Ceci Gómez", "roles": ["Project Manager"]}, {"nombre": "Rosy Ruesga", "roles": ["Seguimiento músicos"]}, {"nombre": "Diego Suárez", "roles": ["Desarrollador web", "Formador"]}, {"nombre": "Memo Reyes", "roles": ["Formador"]}, {"nombre": "Ale Suárez", "roles": ["Formadora", "Diseñadora instruccional"]}, {"nombre": "Ariel González", "roles": ["Formador"]}, {"nombre": "Willy Gálvez", "roles": ["Coordinador audiovisual"]}, {"nombre": "Karla Flores", "roles": ["Formadora", "Seguimiento formadores"]}, {"nombre": "Ricardo Bañuelos", "roles": ["Finanzas"]}], "nombre": "Equipo base"}$tdd$::jsonb)
on conflict (id) do nothing;

-- El equipo guardado de la versión anterior de este archivo se reemplazó; se borra por si ya se había cargado.
delete from public.equipos where id = '4550igq497x4';

insert into public.migraciones_aplicadas (nombre) values ('031_proyectos_formacion') on conflict (nombre) do nothing;
