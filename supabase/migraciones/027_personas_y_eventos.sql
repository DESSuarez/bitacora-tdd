-- Bitácora Tiempo de Dios · migración 027: Operativo → Personas (base de asistentes y donadores)
-- · crm_personas: un perfil único por persona (contacto, cumpleaños, estado de seguimiento, responsable,
--   próxima acción). No se duplica: el registro busca primero por correo y luego por teléfono.
-- · crm_asistencias: quién se registró, confirmó, vino o no vino a cada fecha de un cenáculo o evento del
--   calendario (evento = id del evento en «eventos», fecha = el día; los cenáculos se repiten).
-- · crm_seguimientos: historial de conversaciones y próximas acciones.
-- · crm_donaciones: solo Finanzas, la PM y el desarrollador ven montos. «donador» en la persona lo pone un trigger.
-- · crm_mensajes: correos y WhatsApp enviados o recibidos (también evita mandar dos veces lo mismo).
-- · crm_boletines: newsletters.
-- · Funciones públicas para el formulario /registro: eventos con registro abierto, registrarse,
--   confirmar o cancelar desde la liga personal y darse de baja de los correos.
-- · Cron diario (9:00 de México) que llama a la Edge Function «crm»: invitaciones 15 y 7 días antes,
--   recordatorio por WhatsApp 2 días antes y resumen para Operativo.
-- Ejecútala una vez en Supabase → SQL Editor → Run. Se puede volver a correr sin error.

create or replace function public.crm_tocar()
returns trigger language plpgsql as $$ begin new.actualizado = now(); return new; end $$;

-- ============ Personas ============
create table if not exists public.crm_personas (
  id uuid primary key default gen_random_uuid(),
  nombre text not null check (char_length(trim(nombre)) between 2 and 120),
  telefono text not null default '' check (char_length(telefono) <= 40),
  tel_digitos text generated always as (right(regexp_replace(telefono, '\D', '', 'g'), 10)) stored,
  correo text not null default '' check (char_length(correo) <= 160),
  nacimiento date,
  empresa text not null default '' check (char_length(empresa) <= 120),
  cargo text not null default '' check (char_length(cargo) <= 120),
  ciudad text not null default '' check (char_length(ciudad) <= 120),
  origen text not null default '' check (char_length(origen) <= 160),
  responsable uuid references public.perfiles(id) on delete set null,
  estado text not null default 'sin_contactar' check (estado in
    ('sin_contactar','contacto_inicial','en_conversacion','interesado','seguimiento_pendiente','no_interesado','relacion_activa')),
  proxima_accion text not null default '' check (char_length(proxima_accion) <= 300),
  proxima_fecha date,
  notas text not null default '' check (char_length(notas) <= 4000),
  acepta_correos boolean not null default true,
  acepta_whatsapp boolean not null default true,
  donador boolean not null default false,
  token uuid not null default gen_random_uuid() unique,  -- liga personal: confirmar asistencia y darse de baja
  creado timestamptz not null default now(),
  actualizado timestamptz not null default now(),
  creado_por uuid default auth.uid()
);
create unique index if not exists crm_personas_correo on public.crm_personas (lower(correo)) where correo <> '';
create index if not exists crm_personas_tel on public.crm_personas (tel_digitos);
drop trigger if exists crm_personas_actualizado on public.crm_personas;
create trigger crm_personas_actualizado before update on public.crm_personas for each row execute function public.crm_tocar();

-- ============ Asistencia a cada fecha de un evento ============
create table if not exists public.crm_asistencias (
  id uuid primary key default gen_random_uuid(),
  persona uuid not null references public.crm_personas(id) on delete cascade,
  evento text not null,
  fecha date not null,
  estado text not null default 'registrado' check (estado in ('invitado','registrado','confirmo','asistio','no_asistio','cancelo')),
  origen text not null default 'manual' check (origen in ('formulario','puerta','manual')),
  nota text not null default '' check (char_length(nota) <= 1000),
  creado timestamptz not null default now(),
  actualizado timestamptz not null default now(),
  marcado_por uuid default auth.uid(),
  unique (persona, evento, fecha)
);
create index if not exists crm_asistencias_evento on public.crm_asistencias (evento, fecha);
drop trigger if exists crm_asistencias_actualizado on public.crm_asistencias;
create trigger crm_asistencias_actualizado before update on public.crm_asistencias for each row execute function public.crm_tocar();

