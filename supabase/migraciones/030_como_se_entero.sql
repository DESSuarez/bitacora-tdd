-- Bitácora Tiempo de Dios · migración 030: «¿Cómo te enteraste?» y quién invitó
-- · Cada registro a un cenáculo o evento guarda por qué medio llegó la persona (crm_asistencias.medio:
--   invitacion, instagram, facebook, tiktok, whatsapp, correo, parroquia u otro) y, si alguien la invitó,
--   quién (crm_asistencias.referido → crm_referidos).
-- · crm_referidos unifica los nombres de quien invita: «ricarDo Bañuelos Sanches» y «Ricardo Bañuelos Sánchez»
--   quedan como la misma persona (sin importar mayúsculas, acentos y pequeñas diferencias de escritura, con pg_trgm)
--   y se muestra siempre la forma mejor escrita (con acentos y con mayúscula inicial). Si Operativo corrige el
--   nombre a mano, se queda así (fijo).
-- · registro_evento, registro_rapido y crm_puerta reciben el medio y quién invitó.
-- Requiere la 029. Ejecútala una vez en Supabase → SQL Editor → Run. Se puede volver a correr sin error.

create extension if not exists pg_trgm with schema extensions;

create or replace function public.texto_simple(t text)
returns text language sql immutable as $$
  select lower(translate(coalesce(t, ''), 'áéíóúüñÁÉÍÓÚÜÑàèìòùÀÈÌÒÙ', 'aeiouunAEIOUUNaeiouAEIOU'));
$$;
-- Clave para comparar nombres: sin acentos, en minúsculas y con espacios sencillos
create or replace function public.nombre_clave(t text)
returns text language sql immutable as $$
  select trim(regexp_replace(public.texto_simple(t), '\s+', ' ', 'g'));
$$;
-- Qué tan bien escrito está un nombre: acentos o ñ, mayúscula inicial en cada palabra y no todo en mayúsculas
create or replace function public.nombre_puntaje(t text)
returns int language sql immutable as $$
  select (case when t ~ '[áéíóúüñÁÉÍÓÚÜÑ]' then 3 else 0 end)
       + (case when t = initcap(t) then 2 else 0 end)
       + (case when t <> upper(t) and t <> lower(t) then 1 else 0 end);
$$;

create table if not exists public.crm_referidos (
  id uuid primary key default gen_random_uuid(),
  nombre text not null check (char_length(nombre) between 2 and 120),
  clave text not null unique,
  variantes jsonb not null default '{}'::jsonb,   -- {«como lo escribieron»: veces}
  veces int not null default 0,
  fijo boolean not null default false,             -- Operativo corrigió el nombre a mano
  creado timestamptz not null default now(),
  actualizado timestamptz not null default now()
);
drop trigger if exists crm_referidos_actualizado on public.crm_referidos;
create trigger crm_referidos_actualizado before update on public.crm_referidos for each row execute function public.crm_tocar();
alter table public.crm_referidos enable row level security;
drop policy if exists crm_referidos_operativo on public.crm_referidos;
create policy crm_referidos_operativo on public.crm_referidos for all to authenticated
  using (public.puede_area('operativo')) with check (public.puede_area('operativo'));

alter table public.crm_asistencias add column if not exists medio text not null default '' check (char_length(medio) <= 40);
alter table public.crm_asistencias add column if not exists medio_otro text not null default '' check (char_length(medio_otro) <= 120);
alter table public.crm_asistencias add column if not exists referido uuid references public.crm_referidos(id) on delete set null;
alter table public.crm_personas add column if not exists referido uuid references public.crm_referidos(id) on delete set null;

