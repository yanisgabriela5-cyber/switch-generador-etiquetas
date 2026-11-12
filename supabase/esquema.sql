-- =====================================================================
--  Generador de Etiquetas — Switch Soft
--  Base compartida en Supabase.
--
--  Cómo usarlo: en Supabase abre "SQL Editor", pega TODO este archivo
--  y presiona "Run". Se puede volver a ejecutar sin perder datos.
--
--  Qué guarda:
--   · El archivo (Excel/CSV) que se está trabajando, fila por fila.
--   · Cada cambio que hace cada dispositivo, para repartirlo a los demás.
--   · El último número de SKU usado por cada prefijo (SG, HP, …), para que
--     dos personas nunca generen el mismo código.
--   · La cola de impresión remota (celular -> PC con la impresora).
--   · Las plantillas de etiqueta, para que todos usen las mismas.
--
--  Seguridad: las tablas quedan cerradas (RLS sin políticas). La página
--  solo puede usar las funciones et_* de abajo.
-- =====================================================================

create extension if not exists pgcrypto;

-- ---------- Tablas ----------
create table if not exists compartido (
  id        int primary key default 1 check (id = 1),
  epoca     text,                       -- identifica el archivo vigente
  version   bigint not null default 0,  -- sube con cada cambio
  nombre    text,
  columnas  text[] not null default '{}',
  n_filas   int not null default 0,
  cargado   timestamptz
);
insert into compartido (id) values (1) on conflict (id) do nothing;

create table if not exists cargas (      -- archivos que se están subiendo por partes
  epoca    text primary key,
  nombre   text,
  columnas text[] not null,
  cliente  text,
  creado   timestamptz not null default now()
);

create table if not exists filas (
  epoca text not null,
  idx   int  not null,
  datos jsonb not null,                  -- lista de textos, en el orden de "columnas"
  primary key (epoca, idx)
);

create table if not exists lotes (       -- historial de cambios del archivo vigente
  epoca   text   not null,
  version bigint not null,
  cliente text,
  cambios jsonb not null default '[]',
  nuevas  jsonb not null default '[]',
  creado  timestamptz not null default now(),
  primary key (epoca, version)
);

create table if not exists clientes (    -- dispositivos conectados (para el contador "N equipos")
  cliente text primary key,
  visto   timestamptz not null default now()
);

create table if not exists sku_contadores (
  prefijo text primary key,
  ultimo  int not null default 0
);

create table if not exists trabajos_impresion (
  id       bigserial primary key,
  creado   timestamptz not null default now(),
  trabajos jsonb not null
);

create table if not exists plantillas (
  nombre     text primary key,
  datos      jsonb not null,
  actualizado timestamptz not null default now()
);

alter table compartido         enable row level security;
alter table cargas             enable row level security;
alter table filas              enable row level security;
alter table lotes              enable row level security;
alter table clientes           enable row level security;
alter table sku_contadores     enable row level security;
alter table trabajos_impresion enable row level security;
alter table plantillas         enable row level security;

-- ---------- Ayudantes internos ----------
create or replace function et_latido(p_cliente text) returns int
language plpgsql security definer set search_path = public as $$
declare n int;
begin
  if p_cliente is not null and p_cliente <> '' then
    insert into clientes (cliente, visto) values (p_cliente, now())
      on conflict (cliente) do update set visto = now();
  end if;
  delete from clientes where visto < now() - interval '1 hour';
  select count(*) into n from clientes where visto > now() - interval '20 seconds';
  return greatest(n, 1);
end $$;