-- ============ Seguimiento (historial de conversaciones) ============
create table if not exists public.crm_seguimientos (
  id uuid primary key default gen_random_uuid(),
  persona uuid not null references public.crm_personas(id) on delete cascade,
  fecha timestamptz not null default now(),
  medio text not null default 'whatsapp' check (medio in ('llamada','whatsapp','correo','en_persona','otro','sistema')),
  responsable uuid references public.perfiles(id) on delete set null,
  resumen text not null default '' check (char_length(resumen) <= 4000),
  interes text not null default '' check (char_length(interes) <= 300),
  proxima_accion text not null default '' check (char_length(proxima_accion) <= 300),
  proxima_fecha date,
  estado text,  -- estado al que pasó la persona con esta conversación (si cambió)
  creado timestamptz not null default now(),
  creado_por uuid default auth.uid()
);
create index if not exists crm_seguimientos_persona on public.crm_seguimientos (persona, fecha desc);

-- ============ Donaciones (solo Finanzas, PM y desarrollador) ============
create table if not exists public.crm_donaciones (
  id uuid primary key default gen_random_uuid(),
  persona uuid not null references public.crm_personas(id) on delete cascade,
  monto numeric(12,2) not null check (monto > 0),
  fecha date not null default current_date,
  tipo text not null default 'unica' check (tipo in ('unica','recurrente')),
  destino text not null default '' check (char_length(destino) <= 160),
  metodo text not null default '' check (char_length(metodo) <= 80),
  estado text not null default 'comprometida' check (estado in ('comprometida','recibida','cancelada')),
  evento text not null default '',   -- «<id del evento>|<fecha>» si salió de un evento
  comprobante text not null default '' check (char_length(comprobante) <= 500),
  notas text not null default '' check (char_length(notas) <= 2000),
  creado timestamptz not null default now(),
  actualizado timestamptz not null default now(),
  creado_por uuid default auth.uid()
);
create index if not exists crm_donaciones_persona on public.crm_donaciones (persona);
drop trigger if exists crm_donaciones_actualizado on public.crm_donaciones;
create trigger crm_donaciones_actualizado before update on public.crm_donaciones for each row execute function public.crm_tocar();
-- «Donador» se ve en la persona sin mostrar montos: alguien con al menos una donación recibida
create or replace function public.crm_marcar_donador()
returns trigger language plpgsql security definer set search_path = public as $$
declare p uuid := coalesce(new.persona, old.persona);
begin
  update public.crm_personas set donador = exists (select 1 from public.crm_donaciones d where d.persona = p and d.estado = 'recibida')
   where id = p;
  if tg_op = 'UPDATE' and old.persona <> new.persona then
    update public.crm_personas set donador = exists (select 1 from public.crm_donaciones d where d.persona = old.persona and d.estado = 'recibida')
     where id = old.persona;
  end if;
  return null;
end $$;
drop trigger if exists crm_donaciones_donador on public.crm_donaciones;
create trigger crm_donaciones_donador after insert or update or delete on public.crm_donaciones
  for each row execute function public.crm_marcar_donador();