-- Encuentra (o crea) a quien invita y suma esta forma de escribirlo
create or replace function public.crm_referido(t text)
returns uuid language plpgsql security definer set search_path = public, extensions as $$
declare v text := left(trim(regexp_replace(coalesce(t, ''), '\s+', ' ', 'g')), 120); c text; rid uuid; r record; mejor text;
begin
  if char_length(v) < 3 then return null; end if;
  c := public.nombre_clave(v);
  select id into rid from public.crm_referidos where clave = c;
  if rid is null then
    select id into rid from public.crm_referidos where similarity(clave, c) >= 0.55 order by similarity(clave, c) desc limit 1;
  end if;
  if rid is null then
    insert into public.crm_referidos (nombre, clave, variantes, veces)
    values (case when public.nombre_puntaje(v) >= 3 then v else initcap(v) end, c, jsonb_build_object(v, 1), 1)
    on conflict (clave) do update set veces = crm_referidos.veces + 1
    returning id into rid;
    return rid;
  end if;
  update public.crm_referidos set variantes = variantes || jsonb_build_object(v, coalesce((variantes->>v)::int, 0) + 1), veces = veces + 1
   where id = rid returning * into r;
  if not r.fijo then
    select key into mejor from jsonb_each_text(r.variantes) order by public.nombre_puntaje(key) desc, value::int desc, char_length(key) desc limit 1;
    update public.crm_referidos set nombre = case when public.nombre_puntaje(mejor) >= 3 then mejor else initcap(mejor) end where id = rid;
  end if;
  return rid;
end $$;
revoke all on function public.crm_referido(text) from public, anon, authenticated;

-- Para el formulario: nombres de quien invita que coinciden (mín. 3 letras, máx. 5)
create or replace function public.registro_invitan(q text)
returns json language sql stable security definer set search_path = public, extensions as $$
  select coalesce(json_agg(nombre), '[]'::json) from (
    select nombre from public.crm_referidos
     where char_length(public.nombre_clave(q)) >= 3
       and (clave like '%' || public.nombre_clave(q) || '%' or similarity(clave, public.nombre_clave(q)) >= 0.4)
     order by veces desc limit 5) x;
$$;
grant execute on function public.registro_invitan(text) to anon, authenticated;

-- Guarda el medio en una asistencia (y quién invitó)
create or replace function public.crm_medio(a uuid, medio text, quien text)
returns void language plpgsql security definer set search_path = public as $$
#variable_conflict use_variable
declare m text := lower(trim(coalesce(medio, ''))); rid uuid; pid uuid;
begin
  if m = '' then return; end if;
  if m not in ('invitacion','instagram','facebook','tiktok','whatsapp','correo','parroquia','otro') then m := 'otro'; end if;
  if m = 'invitacion' then rid := public.crm_referido(quien); end if;
  update public.crm_asistencias set medio = m, referido = coalesce(rid, referido),
         medio_otro = case when m = 'otro' then left(trim(coalesce(quien, '')), 120) else '' end
   where id = a returning persona into pid;
  if rid is not null then update public.crm_personas set referido = rid where id = pid and referido is null; end if;
end $$;
revoke all on function public.crm_medio(uuid, text, text) from public, anon, authenticated;

-- Registro público (con medio)
drop function if exists public.registro_evento(text, date, text, text, text, date, boolean);
create or replace function public.registro_evento(ev text, f date, nombre text, telefono text, correo text, nacimiento date,
  acepta boolean default true, medio text default '', quien text default '')
returns json language plpgsql security definer set search_path = public as $$
#variable_conflict use_variable
declare e record; pid uuid; aid uuid;
begin
  if coalesce(char_length(trim(nombre)), 0) < 2 then raise exception 'Escribe tu nombre.'; end if;
  if coalesce(trim(correo), '') !~* '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'Revisa tu correo.'; end if;
  if char_length(regexp_replace(coalesce(telefono, ''), '\D', '', 'g')) < 10 then raise exception 'Escribe tu teléfono a 10 dígitos.'; end if;
  if nacimiento is null or nacimiento > current_date or nacimiento < date '1900-01-01' then raise exception 'Revisa tu fecha de nacimiento.'; end if;
  if coalesce(trim(medio), '') = '' then raise exception 'Cuéntanos cómo te enteraste.'; end if;
  if medio = 'invitacion' and char_length(trim(coalesce(quien, ''))) < 3 then raise exception 'Escribe el nombre de quien te invitó.'; end if;
  select * into e from public.eventos x where x.id = ev;
  if not found or not public.evento_con_registro(e.data) or not public.evento_ocurre(e.data, f) then raise exception 'Este evento ya no tiene registro abierto.'; end if;
  if f < current_date - 1 or f > current_date + 180 then raise exception 'El registro para esa fecha está cerrado.'; end if;
  pid := public.crm_guardar_persona(nombre, telefono, correo, nacimiento, 'Registro: ' || coalesce(e.data->>'titulo', 'evento'), coalesce(acepta, false));
  insert into public.crm_asistencias (persona, evento, fecha, estado, origen, marcado_por) values (pid, ev, f, 'registrado', 'formulario', null)
  on conflict (persona, evento, fecha) do update set estado = case when crm_asistencias.estado in ('invitado','cancelo','no_asistio') then 'registrado' else crm_asistencias.estado end
  returning id into aid;
  perform public.crm_medio(aid, medio, quien);
  return json_build_object('ok', true, 'titulo', e.data->>'titulo', 'fecha', f, 'hora', coalesce(e.data->>'hora', ''), 'lugar', coalesce(e.data->>'lugar', ''));
