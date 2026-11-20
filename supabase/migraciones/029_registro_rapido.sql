-- Bitácora Tiempo de Dios · migración 029: «Ya he ido a un cenáculo» en el registro público
-- Quien ya está en la base busca su nombre, confirma que es él o ella con su teléfono (o correo)
-- y queda registrado sin volver a escribir sus datos.
-- · registro_buscar(q): mínimo 3 letras, máximo 6 resultados y solo nombre + inicial del apellido
--   y los 2 últimos dígitos del teléfono (no expone datos de contacto).
-- · registro_rapido(p, dato, ev, f): registra solo si el teléfono (10 dígitos) o el correo coinciden.
-- Ejecútala una vez en Supabase → SQL Editor → Run. Se puede volver a correr sin error.

create or replace function public.texto_simple(t text)
returns text language sql immutable as $$
  select lower(translate(coalesce(t, ''), 'áéíóúüñÁÉÍÓÚÜÑàèìòùÀÈÌÒÙ', 'aeiouunAEIOUUNaeiouAEIOU'));
$$;

create or replace function public.registro_buscar(q text)
returns json language plpgsql stable security definer set search_path = public as $$
declare b text := public.texto_simple(trim(q));
begin
  if char_length(b) < 3 then return '[]'::json; end if;
  return coalesce((select json_agg(x) from (
    select p.id as ref,
           split_part(trim(p.nombre), ' ', 1) || coalesce(' ' || nullif(left(split_part(trim(p.nombre), ' ', 2), 1), '') || '.', '') as nombre,
           case when char_length(p.tel_digitos) = 10 then right(p.tel_digitos, 2) else '' end as tel,
           p.correo <> '' as con_correo
      from public.crm_personas p
     where public.texto_simple(p.nombre) like '%' || b || '%'
     order by p.actualizado desc
     limit 6) x), '[]'::json);
end $$;
grant execute on function public.registro_buscar(text) to anon, authenticated;

create or replace function public.registro_rapido(p uuid, dato text, ev text, f date)
returns json language plpgsql security definer set search_path = public as $$
#variable_conflict use_variable
declare per record; e record; d text := trim(coalesce(dato, '')); dig text := right(regexp_replace(coalesce(dato, ''), '\D', '', 'g'), 10);
begin
  select * into per from public.crm_personas where id = p;
  if not found then raise exception 'No te encontramos. Regístrate con tus datos.'; end if;
  if not ((char_length(dig) = 10 and per.tel_digitos = dig) or (d like '%@%' and lower(per.correo) = lower(d))) then
    raise exception 'Ese teléfono o correo no coincide con el que tenemos. Revísalo o regístrate con tus datos.';
  end if;
  select * into e from public.eventos x where x.id = ev;
  if not found or not public.evento_con_registro(e.data) or not public.evento_ocurre(e.data, f) then raise exception 'Este evento ya no tiene registro abierto.'; end if;
  if f < current_date - 1 or f > current_date + 180 then raise exception 'El registro para esa fecha está cerrado.'; end if;
  insert into public.crm_asistencias (persona, evento, fecha, estado, origen, marcado_por) values (per.id, ev, f, 'registrado', 'formulario', null)
  on conflict (persona, evento, fecha) do update set estado = case when crm_asistencias.estado in ('invitado','cancelo','no_asistio') then 'registrado' else crm_asistencias.estado end;
  return json_build_object('ok', true, 'nombre', split_part(trim(per.nombre), ' ', 1));
end $$;
grant execute on function public.registro_rapido(uuid, text, text, date) to anon, authenticated;

insert into public.migraciones_aplicadas (nombre) values ('029_registro_rapido') on conflict (nombre) do nothing;