-- ============ Mensajes (correo y WhatsApp) ============
create table if not exists public.crm_mensajes (
  id uuid primary key default gen_random_uuid(),
  persona uuid references public.crm_personas(id) on delete cascade,
  canal text not null check (canal in ('correo','whatsapp')),
  direccion text not null default 'salida' check (direccion in ('salida','entrada')),
  tipo text not null default '' check (char_length(tipo) <= 40),  -- invitacion15, invitacion7, recordatorio, boletin, texto, respuesta…
  texto text not null default '' check (char_length(texto) <= 4000),
  evento text not null default '',
  fecha_evento date,
  clave text unique,   -- para no mandar dos veces el mismo aviso
  estado text not null default 'enviado' check (char_length(estado) <= 40),
  wa_id text,
  error text not null default '' check (char_length(error) <= 1000),
  creado timestamptz not null default now(),
  creado_por uuid default auth.uid()
);
create index if not exists crm_mensajes_persona on public.crm_mensajes (persona, creado desc);
create index if not exists crm_mensajes_wa on public.crm_mensajes (wa_id) where wa_id is not null;

-- ============ Newsletters ============
create table if not exists public.crm_boletines (
  id uuid primary key default gen_random_uuid(),
  asunto text not null default '' check (char_length(asunto) <= 160),
  titulo text not null default '' check (char_length(titulo) <= 160),
  cuerpo text not null default '' check (char_length(cuerpo) <= 20000),
  imagen text not null default '' check (char_length(imagen) <= 500),
  boton_texto text not null default '' check (char_length(boton_texto) <= 60),
  boton_liga text not null default '' check (char_length(boton_liga) <= 500),
  estado text not null default 'borrador' check (estado in ('borrador','enviando','enviado')),
  enviados int not null default 0,
  total int not null default 0,
  enviado_en timestamptz,
  creado timestamptz not null default now(),
  actualizado timestamptz not null default now(),
  creado_por uuid default auth.uid()
);
drop trigger if exists crm_boletines_actualizado on public.crm_boletines;
create trigger crm_boletines_actualizado before update on public.crm_boletines for each row execute function public.crm_tocar();

-- ============ Permisos ============
-- Operativo (también como área adicional), la PM y el desarrollador: personas, asistencia, seguimiento, mensajes y boletines.
-- Donaciones: solo Finanzas, la PM y el desarrollador. Borrar personas: solo la PM y el desarrollador.
alter table public.crm_personas enable row level security;
alter table public.crm_asistencias enable row level security;
alter table public.crm_seguimientos enable row level security;
alter table public.crm_donaciones enable row level security;
alter table public.crm_mensajes enable row level security;
alter table public.crm_boletines enable row level security;
do $$ declare t text; begin
  foreach t in array array['crm_personas','crm_asistencias','crm_seguimientos','crm_mensajes','crm_boletines'] loop
    execute format('drop policy if exists %1$s_ver on public.%1$s', t);
    execute format('create policy %1$s_ver on public.%1$s for select to authenticated using (public.puede_area(''operativo''))', t);
    execute format('drop policy if exists %1$s_crear on public.%1$s', t);
    execute format('create policy %1$s_crear on public.%1$s for insert to authenticated with check (public.puede_area(''operativo''))', t);
    execute format('drop policy if exists %1$s_editar on public.%1$s', t);
    execute format('create policy %1$s_editar on public.%1$s for update to authenticated using (public.puede_area(''operativo'')) with check (public.puede_area(''operativo''))', t);
    execute format('drop policy if exists %1$s_borrar on public.%1$s', t);
    if t = 'crm_personas' then
      execute format('create policy %1$s_borrar on public.%1$s for delete to authenticated using (public.es_pm())', t);
    else
      execute format('create policy %1$s_borrar on public.%1$s for delete to authenticated using (public.puede_area(''operativo''))', t);
    end if;
  end loop;
end $$;
drop policy if exists crm_donaciones_todo on public.crm_donaciones;
create policy crm_donaciones_todo on public.crm_donaciones for all to authenticated
  using (public.puede_finanzas() or public.es_pm()) with check (public.puede_finanzas() or public.es_pm());