-- ---------- Estado general ----------
create or replace function et_info(p_cliente text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare c compartido; n int;
begin
  n := et_latido(p_cliente);
  select * into c from compartido where id = 1;
  return jsonb_build_object('version', coalesce(c.version, 0) * (case when c.epoca is null then 0 else 1 end),
                            'nombre', c.nombre, 'epoca', c.epoca, 'clientes', n);
end $$;

-- Todo el archivo vigente, en una sola lectura consistente.
create or replace function et_estado() returns jsonb
language plpgsql security definer set search_path = public as $$
declare c compartido;
begin
  select * into c from compartido where id = 1;
  if c.epoca is null then return jsonb_build_object('version', 0); end if;
  return jsonb_build_object(
    'epoca', c.epoca, 'version', c.version, 'nombre', c.nombre, 'columnas', to_jsonb(c.columnas),
    'filas', coalesce((select jsonb_agg(f.datos order by f.idx) from filas f where f.epoca = c.epoca), '[]'::jsonb));
end $$;

-- ---------- Subir un archivo nuevo (por partes) ----------
create or replace function et_cargar_inicio(p_nombre text, p_columnas text[], p_cliente text) returns text
language plpgsql security definer set search_path = public as $$
declare e text := gen_random_uuid()::text;
begin
  -- limpia subidas a medias de hace más de una hora
  delete from filas where epoca in (select epoca from cargas where creado < now() - interval '1 hour');
  delete from cargas where creado < now() - interval '1 hour';
  insert into cargas (epoca, nombre, columnas, cliente) values (e, p_nombre, p_columnas, p_cliente);
  return e;
end $$;

create or replace function et_cargar_filas(p_epoca text, p_desde int, p_filas jsonb) returns int
language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from cargas where epoca = p_epoca) then raise exception 'Carga no encontrada'; end if;
  insert into filas (epoca, idx, datos)
    select p_epoca, p_desde + (t.ord - 1)::int, t.valor
    from jsonb_array_elements(p_filas) with ordinality as t(valor, ord)
  on conflict (epoca, idx) do update set datos = excluded.datos;
  return jsonb_array_length(p_filas);
end $$;