end $$;
grant execute on function public.registro_evento(text, date, text, text, text, date, boolean, text, text) to anon, authenticated;

-- «Ya he ido a un cenáculo» (con medio)
drop function if exists public.registro_rapido(uuid, text, text, date);
create or replace function public.registro_rapido(p uuid, dato text, ev text, f date, medio text default '', quien text default '')
returns json language plpgsql security definer set search_path = public as $$
#variable_conflict use_variable
declare per record; e record; aid uuid; d text := trim(coalesce(dato, '')); dig text := right(regexp_replace(coalesce(dato, ''), '\D', '', 'g'), 10);
begin
  select * into per from public.crm_personas where id = p;
  if not found then raise exception 'No te encontramos. Regístrate con tus datos.'; end if;
  if not ((char_length(dig) = 10 and per.tel_digitos = dig) or (d like '%@%' and lower(per.correo) = lower(d))) then
    raise exception 'Ese teléfono o correo no coincide con el que tenemos. Revísalo o regístrate con tus datos.';
  end if;
  if coalesce(trim(medio), '') = '' then raise exception 'Cuéntanos cómo te enteraste.'; end if;
  if medio = 'invitacion' and char_length(trim(coalesce(quien, ''))) < 3 then raise exception 'Escribe el nombre de quien te invitó.'; end if;
  select * into e from public.eventos x where x.id = ev;
  if not found or not public.evento_con_registro(e.data) or not public.evento_ocurre(e.data, f) then raise exception 'Este evento ya no tiene registro abierto.'; end if;
  if f < current_date - 1 or f > current_date + 180 then raise exception 'El registro para esa fecha está cerrado.'; end if;
  insert into public.crm_asistencias (persona, evento, fecha, estado, origen, marcado_por) values (per.id, ev, f, 'registrado', 'formulario', null)
  on conflict (persona, evento, fecha) do update set estado = case when crm_asistencias.estado in ('invitado','cancelo','no_asistio') then 'registrado' else crm_asistencias.estado end
  returning id into aid;
  perform public.crm_medio(aid, medio, quien);
  return json_build_object('ok', true, 'nombre', split_part(trim(per.nombre), ' ', 1));
end $$;
grant execute on function public.registro_rapido(uuid, text, text, date, text, text) to anon, authenticated;

-- Alta en la puerta (con medio)
drop function if exists public.crm_puerta(text, date, text, text, text, date);
create or replace function public.crm_puerta(ev text, f date, nombre text, telefono text, correo text, nacimiento date,
  medio text default '', quien text default '')
returns uuid language plpgsql security definer set search_path = public as $$
#variable_conflict use_variable
declare pid uuid; aid uuid; titulo text;
begin
  if not public.puede_area('operativo') then raise exception 'Solo Operativo puede pasar lista.'; end if;
  if coalesce(char_length(trim(nombre)), 0) < 2 then raise exception 'Escribe el nombre.'; end if;
  select data->>'titulo' into titulo from public.eventos where id = ev;
  pid := public.crm_guardar_persona(nombre, telefono, correo, nacimiento, 'En la puerta: ' || coalesce(titulo, 'evento'), true);
  insert into public.crm_asistencias (persona, evento, fecha, estado, origen) values (pid, ev, f, 'asistio', 'puerta')
  on conflict (persona, evento, fecha) do update set estado = 'asistio'
  returning id into aid;
  perform public.crm_medio(aid, medio, quien);
  return pid;
end $$;
grant execute on function public.crm_puerta(text, date, text, text, text, date, text, text) to authenticated;

do $$ begin alter publication supabase_realtime add table public.crm_referidos; exception when duplicate_object then null; end $$;

insert into public.migraciones_aplicadas (nombre) values ('030_como_se_entero') on conflict (nombre) do nothing;