-- ============ Fechas de un evento del calendario ============
-- ¿El evento (data de «eventos») ocurre ese día? Misma regla que ocurrencias() de agenda-reglas.js
create or replace function public.evento_ocurre(d jsonb, f date)
returns boolean language plpgsql immutable as $$
declare ini date; hasta date; rep text := coalesce(d->>'repetir', '');
begin
  begin ini := (d->>'fecha')::date; hasta := nullif(d->>'hasta', '')::date; exception when others then return false; end;
  if ini is null or f < ini then return false; end if;
  if rep <> '' and hasta is not null and f > hasta then return false; end if;
  if coalesce(d->'excepciones', '[]'::jsonb) ? to_char(f, 'YYYY-MM-DD') then return false; end if;
  return case rep
    when '' then f = ini
    when 'semanal' then (f - ini) % 7 = 0
    when 'quincenal' then (f - ini) % 14 = 0
    when 'mensual' then extract(day from f) = extract(day from ini)
    when 'anual' then to_char(f, 'MM-DD') = to_char(ini, 'MM-DD')
    else f = ini end;
end $$;
-- Un evento tiene registro abierto si es cenáculo o si se marcó «registro» en el calendario
create or replace function public.evento_con_registro(d jsonb)
returns boolean language sql immutable as $$
  select d->>'tipo' = 'cenaculo' or coalesce(d->>'registro', '') = 'true';
$$;

-- Eventos con registro abierto (para el formulario público): solo lo necesario para mostrarlos
create or replace function public.registro_eventos()
returns json language sql stable security definer set search_path = public as $$
  select coalesce(json_agg(json_build_object('id', e.id, 'titulo', e.data->>'titulo', 'tipo', e.data->>'tipo',
      'fecha', e.data->>'fecha', 'fin', coalesce(e.data->>'fin', ''), 'hora', coalesce(e.data->>'hora', ''),
      'horaFin', coalesce(e.data->>'horaFin', ''), 'repetir', coalesce(e.data->>'repetir', ''), 'hasta', coalesce(e.data->>'hasta', ''),
      'excepciones', coalesce(e.data->'excepciones', '[]'::jsonb), 'lugar', coalesce(e.data->>'lugar', ''))), '[]'::json)
    from public.eventos e
   where public.evento_con_registro(e.data)
     and ((coalesce(e.data->>'repetir', '') <> '' and coalesce(nullif(e.data->>'hasta', ''), '9999-12-31') >= to_char(current_date, 'YYYY-MM-DD'))
          or (e.data->>'fecha') >= to_char(current_date - 1, 'YYYY-MM-DD'));
$$;
grant execute on function public.registro_eventos() to anon, authenticated;

-- ============ Alta sin duplicados ============
-- Busca por correo; si no, por teléfono (10 dígitos) cuando alguno de los dos no tiene correo. Completa lo que falte.
create or replace function public.crm_guardar_persona(p_nombre text, p_tel text, p_correo text, p_nac date, p_origen text, p_acepta boolean)
returns uuid language plpgsql security definer set search_path = public as $$
declare pid uuid; c text := lower(trim(coalesce(p_correo, ''))); t text := right(regexp_replace(coalesce(p_tel, ''), '\D', '', 'g'), 10);
begin
  if c <> '' then select id into pid from public.crm_personas where lower(correo) = c limit 1; end if;
  if pid is null and char_length(t) = 10 then
    select id into pid from public.crm_personas where tel_digitos = t and (c = '' or correo = '') order by creado limit 1;
  end if;
  if pid is null then
    insert into public.crm_personas (nombre, telefono, correo, nacimiento, origen, acepta_correos, creado_por)
    values (left(trim(p_nombre), 120), left(trim(coalesce(p_tel, '')), 40), left(c, 160), p_nac, left(coalesce(p_origen, ''), 160), coalesce(p_acepta, true), auth.uid())
    returning id into pid;
  else
    update public.crm_personas set
      telefono = case when telefono = '' then left(trim(coalesce(p_tel, '')), 40) else telefono end,
      correo = case when correo = '' then left(c, 160) else correo end,
      nacimiento = coalesce(nacimiento, p_nac),
      acepta_correos = case when p_acepta then true else acepta_correos end
     where id = pid;
  end if;
  return pid;