create or replace function et_cargar_fin(p_epoca text, p_total int, p_cliente text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare k cargas; n int; v bigint;
begin
  select * into k from cargas where epoca = p_epoca;
  if not found then raise exception 'Carga no encontrada'; end if;
  select count(*) into n from filas where epoca = p_epoca;
  if n <> p_total then raise exception 'Faltan filas: llegaron % de %', n, p_total; end if;
  perform 1 from compartido where id = 1 for update;
  update compartido set epoca = p_epoca, version = version + 1, nombre = k.nombre, columnas = k.columnas,
                        n_filas = p_total, cargado = now()
    where id = 1 returning version into v;
  delete from cargas where epoca = p_epoca;
  delete from filas where epoca <> p_epoca and epoca not in (select epoca from cargas);
  delete from lotes where epoca <> p_epoca;
  return jsonb_build_object('epoca', p_epoca, 'version', v);
end $$;

-- ---------- Enviar cambios de un dispositivo ----------
-- p_cambios: [{"i": fila, "c": {"Columna": "valor", ...}}, ...]
-- p_nuevas:  [["valor col 1", "valor col 2", ...], ...]
create or replace function et_cambios_enviar(p_epoca text, p_cliente text, p_base bigint, p_cambios jsonb, p_nuevas jsonb)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare c compartido; r jsonb; kv record; pos int; remotos jsonb; ini int; nn int; v bigint;
begin
  perform et_latido(p_cliente);
  select * into c from compartido where id = 1 for update;
  if c.epoca is distinct from p_epoca then return jsonb_build_object('reiniciar', true, 'atrasado', false); end if;
  if p_base > c.version then return jsonb_build_object('reiniciar', true, 'atrasado', true); end if;

  -- primero lo que hicieron los demás desde la última vez que este dispositivo sincronizó
  select coalesce(jsonb_agg(jsonb_build_object('cambios', l.cambios, 'nuevas', l.nuevas) order by l.version), '[]'::jsonb)
    into remotos from lotes l where l.epoca = p_epoca and l.version > p_base and l.cliente is distinct from p_cliente;

  -- aplica los cambios de celdas
  for r in select * from jsonb_array_elements(coalesce(p_cambios, '[]'::jsonb)) loop
    for kv in select * from jsonb_each_text(r->'c') loop
      pos := array_position(c.columnas, kv.key);
      if pos is not null then
        update filas set datos = jsonb_set(datos, array[(pos - 1)::text], to_jsonb(coalesce(kv.value, '')))
          where epoca = p_epoca and idx = (r->>'i')::int;
      end if;
    end loop;
  end loop;

  -- agrega las filas nuevas al final
  ini := c.n_filas;
  nn := coalesce(jsonb_array_length(p_nuevas), 0);
  if nn > 0 then
    insert into filas (epoca, idx, datos)
      select p_epoca, ini + (t.ord - 1)::int, t.valor
      from jsonb_array_elements(p_nuevas) with ordinality as t(valor, ord);
  end if;

  v := c.version + 1;
  insert into lotes (epoca, version, cliente, cambios, nuevas)
    values (p_epoca, v, p_cliente, coalesce(p_cambios, '[]'::jsonb), coalesce(p_nuevas, '[]'::jsonb));
  update compartido set version = v, n_filas = ini + nn where id = 1;

  return jsonb_build_object('version', v, 'inicio', ini, 'remotos', remotos);
end $$;

-- ---------- Traer lo que cambiaron los demás ----------
create or replace function et_cambios_traer(p_epoca text, p_desde bigint, p_cliente text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare c compartido; n int; ls jsonb;
begin
  n := et_latido(p_cliente);
  select * into c from compartido where id = 1;
  if c.epoca is distinct from p_epoca then return jsonb_build_object('reiniciar', true, 'atrasado', false); end if;
  if p_desde > c.version then return jsonb_build_object('reiniciar', true, 'atrasado', true); end if;
  select coalesce(jsonb_agg(jsonb_build_object('cambios', l.cambios, 'nuevas', l.nuevas) order by l.version), '[]'::jsonb)
    into ls from lotes l where l.epoca = p_epoca and l.version > p_desde and l.cliente is distinct from p_cliente;
  return jsonb_build_object('version', c.version, 'lotes', ls, 'clientes', n);
end $$;

-- ---------- Números de SKU sin repetir ----------
-- Reserva "p_cantidad" números seguidos para el prefijo, empezando después del mayor
-- entre lo ya reservado y "p_minimo" (el mayor número que ya existe en el archivo).
create or replace function et_reservar(p_prefijo text, p_minimo int, p_cantidad int) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u int; cant int := greatest(coalesce(p_cantidad, 1), 1);
begin
  insert into sku_contadores (prefijo, ultimo) values (p_prefijo, greatest(coalesce(p_minimo, 0), 0) + cant)
    on conflict (prefijo) do update
      set ultimo = greatest(sku_contadores.ultimo, greatest(coalesce(p_minimo, 0), 0)) + cant
    returning ultimo into u;
  return jsonb_build_object('inicio', u - cant + 1, 'cantidad', cant);
end $$;

-- ---------- Impresión remota (celular -> PC) ----------
create or replace function et_imprimir_enviar(p_trabajos jsonb) returns int
language plpgsql security definer set search_path = public as $$
begin
  insert into trabajos_impresion (trabajos) values (p_trabajos);
  delete from trabajos_impresion where creado < now() - interval '1 day';
  return jsonb_array_length(p_trabajos);
end $$;

create or replace function et_imprimir_recibir() returns jsonb
language plpgsql security definer set search_path = public as $$
declare res jsonb;
begin
  with d as (delete from trabajos_impresion returning id, trabajos)
  select coalesce(jsonb_agg(t.valor order by d.id, t.ord), '[]'::jsonb) into res
    from d, jsonb_array_elements(d.trabajos) with ordinality as t(valor, ord);
  return jsonb_build_object('trabajos', res);
end $$;

-- ---------- Plantillas compartidas ----------
create or replace function et_plantillas_listar() returns jsonb
language sql security definer set search_path = public as $$
  select coalesce(jsonb_object_agg(nombre, datos), '{}'::jsonb) from plantillas;
$$;

create or replace function et_plantilla_guardar(p_nombre text, p_datos jsonb) returns void
language sql security definer set search_path = public as $$
  insert into plantillas (nombre, datos, actualizado) values (p_nombre, p_datos, now())
    on conflict (nombre) do update set datos = excluded.datos, actualizado = now();
$$;

create or replace function et_plantilla_eliminar(p_nombre text) returns void
language sql security definer set search_path = public as $$
  delete from plantillas where nombre = p_nombre;
$$;

-- ---------- Permisos ----------
revoke all on all tables in schema public from anon, authenticated;
revoke execute on function et_latido(text) from public, anon, authenticated;
grant execute on function
  et_info(text), et_estado(), et_cargar_inicio(text, text[], text), et_cargar_filas(text, int, jsonb),
  et_cargar_fin(text, int, text), et_cambios_enviar(text, text, bigint, jsonb, jsonb),
  et_cambios_traer(text, bigint, text), et_reservar(text, int, int),
  et_imprimir_enviar(jsonb), et_imprimir_recibir(),
  et_plantillas_listar(), et_plantilla_guardar(text, jsonb), et_plantilla_eliminar(text)
to anon, authenticated;

-- Archivos grandes (miles de filas) pueden tardar más de 3 s en leerse completos.
alter role anon set statement_timeout = '60s';
alter role authenticated set statement_timeout = '60s';
notify pgrst, 'reload config';