end $$;
revoke all on function public.crm_guardar_persona(text, text, text, date, text, boolean) from public, anon, authenticated;

-- Registro público a una fecha de un evento (formulario /registro)
create or replace function public.registro_evento(ev text, f date, nombre text, telefono text, correo text, nacimiento date, acepta boolean default true)
returns json language plpgsql security definer set search_path = public as $$
#variable_conflict use_variable
declare e record; pid uuid;
begin
  if coalesce(char_length(trim(nombre)), 0) < 2 then raise exception 'Escribe tu nombre.'; end if;
  if coalesce(trim(correo), '') !~* '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'Revisa tu correo.'; end if;
  if char_length(regexp_replace(coalesce(telefono, ''), '\D', '', 'g')) < 10 then raise exception 'Escribe tu teléfono a 10 dígitos.'; end if;
  if nacimiento is not null and (nacimiento > current_date or nacimiento < date '1900-01-01') then raise exception 'Revisa tu fecha de nacimiento.'; end if;
  select * into e from public.eventos x where x.id = ev;
  if not found or not public.evento_con_registro(e.data) or not public.evento_ocurre(e.data, f) then raise exception 'Este evento ya no tiene registro abierto.'; end if;
  if f < current_date - 1 or f > current_date + 180 then raise exception 'El registro para esa fecha está cerrado.'; end if;
  pid := public.crm_guardar_persona(nombre, telefono, correo, nacimiento, 'Registro: ' || coalesce(e.data->>'titulo', 'evento'), coalesce(acepta, false));
  insert into public.crm_asistencias (persona, evento, fecha, estado, origen, marcado_por) values (pid, ev, f, 'registrado', 'formulario', null)
  on conflict (persona, evento, fecha) do update set estado = case when crm_asistencias.estado in ('invitado','cancelo','no_asistio') then 'registrado' else crm_asistencias.estado end;
  return json_build_object('ok', true, 'titulo', e.data->>'titulo', 'fecha', f, 'hora', coalesce(e.data->>'hora', ''), 'lugar', coalesce(e.data->>'lugar', ''));
end $$;
grant execute on function public.registro_evento(text, date, text, text, text, date, boolean) to anon, authenticated;

-- Alta en la puerta (el mismo día): la registra y la marca como «vino»
create or replace function public.crm_puerta(ev text, f date, nombre text, telefono text, correo text, nacimiento date)
returns uuid language plpgsql security definer set search_path = public as $$
#variable_conflict use_variable
declare pid uuid; titulo text;
begin
  if not public.puede_area('operativo') then raise exception 'Solo Operativo puede pasar lista.'; end if;
  if coalesce(char_length(trim(nombre)), 0) < 2 then raise exception 'Escribe el nombre.'; end if;
  select data->>'titulo' into titulo from public.eventos where id = ev;
  pid := public.crm_guardar_persona(nombre, telefono, correo, nacimiento, 'En la puerta: ' || coalesce(titulo, 'evento'), true);
  insert into public.crm_asistencias (persona, evento, fecha, estado, origen) values (pid, ev, f, 'asistio', 'puerta')
  on conflict (persona, evento, fecha) do update set estado = 'asistio';
  return pid;
end $$;
grant execute on function public.crm_puerta(text, date, text, text, text, date) to authenticated;

-- Liga personal (en correos y WhatsApp): r = 'info' (solo ver), 'registrar', 'si' (confirma), 'no' (cancela)
create or replace function public.crm_responder(t uuid, ev text, f date, r text default 'info')
returns json language plpgsql security definer set search_path = public as $$
#variable_conflict use_variable
declare p record; e record; a record; nuevo text;
begin
  select * into p from public.crm_personas where token = t;
  if not found then raise exception 'Esta liga no es válida.'; end if;
  select * into e from public.eventos x where x.id = ev;
  if not found or not public.evento_ocurre(e.data, f) then raise exception 'No encontramos ese evento.'; end if;
  select * into a from public.crm_asistencias x where x.persona = p.id and x.evento = ev and x.fecha = f;
  if r in ('registrar','si','no') then
    if f < current_date then raise exception 'Ese evento ya pasó.'; end if;
    nuevo := case r when 'no' then 'cancelo' when 'si' then 'confirmo' else 'registrado' end;
    if a.id is null then
      if not public.evento_con_registro(e.data) then raise exception 'Este evento no tiene registro abierto.'; end if;
      insert into public.crm_asistencias (persona, evento, fecha, estado, origen, marcado_por) values (p.id, ev, f, nuevo, 'formulario', null);
    elsif not (r = 'registrar' and a.estado in ('confirmo','asistio')) then
      update public.crm_asistencias set estado = nuevo where id = a.id;
    end if;
    insert into public.crm_mensajes (persona, canal, direccion, tipo, texto, evento, fecha_evento, creado_por)
    values (p.id, 'correo', 'entrada', 'respuesta', case r when 'no' then 'No podrá ir (desde su liga)' when 'si' then 'Confirmó que sí va (desde su liga)' else 'Se registró desde su liga' end, ev, f, null);
    select * into a from public.crm_asistencias x where x.persona = p.id and x.evento = ev and x.fecha = f;
  end if;
  return json_build_object('nombre', split_part(p.nombre, ' ', 1), 'titulo', e.data->>'titulo', 'fecha', f,
    'hora', coalesce(e.data->>'hora', ''), 'lugar', coalesce(e.data->>'lugar', ''), 'estado', a.estado);
end $$;
grant execute on function public.crm_responder(uuid, text, date, text) to anon, authenticated;

-- Darse de baja de los correos (liga al pie de cada correo)
create or replace function public.crm_baja(t uuid)
returns json language plpgsql security definer set search_path = public as $$
declare n text;
begin
  update public.crm_personas set acepta_correos = false where token = t returning split_part(nombre, ' ', 1) into n;
  if n is null then raise exception 'Esta liga no es válida.'; end if;
  return json_build_object('ok', true, 'nombre', n);
end $$;
grant execute on function public.crm_baja(uuid) to anon, authenticated;

do $$ begin alter publication supabase_realtime add table public.crm_personas; exception when duplicate_object then null; end $$;
do $$ begin alter publication supabase_realtime add table public.crm_asistencias; exception when duplicate_object then null; end $$;
do $$ begin alter publication supabase_realtime add table public.crm_seguimientos; exception when duplicate_object then null; end $$;
do $$ begin alter publication supabase_realtime add table public.crm_donaciones; exception when duplicate_object then null; end $$;
do $$ begin alter publication supabase_realtime add table public.crm_mensajes; exception when duplicate_object then null; end $$;

-- ============ Envíos automáticos (Edge Function «crm», cada día a las 9:00 de México) ============
select cron.unschedule('bitacora-crm') where exists (select 1 from cron.job where jobname = 'bitacora-crm');
select cron.schedule(
  'bitacora-crm',
  '0 15 * * *',
  $$
  select net.http_post(
    url := 'https://zhzqvetehynndfjbrzti.supabase.co/functions/v1/crm',
    headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InpoenF2ZXRlaHlubmRmamJyenRpIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTM3Mjc3NjgsImV4cCI6MjEwOTMwMzc2OH0.ZhsazISy5Azt7i14qFeHKjcSPNQzXJeeAGcPAoEzjqw'),
    body := '{"accion":"diario"}'::jsonb,
    timeout_milliseconds := 120000
  );
  $$
);

insert into public.migraciones_aplicadas (nombre) values ('027_personas_y_eventos') on conflict (nombre) do nothing;
