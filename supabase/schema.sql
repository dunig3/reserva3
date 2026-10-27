-- =====================================================================
-- Vendedor Automático · Esquema Supabase (proyecto dunig3)
-- Todo lleva prefijo va_ para NO tocar las tablas de la otra app.
-- Idempotente en lo posible: se puede volver a ejecutar.
-- Requiere: pgcrypto, pg_cron, pg_net, supabase_vault. (pg_net se instaló para borrar imágenes vía API de Storage.)
-- =====================================================================
create extension if not exists pgcrypto with schema extensions;
create extension if not exists pg_net;

-- ---------------------------------------------------------------------
-- 1) TABLAS (tipos compactos para ahorrar espacio)
-- ---------------------------------------------------------------------
-- Datos públicos del negocio (se muestran en la tienda)
create table if not exists va_negocios(
  slug      text primary key check (slug ~ '^[a-z0-9-]{2,30}$'),
  nombre    varchar(60)  not null,
  lema      varchar(120) not null default '',
  emoji     varchar(8)   not null default '🛍️',
  hero      varchar(120) not null default '',           -- ruta en el bucket (p/<slug>/xxx.webp)
  comision  numeric(5,2) not null default 10 check (comision between 0 and 90),
  auto_resp boolean      not null default true,          -- respuesta automática de demo
  creado    timestamptz  not null default now()
);
-- Datos privados del negocio (nunca visibles para anon)
create table if not exists va_negocio_priv(
  biz      text primary key references va_negocios(slug) on delete cascade,
  pin_hash text not null,                                -- crypt(pin, gen_salt('bf'))
  sig_cod  int  not null default 1001                    -- siguiente número de pedido
);
create table if not exists va_cuentas(                   -- métodos de pago del negocio (públicos)
  biz    text not null references va_negocios(slug) on delete cascade,
  id     varchar(30) not null,
  nombre varchar(40) not null,
  activo boolean not null default true,
  campos jsonb not null default '{}'::jsonb,
  orden  smallint not null default 0,
  primary key (biz, id)
);
create table if not exists va_productos(
  id     bigint generated always as identity primary key,
  biz    text not null references va_negocios(slug) on delete cascade,
  n      varchar(80)  not null,
  d      varchar(160) not null default '',
  p      numeric(10,2) not null check (p > 0 and p < 100000),
  img    varchar(120) not null default '',
  orden  smallint not null default 0,
  activo boolean not null default true,
  creado timestamptz not null default now()
);
create index if not exists va_productos_biz on va_productos(biz, orden);

create table if not exists va_vendedores(                -- promotores (privado: lleva pin_hash)
  biz      text not null references va_negocios(slug) on delete cascade,
  cod      varchar(12) not null check (cod ~ '^[A-Z0-9]{2,12}$'),
  n        varchar(40) not null,
  pin_hash text not null,
  activo   boolean not null default true,
  creado   timestamptz not null default now(),
  primary key (biz, cod)
);
create table if not exists va_pedidos(
  id          bigint generated always as identity primary key,
  biz         text not null references va_negocios(slug) on delete cascade,
  cod         varchar(10) not null,                    -- '#1001'
  cliente_id  uuid not null,                           -- id aleatorio secreto del cliente
  cliente_nom varchar(60) not null,
  cliente_tel varchar(30) not null default '',
  cliente_dir varchar(160) not null default '',
  items       jsonb not null,                          -- [{n,p,q}] copia al momento de pedir
  total       numeric(10,2) not null,
  pago        varchar(40) not null,
  ref_pago    varchar(40) not null default '',
  pago_estado varchar(15) not null default 'por verificar',
  ref         varchar(12),                             -- código del promotor que refirió
  estado      varchar(12) not null default 'nuevo',
  recibo      char(6),
  directa     boolean not null default false,
  comprobante varchar(120),                            -- foto del pago (se borra a los 30 días)
  liquidado   timestamptz,
  t           timestamptz not null default now(),
  act         timestamptz not null default now(),      -- última modificación (sincronización)
  unique (biz, cod)
);
create index if not exists va_pedidos_biz_act on va_pedidos(biz, act);
create index if not exists va_pedidos_cliente on va_pedidos(cliente_id);

create table if not exists va_mensajes(
  id         bigint generated always as identity primary key,
  biz        text not null references va_negocios(slug) on delete cascade,
  cliente_id uuid not null,
  de_negocio boolean not null,
  texto      varchar(1000) not null,
  pedido     varchar(10),
  nom        varchar(60),
  leido      boolean not null default false,
  t          timestamptz not null default now()
);
create index if not exists va_mensajes_biz_id on va_mensajes(biz, id);
create index if not exists va_mensajes_cliente on va_mensajes(cliente_id, id);

create table if not exists va_recibos(                   -- códigos de cobro en efectivo (6 dígitos)
  id    bigint generated always as identity primary key,
  biz   text not null references va_negocios(slug) on delete cascade,
  prom  varchar(12) not null,
  k     char(6) not null,
  monto numeric(10,2) not null,
  usado varchar(10),
  t     timestamptz not null default now()
);
create index if not exists va_recibos_biz_k on va_recibos(biz, k);

create table if not exists va_resumen(                   -- agregados de pedidos cobrados ya purgados
  biz     text not null references va_negocios(slug) on delete cascade,
  mes     date not null,
  ref     varchar(12) not null default '',
  pedidos int not null default 0,
  total   numeric(12,2) not null default 0,
  primary key (biz, mes, ref)
);
create table if not exists va_sesiones(                  -- sesiones cortas del panel / promotor
  token_hash bytea primary key,
  biz    text not null references va_negocios(slug) on delete cascade,
  rol    char(1) not null check (rol in ('d','v')),      -- d = dueño, v = vendedor
  cod    varchar(12),
  expira timestamptz not null
);
create table if not exists va_limites(                   -- contador anti-spam (ventanas)
  k     text primary key,
  n     int not null,
  desde timestamptz not null
);
create table if not exists va_tickets(                   -- permisos de subida de una sola imagen
  ticket text primary key,
  biz    text not null,
  tipo   char(1) not null check (tipo in ('p','r')),     -- p = producto/portada, r = comprobante
  expira timestamptz not null
);

-- ---------------------------------------------------------------------
-- 2) SEGURIDAD: RLS en todo + permisos mínimos
-- ---------------------------------------------------------------------
do $$ declare t text; begin
  foreach t in array array['va_negocios','va_negocio_priv','va_cuentas','va_productos','va_vendedores','va_pedidos',
    'va_mensajes','va_recibos','va_resumen','va_sesiones','va_limites','va_tickets'] loop
    execute format('alter table %I enable row level security', t);
    execute format('revoke all on %I from anon, authenticated', t);
  end loop;
end $$;
-- Solo lectura pública del catálogo
grant select on va_negocios, va_productos, va_cuentas to anon, authenticated;
drop policy if exists va_neg_leer on va_negocios;
create policy va_neg_leer on va_negocios for select to anon, authenticated using (true);
drop policy if exists va_prod_leer on va_productos;
create policy va_prod_leer on va_productos for select to anon, authenticated using (activo);
drop policy if exists va_cta_leer on va_cuentas;
create policy va_cta_leer on va_cuentas for select to anon, authenticated using (true);
-- El resto de tablas NO tiene políticas: solo se tocan vía funciones SECURITY DEFINER.

-- ---------------------------------------------------------------------
-- 3) FUNCIONES INTERNAS (no ejecutables por anon)
-- ---------------------------------------------------------------------
-- IP del cliente (encabezados que añade la pasarela de Supabase)
create or replace function va_ip() returns text language sql stable as $$
  select coalesce(
    nullif(current_setting('request.headers', true), '')::json->>'cf-connecting-ip',
    split_part(nullif(current_setting('request.headers', true), '')::json->>'x-forwarded-for', ',', 1),
    nullif(current_setting('request.headers', true), '')::json->>'x-real-ip',
    'sin-ip')
$$;

-- Limitador: máximo p_max acciones por ventana; si se pasa, error
create or replace function va_limite(p_k text, p_max int, p_ventana interval) returns void
language plpgsql security definer set search_path = public as $$
declare c int;
begin
  insert into va_limites(k, n, desde) values (p_k, 1, now())
  on conflict (k) do update set
    n     = case when va_limites.desde < now() - p_ventana then 1 else va_limites.n + 1 end,
    desde = case when va_limites.desde < now() - p_ventana then now() else va_limites.desde end
  returning n into c;
  if c > p_max then raise exception 'Demasiadas solicitudes. Espera unos minutos e intenta de nuevo.'; end if;
end $$;

-- Limpia y valida texto (recorta, quita caracteres de control, controla largo)
create or replace function va_txt(p text, p_max int, p_req boolean default false, p_campo text default 'texto')
returns text language plpgsql immutable as $$
declare s text := btrim(regexp_replace(coalesce(p, ''), '[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]', '', 'g'));
begin
  if p_req and s = '' then raise exception 'Falta %', p_campo; end if;
  if char_length(s) > p_max then raise exception 'El campo % es muy largo (máx. %)', p_campo, p_max; end if;
  return s;
end $$;

-- Valida una sesión y devuelve (biz, cod)
create or replace function va_sesion(p_token text, p_rol char, out biz text, out cod text)
language plpgsql security definer set search_path = public, extensions as $$
begin
  select s.biz, s.cod into biz, cod from va_sesiones s
   where s.token_hash = digest(coalesce(p_token, ''), 'sha256') and s.rol = p_rol and s.expira > now();
  if biz is null then raise exception 'Sesión vencida. Vuelve a entrar con tu PIN.'; end if;
end $$;

create or replace function va_nueva_sesion(p_biz text, p_rol char, p_cod text) returns text
language plpgsql security definer set search_path = public, extensions as $$
declare tok text := encode(gen_random_bytes(24), 'hex');
begin
  insert into va_sesiones(token_hash, biz, rol, cod, expira)
  values (digest(tok, 'sha256'), p_biz, p_rol, p_cod, now() + interval '12 hours');
  return tok;
end $$;

-- Aviso en tiempo real (Broadcast). No lleva datos personales: solo "hay cambios".
create or replace function va_aviso(p_biz text, p_cliente uuid, p_k text) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform realtime.send(jsonb_build_object('k', p_k), 'va', 'va:b:' || p_biz, false);
  if p_cliente is not null then
    perform realtime.send(jsonb_build_object('k', p_k), 'va', 'va:c:' || p_cliente::text, false);
  end if;
exception when others then null;  -- si Realtime falla, el sondeo ligero del cliente lo cubre
end $$;

create or replace function va_trg_aviso() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if tg_table_name = 'va_pedidos' then
    if tg_op = 'UPDATE' then new.act := now(); end if;
    perform va_aviso(new.biz, new.cliente_id, 'p');
  elsif tg_table_name = 'va_mensajes' then
    perform va_aviso(new.biz, new.cliente_id, 'm');
  else
    perform va_aviso(new.biz, null, 'r');
  end if;
  return new;
end $$;
drop trigger if exists va_pedidos_aviso on va_pedidos;
create trigger va_pedidos_aviso before insert or update on va_pedidos for each row execute function va_trg_aviso();
drop trigger if exists va_mensajes_aviso on va_mensajes;
create trigger va_mensajes_aviso after insert on va_mensajes for each row execute function va_trg_aviso();
drop trigger if exists va_recibos_aviso on va_recibos;
create trigger va_recibos_aviso after insert or update on va_recibos for each row execute function va_trg_aviso();

-- Borra archivos del bucket usando la API de Storage (vía pg_net + clave en Vault, solo en servidor)
create or replace function va_borrar_storage(p_paths text[]) returns void
language plpgsql security definer set search_path = public, extensions as $$
declare k text;
begin
  p_paths := array(select x from unnest(p_paths) x where x ~ '^[pr]/[a-z0-9-]+/[A-Za-z0-9._-]+$');
  if coalesce(array_length(p_paths, 1), 0) = 0 then return; end if;
  select decrypted_secret into k from vault.decrypted_secrets where name = 'va_service_key';
  if k is null then return; end if;
  perform net.http_delete(
    url := 'https://xcaasrvlpyxfjeyqhyve.supabase.co/storage/v1/object/va-imagenes',
    headers := jsonb_build_object('apikey', k, 'Authorization', 'Bearer ' || k, 'Content-Type', 'application/json'),
    body := jsonb_build_object('prefixes', to_jsonb(p_paths)));
end $$;

-- ¿El nombre del archivo corresponde a un ticket de subida válido? (lo usa la política de Storage)
create or replace function va_ticket_ok(p_name text) returns boolean
language sql stable security definer set search_path = public as $$
  select p_name ~ '^[pr]/[a-z0-9-]+/[a-f0-9]{24}\.(webp|jpg)$' and exists(
    select 1 from va_tickets t
     where t.ticket = split_part(split_part(p_name, '/', 3), '.', 1)
       and t.tipo = split_part(p_name, '/', 1) and t.biz = split_part(p_name, '/', 2) and t.expira > now())
$$;
create or replace function va_nuevo_ticket(p_biz text, p_tipo char) returns text
language plpgsql security definer set search_path = public, extensions as $$
declare tk text := encode(gen_random_bytes(12), 'hex');
begin
  insert into va_tickets values (tk, p_biz, p_tipo, now() + interval '15 minutes');
  return p_tipo || '/' || p_biz || '/' || tk;   -- el cliente le añade .webp o .jpg
end $$;

-- Formatos JSON iguales a los que usaba la demo (para cambiar poco las páginas)
create or replace function va_ms(t timestamptz) returns bigint language sql immutable as $$ select (extract(epoch from t) * 1000)::bigint $$;
create or replace function va_j_pedido(p va_pedidos) returns jsonb language sql stable as $$
  select jsonb_build_object('cod', p.cod, 'biz', p.biz,
    'cliente', jsonb_build_object('id', p.cliente_id, 'nombre', p.cliente_nom, 'tel', p.cliente_tel, 'dir', p.cliente_dir),
    'items', p.items, 'total', p.total, 'pago', p.pago, 'refPago', p.ref_pago, 'pagoEstado', p.pago_estado,
    'ref', p.ref, 'estado', p.estado, 'recibo', p.recibo, 'directa', p.directa, 'comprobante', p.comprobante,
    'liquidado', va_ms(p.liquidado), 't', va_ms(p.t), 'act', va_ms(p.act))
$$;
create or replace function va_j_msg(m va_mensajes) returns jsonb language sql stable as $$
  select jsonb_build_object('id', m.id, 'biz', m.biz,
    'de', case when m.de_negocio then 'negocio' else m.cliente_id::text end,
    'para', case when m.de_negocio then m.cliente_id::text else 'negocio' end,
    'texto', m.texto, 'pedido', m.pedido, 'nom', m.nom, 't', va_ms(m.t), 'leido', m.leido)
$$;

-- Ranking de vendedores (pedidos cobrados + agregados históricos)
create or replace function va_ranking(p_biz text) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(x order by x.ven desc), '[]'::jsonb) from (
    select v.cod, v.n,
      coalesce((select count(*) from va_pedidos p where p.biz = v.biz and p.ref = v.cod and p.estado = 'cobrado'), 0)
        + coalesce((select sum(r.pedidos) from va_resumen r where r.biz = v.biz and r.ref = v.cod), 0) as cant,
      coalesce((select sum(total) from va_pedidos p where p.biz = v.biz and p.ref = v.cod and p.estado = 'cobrado'), 0)
        + coalesce((select sum(r.total) from va_resumen r where r.biz = v.biz and r.ref = v.cod), 0) as ven
    from va_vendedores v where v.biz = p_biz and v.activo) x
$$;

-- Uso del plan gratis (BD y Storage)
create or replace function va_uso() returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'db_mb', round(pg_database_size(current_database()) / 1048576.0, 1),
    'db_limite_mb', 500,
    'storage_mb', round(coalesce((select sum((metadata->>'size')::bigint) from storage.objects), 0) / 1048576.0, 2),
    'storage_va_mb', round(coalesce((select sum((metadata->>'size')::bigint) from storage.objects where bucket_id = 'va-imagenes'), 0) / 1048576.0, 2),
    'storage_limite_mb', 1024,
    'va_mb', round((select sum(pg_total_relation_size(c.oid)) from pg_class c join pg_namespace n on n.oid = c.relnamespace
                     where n.nspname = 'public' and c.relkind = 'r' and c.relname like 'va\_%') / 1048576.0, 2),
    'filas', jsonb_build_object(
      'pedidos', (select count(*) from va_pedidos), 'mensajes', (select count(*) from va_mensajes),
      'productos', (select count(*) from va_productos), 'imagenes', (select count(*) from storage.objects where bucket_id = 'va-imagenes')))
$$;

-- ---------------------------------------------------------------------
-- 4) RPC PÚBLICAS · TIENDA (cliente)
-- ---------------------------------------------------------------------
create or replace function va_crear_pedido(
  p_biz text, p_cliente uuid, p_nombre text, p_tel text, p_dir text, p_items jsonb,
  p_cuenta text, p_ref_pago text default '', p_promo text default null, p_cobro text default null,
  p_ref text default null, p_comprobante boolean default false)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare
  nom text; tel text; dir text;
  cta va_cuentas; neg va_negocios; v_prom va_vendedores; v_rec va_recibos;
  its jsonb := '[]'::jsonb; tot numeric(10,2) := 0; x jsonb; pr va_productos; qn int;
  codigo text; refp text; refv text; pagon text; tk text := null; ef boolean;
begin
  if p_cliente is null then raise exception 'Cliente inválido'; end if;
  select * into neg from va_negocios where slug = p_biz;
  if neg.slug is null then raise exception 'Negocio no existe'; end if;
  perform va_limite('ped:ip:' || va_ip(), 8, interval '10 minutes');
  perform va_limite('ped:cl:' || p_cliente, 6, interval '10 minutes');
  perform va_limite('ped:biz:' || p_biz, 300, interval '1 hour');
  if p_cuenta = 'efectivo' then perform va_limite('cobrotry:' || p_biz, 60, interval '10 minutes'); end if;
  -- Desde aquí, los errores de validación se devuelven como {error} para que los contadores anti-spam
  -- (incluido el de intentos de código de cobro) queden guardados y no se pueda adivinar por fuerza bruta.
  begin
  nom := va_txt(p_nombre, 60, true, 'nombre'); tel := va_txt(p_tel, 30, true, 'teléfono'); dir := va_txt(p_dir, 160, true, 'dirección');
  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) not between 1 and 30 then raise exception 'Carrito inválido'; end if;
  -- El precio SIEMPRE sale del catálogo del servidor (no del navegador)
  for x in select * from jsonb_array_elements(p_items) loop
    if coalesce(x->>'id', '') !~ '^\d{1,12}$' or coalesce(x->>'q', '') !~ '^\d{1,2}$' then raise exception 'Producto inválido'; end if;
    qn := (x->>'q')::int; if qn < 1 then raise exception 'Cantidad inválida'; end if;
    select * into pr from va_productos where id = (x->>'id')::bigint and biz = p_biz and activo;
    if pr.id is null then raise exception 'Un producto ya no está disponible. Recarga la página.'; end if;
    its := its || jsonb_build_object('n', pr.n, 'p', pr.p, 'q', qn);
    tot := tot + pr.p * qn;
  end loop;
  select * into cta from va_cuentas where biz = p_biz and id = p_cuenta and activo;
  if cta.id is null then raise exception 'Selecciona un método de pago'; end if;
  pagon := cta.nombre; ef := cta.id = 'efectivo';
  refv := upper(left(regexp_replace(coalesce(p_ref, ''), '[^A-Za-z0-9]', '', 'g'), 12));
  if refv <> '' and not exists(select 1 from va_vendedores where biz = p_biz and cod = refv and activo) then refv := null; end if;
  if refv = '' then refv := null; end if;
  -- número de pedido consecutivo por negocio
  update va_negocio_priv set sig_cod = sig_cod + 1 where biz = p_biz returning '#' || (sig_cod - 1) into codigo;
  if ef then
    select * into v_prom from va_vendedores where biz = p_biz and cod = upper(left(btrim(coalesce(p_promo, '')), 12)) and activo;
    if v_prom.cod is null then raise exception 'Ese código de promotor no existe'; end if;
    if coalesce(p_cobro, '') !~ '^\d{6}$' then raise exception 'Escribe el código de cobro de 6 dígitos'; end if;
    select * into v_rec from va_recibos r where r.biz = p_biz and r.prom = v_prom.cod and r.k = p_cobro order by r.t desc limit 1 for update;
    if v_rec.id is null then raise exception 'Código de cobro inválido para ese promotor'; end if;
    if v_rec.usado is not null then raise exception 'Ese código de cobro ya fue usado'; end if;
    if v_rec.t < now() - interval '30 minutes' then raise exception 'El código de cobro venció. Pide uno nuevo al promotor'; end if;
    if abs(v_rec.monto - tot) > 0.009 then raise exception 'El cobro registrado es de $% y tu pedido es de $%', to_char(v_rec.monto, 'FM999990.00'), to_char(tot, 'FM999990.00'); end if;
    update va_recibos set usado = codigo where id = v_rec.id;
    refp := v_prom.cod; refv := v_prom.cod;
  else
    refp := va_txt(p_ref_pago, 40, true, 'número de referencia');
  end if;
  insert into va_pedidos(biz, cod, cliente_id, cliente_nom, cliente_tel, cliente_dir, items, total, pago, ref_pago, ref, recibo)
  values (p_biz, codigo, p_cliente, nom, tel, dir, its, tot, pagon, refp, refv, case when ef then v_rec.k end);
  insert into va_mensajes(biz, cliente_id, de_negocio, texto, pedido, nom) values (p_biz, p_cliente, false,
    format('Hola, hice el pedido %s por $%s. Pago: %s%s.', codigo, to_char(tot, 'FM999990.00'), pagon,
      case when ef then ' al promotor ' || v_prom.n || ' (' || v_prom.cod || ')' else ' · Ref. ' || refp end), codigo, nom);
  if neg.auto_resp then
    insert into va_mensajes(biz, cliente_id, de_negocio, texto, pedido) values (p_biz, p_cliente, true,
      format('¡Gracias %s! Recibimos tu pedido %s. %s 🙌', nom, codigo,
        case when ef then 'Estamos confirmando con tu promotor' else 'Estamos verificando tu pago' end), codigo);
  end if;
  if p_comprobante and not ef then tk := va_nuevo_ticket(p_biz, 'r'); end if;
  return jsonb_build_object('cod', codigo, 'total', tot, 'subida', tk);
  exception when raise_exception then
    return jsonb_build_object('error', sqlerrm);
  end;
end $$;

-- Adjunta la foto del comprobante (después de subirla con el ticket)
create or replace function va_adjuntar_comprobante(p_biz text, p_cliente uuid, p_cod text, p_path text) returns boolean
language plpgsql security definer set search_path = public as $$
begin
  if p_path !~ ('^r/' || p_biz || '/[a-f0-9]{24}\.(webp|jpg)$') then raise exception 'Archivo inválido'; end if;
  if not exists(select 1 from storage.objects where bucket_id = 'va-imagenes' and name = p_path) then raise exception 'El archivo no se subió'; end if;
  update va_pedidos set comprobante = p_path where biz = p_biz and cod = p_cod and cliente_id = p_cliente and comprobante is null;
  return found;
end $$;

create or replace function va_cliente_enviar(p_biz text, p_cliente uuid, p_nombre text, p_texto text) returns boolean
language plpgsql security definer set search_path = public as $$
declare txt text := va_txt(p_texto, 1000, true, 'mensaje'); nom text := va_txt(p_nombre, 60, true, 'nombre'); auto boolean;
begin
  if p_cliente is null then raise exception 'Cliente inválido'; end if;
  select auto_resp into auto from va_negocios where slug = p_biz;
  if auto is null then raise exception 'Negocio no existe'; end if;
  perform va_limite('msg:ip:' || va_ip(), 30, interval '5 minutes');
  perform va_limite('msg:cl:' || p_cliente, 20, interval '5 minutes');
  perform va_limite('msg:biz:' || p_biz, 1000, interval '1 hour');
  insert into va_mensajes(biz, cliente_id, de_negocio, texto, nom) values (p_biz, p_cliente, false, txt, nom);
  if auto then
    insert into va_mensajes(biz, cliente_id, de_negocio, texto) values (p_biz, p_cliente, true, 'Recibido 👍 Ya te atendemos. (respuesta automática)');
  end if;
  return true;
end $$;

-- El cliente trae SOLO su chat y sus pedidos (su id es un UUID secreto guardado en su teléfono)
create or replace function va_cliente_sync(p_biz text, p_cliente uuid, p_desde bigint default 0, p_leer boolean default false) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r jsonb;
begin
  if p_leer then
    update va_mensajes set leido = true where biz = p_biz and cliente_id = p_cliente and de_negocio and not leido;
  end if;
  select jsonb_build_object(
    'mensajes', coalesce((select jsonb_agg(va_j_msg(m) order by m.id) from (
       select * from va_mensajes where biz = p_biz and cliente_id = p_cliente and id > coalesce(p_desde, 0)
        order by id desc limit 300) m), '[]'::jsonb),
    'pedidos', coalesce((select jsonb_agg(jsonb_build_object('cod', p.cod, 'estado', p.estado, 'pagoEstado', p.pago_estado,
       'total', p.total, 't', va_ms(p.t)) order by p.id desc) from (
       select * from va_pedidos where biz = p_biz and cliente_id = p_cliente order by id desc limit 10) p), '[]'::jsonb))
  into r;
  return r;
end $$;

-- ---------------------------------------------------------------------
-- 5) RPC · PANEL DEL DUEÑO (PIN -> token de 12 h)
-- ---------------------------------------------------------------------
create or replace function va_login_panel(p_biz text, p_pin text) returns text
language plpgsql security definer set search_path = public, extensions as $$
declare h text;
begin
  perform va_limite('login:ip:' || va_ip(), 20, interval '15 minutes');
  if coalesce((select n from va_limites where k = 'loginfail:' || p_biz and desde > now() - interval '15 minutes'), 0) >= 15 then
    raise exception 'Demasiados intentos fallidos. Espera 15 minutos.';
  end if;
  select pin_hash into h from va_negocio_priv where biz = p_biz;
  if h is null or crypt(coalesce(p_pin, ''), h) <> h then
    insert into va_limites values ('loginfail:' || p_biz, 1, now()) on conflict (k) do update
      set n = case when va_limites.desde < now() - interval '15 minutes' then 1 else va_limites.n + 1 end,
          desde = case when va_limites.desde < now() - interval '15 minutes' then now() else va_limites.desde end;
    return null;  -- PIN incorrecto (no se usa excepción para que el contador quede guardado)
  end if;
  return va_nueva_sesion(p_biz, 'd', null);
end $$;

create or replace function va_logout(p_token text) returns void
language sql security definer set search_path = public, extensions as $$
  delete from va_sesiones where token_hash = digest(coalesce(p_token, ''), 'sha256')
$$;

-- Datos del panel: carga inicial (p_desde null) o solo cambios desde p_desde / p_desde_msg
create or replace function va_panel_datos(p_token text, p_desde bigint default null, p_desde_msg bigint default 0) returns jsonb
language plpgsql security definer set search_path = public as $$
declare s record; r jsonb;
begin
  s := va_sesion(p_token, 'd');
  select jsonb_build_object(
    'ahora', va_ms(now()),
    'negocio', (select to_jsonb(n) from va_negocios n where slug = s.biz),
    'vendedores', coalesce((select jsonb_agg(jsonb_build_object('cod', cod, 'n', n) order by creado) from va_vendedores where biz = s.biz and activo), '[]'::jsonb),
    'pedidos', coalesce((select jsonb_agg(va_j_pedido(p) order by p.id) from (
        select * from va_pedidos where biz = s.biz
           and (p_desde is null or act > to_timestamp(p_desde / 1000.0) - interval '2 seconds')
         order by id desc limit 500) p), '[]'::jsonb),
    'mensajes', coalesce((select jsonb_agg(va_j_msg(m) order by m.id) from (
        select * from va_mensajes where biz = s.biz and id > coalesce(p_desde_msg, 0) order by id desc limit 1500) m), '[]'::jsonb),
    'resumen', case when p_desde is null then coalesce((select jsonb_agg(to_jsonb(x)) from va_resumen x where biz = s.biz), '[]'::jsonb) end)
  into r;
  return r;
end $$;

create or replace function va_panel_leido(p_token text, p_cliente uuid) returns void
language plpgsql security definer set search_path = public as $$
declare s record;
begin
  s := va_sesion(p_token, 'd');
  update va_mensajes set leido = true where biz = s.biz and cliente_id = p_cliente and not de_negocio and not leido;
end $$;

create or replace function va_panel_enviar(p_token text, p_cliente uuid, p_texto text, p_pedido text default null) returns boolean
language plpgsql security definer set search_path = public as $$
declare s record;
begin
  s := va_sesion(p_token, 'd');
  perform va_limite('pmsg:' || s.biz, 300, interval '10 minutes');
  insert into va_mensajes(biz, cliente_id, de_negocio, texto, pedido)
  values (s.biz, p_cliente, true, va_txt(p_texto, 1000, true, 'mensaje'), va_txt(p_pedido, 10));
  return true;
end $$;

-- Cambia el estado de un pedido y (opcional) avisa al cliente por el chat
create or replace function va_panel_pedido(p_token text, p_cod text, p_estado text, p_pago_estado text default null, p_msg text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare s record; p va_pedidos;
begin
  s := va_sesion(p_token, 'd');
  if p_estado not in ('nuevo', 'confirmado', 'entregado', 'cobrado', 'rechazado') then raise exception 'Estado inválido'; end if;
  if p_pago_estado is not null and p_pago_estado not in ('por verificar', 'verificado', 'rechazado') then raise exception 'Estado de pago inválido'; end if;
  update va_pedidos set estado = p_estado, pago_estado = coalesce(p_pago_estado, pago_estado)
   where biz = s.biz and cod = p_cod returning * into p;
  if p.id is null then raise exception 'Pedido no encontrado'; end if;
  if coalesce(p_msg, '') <> '' then
    insert into va_mensajes(biz, cliente_id, de_negocio, texto, pedido) values (s.biz, p.cliente_id, true, va_txt(p_msg, 1000), p.cod);
  end if;
  return va_j_pedido(p);
end $$;

create or replace function va_panel_liquidar(p_token text, p_vend text) returns int
language plpgsql security definer set search_path = public as $$
declare s record; c int;
begin
  s := va_sesion(p_token, 'd');
  update va_pedidos set liquidado = now()
   where biz = s.biz and ref = p_vend and pago ilike '%efectivo%' and pago_estado = 'verificado' and estado <> 'rechazado' and liquidado is null;
  get diagnostics c = row_count; return c;
end $$;

create or replace function va_panel_negocio(p_token text, p_nombre text, p_lema text, p_comision numeric, p_auto boolean,
  p_pin_nuevo text default null, p_hero text default null) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare s record; viejo text; r va_negocios;
begin
  s := va_sesion(p_token, 'd');
  if p_comision is null or p_comision < 0 or p_comision > 90 then raise exception 'Comisión entre 0 y 90'; end if;
  if p_hero is not null and p_hero !~ ('^p/' || s.biz || '/[a-f0-9]{24}\.(webp|jpg)$') then raise exception 'Imagen inválida'; end if;
  select hero into viejo from va_negocios where slug = s.biz;
  update va_negocios set nombre = va_txt(p_nombre, 60, true, 'nombre'), lema = va_txt(p_lema, 120),
         comision = round(p_comision, 2), auto_resp = coalesce(p_auto, auto_resp), hero = coalesce(p_hero, hero)
   where slug = s.biz returning * into r;
  if p_hero is not null and viejo is distinct from p_hero then perform va_borrar_storage(array[viejo]); end if;
  if coalesce(p_pin_nuevo, '') <> '' then
    if p_pin_nuevo !~ '^\d{4,6}$' then raise exception 'El PIN debe tener de 4 a 6 dígitos'; end if;
    update va_negocio_priv set pin_hash = crypt(p_pin_nuevo, gen_salt('bf', 8)) where biz = s.biz;
  end if;
  return to_jsonb(r);
end $$;

create or replace function va_panel_cuenta(p_token text, p_id text, p_activo boolean, p_campos jsonb default null) returns boolean
language plpgsql security definer set search_path = public as $$
declare s record; k text; v text;
begin
  s := va_sesion(p_token, 'd');
  if p_campos is not null then
    if jsonb_typeof(p_campos) <> 'object' or (select count(*) from jsonb_object_keys(p_campos)) > 10 then raise exception 'Datos inválidos'; end if;
    for k, v in select * from jsonb_each_text(p_campos) loop perform va_txt(k, 30); perform va_txt(v, 100); end loop;
  end if;
  update va_cuentas set activo = coalesce(p_activo, activo), campos = coalesce(p_campos, campos) where biz = s.biz and id = p_id;
  return found;
end $$;

-- Crea o edita producto. p_img = nueva ruta subida con ticket (o null para dejar la actual)
create or replace function va_panel_producto(p_token text, p_id bigint, p_n text, p_d text, p_p numeric, p_img text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare s record; pr va_productos; viejo text;
begin
  s := va_sesion(p_token, 'd');
  if p_p is null or p_p <= 0 or p_p >= 100000 then raise exception 'Precio inválido'; end if;
  if p_img is not null and p_img !~ ('^p/' || s.biz || '/[a-f0-9]{24}\.(webp|jpg)$') then raise exception 'Imagen inválida'; end if;
  if p_id is null then
    if (select count(*) from va_productos where biz = s.biz) >= 200 then raise exception 'Máximo 200 productos por negocio'; end if;
    insert into va_productos(biz, n, d, p, img, orden)
    values (s.biz, va_txt(p_n, 80, true, 'nombre'), va_txt(p_d, 160), round(p_p, 2), coalesce(p_img, ''),
            coalesce((select max(orden) + 1 from va_productos where biz = s.biz), 0))
    returning * into pr;
  else
    select img into viejo from va_productos where id = p_id and biz = s.biz;
    update va_productos set n = va_txt(p_n, 80, true, 'nombre'), d = va_txt(p_d, 160), p = round(p_p, 2), img = coalesce(p_img, img)
     where id = p_id and biz = s.biz returning * into pr;
    if pr.id is null then raise exception 'Producto no encontrado'; end if;
    if p_img is not null and viejo is distinct from p_img then perform va_borrar_storage(array[viejo]); end if;  -- borra la foto vieja
  end if;
  return to_jsonb(pr);
end $$;

create or replace function va_panel_producto_borrar(p_token text, p_id bigint) returns boolean
language plpgsql security definer set search_path = public as $$
declare s record; viejo text;
begin
  s := va_sesion(p_token, 'd');
  delete from va_productos where id = p_id and biz = s.biz returning img into viejo;
  if viejo is null then return false; end if;
  perform va_borrar_storage(array[viejo]);   -- también borra su foto del bucket
  return true;
end $$;

create or replace function va_panel_vendedor(p_token text, p_cod text, p_n text, p_pin text) returns boolean
language plpgsql security definer set search_path = public, extensions as $$
declare s record; c text := upper(regexp_replace(coalesce(p_cod, ''), '[^A-Za-z0-9]', '', 'g'));
begin
  s := va_sesion(p_token, 'd');
  if c !~ '^[A-Z0-9]{2,12}$' then raise exception 'Código de 2 a 12 letras o números'; end if;
  if coalesce(p_pin, '') !~ '^\d{4,6}$' then raise exception 'El PIN debe tener de 4 a 6 dígitos'; end if;
  if exists(select 1 from va_vendedores where biz = s.biz and cod = c) then raise exception 'Ese código ya existe'; end if;
  if (select count(*) from va_vendedores where biz = s.biz) >= 100 then raise exception 'Máximo 100 vendedores'; end if;
  insert into va_vendedores(biz, cod, n, pin_hash) values (s.biz, c, va_txt(p_n, 40, true, 'nombre'), crypt(p_pin, gen_salt('bf', 8)));
  return true;
end $$;

-- Ticket para subir 1 imagen (producto o portada) durante 15 min
create or replace function va_panel_ticket(p_token text) returns text
language plpgsql security definer set search_path = public as $$
declare s record;
begin
  s := va_sesion(p_token, 'd');
  perform va_limite('tk:' || s.biz, 60, interval '1 hour');
  return va_nuevo_ticket(s.biz, 'p');
end $$;

create or replace function va_panel_uso(p_token text) returns jsonb
language plpgsql security definer set search_path = public as $$
begin perform va_sesion(p_token, 'd'); return va_uso(); end $$;

-- ---------------------------------------------------------------------
-- 6) RPC · APP DEL PROMOTOR (código + PIN -> token de 12 h)
-- ---------------------------------------------------------------------
create or replace function va_login_vendedor(p_biz text, p_cod text, p_pin text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare v va_vendedores; c text := upper(coalesce(p_cod, ''));
begin
  perform va_limite('login:ip:' || va_ip(), 20, interval '15 minutes');
  if coalesce((select n from va_limites where k = 'vfail:' || p_biz || ':' || c and desde > now() - interval '15 minutes'), 0) >= 10 then
    raise exception 'Demasiados intentos fallidos. Espera 15 minutos.';
  end if;
  select * into v from va_vendedores where biz = p_biz and cod = c and activo;
  if v.cod is null or crypt(coalesce(p_pin, ''), v.pin_hash) <> v.pin_hash then
    insert into va_limites values ('vfail:' || p_biz || ':' || c, 1, now()) on conflict (k) do update
      set n = case when va_limites.desde < now() - interval '15 minutes' then 1 else va_limites.n + 1 end,
          desde = case when va_limites.desde < now() - interval '15 minutes' then now() else va_limites.desde end;
    return null;
  end if;
  return jsonb_build_object('token', va_nueva_sesion(p_biz, 'v', v.cod), 'cod', v.cod, 'n', v.n);
end $$;

create or replace function va_promotor_datos(p_token text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare s record; r jsonb;
begin
  s := va_sesion(p_token, 'v');
  select jsonb_build_object(
    'ahora', va_ms(now()),
    'yo', (select jsonb_build_object('cod', cod, 'n', n) from va_vendedores where biz = s.biz and cod = s.cod),
    'comision', (select comision from va_negocios where slug = s.biz),
    'ranking', va_ranking(s.biz),
    'recibos', coalesce((select jsonb_agg(jsonb_build_object('k', k, 'monto', monto, 't', va_ms(t), 'usado', usado) order by id desc) from (
        select * from va_recibos where biz = s.biz and prom = s.cod order by id desc limit 5) x), '[]'::jsonb),
    'caja', coalesce((select sum(total) from va_pedidos where biz = s.biz and ref = s.cod and pago ilike '%efectivo%'
        and pago_estado = 'verificado' and estado <> 'rechazado' and liquidado is null), 0),
    -- solo sus pedidos y sin teléfono/dirección del cliente
    'pedidos', coalesce((select jsonb_agg(jsonb_build_object('cod', cod, 'cliente', jsonb_build_object('nombre', cliente_nom),
        'estado', estado, 'total', total, 't', va_ms(t)) order by id desc) from (
        select * from va_pedidos where biz = s.biz and ref = s.cod order by id desc limit 50) p), '[]'::jsonb))
  into r;
  return r;
end $$;

create or replace function va_promotor_cobro(p_token text, p_monto numeric) returns text
language plpgsql security definer set search_path = public as $$
declare s record; kk text; i int := 0;
begin
  s := va_sesion(p_token, 'v');
  if p_monto is null or p_monto <= 0 or p_monto >= 100000 then raise exception 'Escribe el monto que recibiste'; end if;
  perform va_limite('cobro:' || s.biz || ':' || s.cod, 40, interval '1 hour');
  loop
    kk := lpad((100000 + floor(random() * 900000))::int::text, 6, '0');
    exit when not exists(select 1 from va_recibos r where r.biz = s.biz and r.k = kk and r.t > now() - interval '1 day');
    i := i + 1; if i > 20 then raise exception 'Intenta de nuevo'; end if;
  end loop;
  insert into va_recibos(biz, prom, k, monto) values (s.biz, s.cod, kk, round(p_monto, 2));
  return kk;
end $$;

-- Venta casa por casa (el promotor recibió el efectivo en mano)
create or replace function va_promotor_venta(p_token text, p_items jsonb, p_nombre text, p_tel text, p_dir text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare s record; its jsonb := '[]'::jsonb; tot numeric(10,2) := 0; x jsonb; pr va_productos; qn int; codigo text; kk text;
begin
  s := va_sesion(p_token, 'v');
  perform va_limite('venta:' || s.biz || ':' || s.cod, 30, interval '1 hour');
  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) not between 1 and 30 then raise exception 'Agrega los productos vendidos'; end if;
  for x in select * from jsonb_array_elements(p_items) loop
    if coalesce(x->>'id', '') !~ '^\d{1,12}$' or coalesce(x->>'q', '') !~ '^\d{1,2}$' then raise exception 'Producto inválido'; end if;
    qn := (x->>'q')::int; continue when qn < 1;
    select * into pr from va_productos where id = (x->>'id')::bigint and biz = s.biz and activo;
    if pr.id is null then raise exception 'Producto no disponible'; end if;
    its := its || jsonb_build_object('n', pr.n, 'p', pr.p, 'q', qn); tot := tot + pr.p * qn;
  end loop;
  if tot <= 0 then raise exception 'Agrega los productos vendidos'; end if;
  update va_negocio_priv set sig_cod = sig_cod + 1 where biz = s.biz returning '#' || (sig_cod - 1) into codigo;
  kk := lpad((100000 + floor(random() * 900000))::int::text, 6, '0');
  insert into va_recibos(biz, prom, k, monto, usado) values (s.biz, s.cod, kk, tot, codigo);
  insert into va_pedidos(biz, cod, cliente_id, cliente_nom, cliente_tel, cliente_dir, items, total, pago, ref_pago, recibo, directa, ref)
  values (s.biz, codigo, gen_random_uuid(), va_txt(p_nombre, 60, true, 'nombre'), va_txt(p_tel, 30), va_txt(p_dir, 160, true, 'dirección'),
          its, tot, 'Efectivo', s.cod, kk, true, s.cod);
  return jsonb_build_object('cod', codigo, 'k', kk, 'total', tot);
end $$;

-- ---------------------------------------------------------------------
-- 7) MANTENIMIENTO (pg_cron) para quedarse SIEMPRE en el plan gratis
-- ---------------------------------------------------------------------
create or replace function va_mantenimiento() returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  u jsonb := va_uso();
  apretado boolean := (u->>'db_mb')::numeric > 400 or (u->>'storage_mb')::numeric > 850;  -- cerca del límite: purga más fuerte
  dias_msg int := case when apretado then 20 else 60 end;
  dias_ped int := case when apretado then 90 else 180 end;
  borrar text[]; nm int; np int;
begin
  -- a) chat viejo
  delete from va_mensajes where t < now() - make_interval(days => dias_msg);
  get diagnostics nm = row_count;
  -- b) fotos de comprobantes > 30 días (y las subidas huérfanas de > 1 día)
  update va_pedidos set comprobante = null where comprobante is not null and t < now() - interval '30 days';
  borrar := array(select name from storage.objects o where bucket_id = 'va-imagenes' and (
      (name like 'r/%' and created_at < now() - interval '30 days')
   or (name like 'r/%' and created_at < now() - interval '1 day' and not exists(select 1 from va_pedidos p where p.comprobante = o.name))
   or (name like 'p/%' and created_at < now() - interval '1 day'
       and not exists(select 1 from va_productos x where x.img = o.name)
       and not exists(select 1 from va_negocios x where x.hero = o.name))) limit 900);
  perform va_borrar_storage(borrar);
  -- c) pedidos finalizados viejos -> resumen mensual por promotor (no se pierden las cifras)
  insert into va_resumen(biz, mes, ref, pedidos, total)
  select biz, date_trunc('month', t)::date, coalesce(ref, ''), count(*), sum(total) from va_pedidos
   where estado = 'cobrado' and t < now() - make_interval(days => dias_ped)
     and not (pago ilike '%efectivo%' and pago_estado = 'verificado' and liquidado is null)
   group by 1, 2, 3
  on conflict (biz, mes, ref) do update set pedidos = va_resumen.pedidos + excluded.pedidos, total = va_resumen.total + excluded.total;
  delete from va_pedidos where estado in ('cobrado', 'rechazado') and t < now() - make_interval(days => dias_ped)
     and not (pago ilike '%efectivo%' and pago_estado = 'verificado' and liquidado is null and estado = 'cobrado');
  get diagnostics np = row_count;
  -- d) temporales
  delete from va_recibos where t < now() - interval '30 days';
  delete from va_sesiones where expira < now();
  delete from va_tickets where expira < now() - interval '1 hour';
  delete from va_limites where desde < now() - interval '1 day';
  return jsonb_build_object('uso', u, 'apretado', apretado, 'mensajes_borrados', nm, 'pedidos_archivados', np,
                            'imagenes_borradas', coalesce(array_length(borrar, 1), 0));
end $$;

-- Ping barato para el keep-alive (GitHub Actions)
create or replace function va_ping() returns text language sql stable as $$ select 'ok' $$;

-- ---------------------------------------------------------------------
-- 8) PERMISOS DE EJECUCIÓN: anon solo ve las RPC públicas
-- ---------------------------------------------------------------------
do $$ declare f record; begin
  for f in select p.oid::regprocedure as sig, p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname like 'va\_%' loop
    execute format('revoke all on function %s from public, anon, authenticated', f.sig);
    if f.proname in ('va_crear_pedido','va_adjuntar_comprobante','va_cliente_enviar','va_cliente_sync',
      'va_login_panel','va_logout','va_panel_datos','va_panel_leido','va_panel_enviar','va_panel_pedido','va_panel_liquidar',
      'va_panel_negocio','va_panel_cuenta','va_panel_producto','va_panel_producto_borrar','va_panel_vendedor','va_panel_ticket',
      'va_panel_uso','va_login_vendedor','va_promotor_datos','va_promotor_cobro','va_promotor_venta','va_ping','va_ticket_ok') then
      execute format('grant execute on function %s to anon, authenticated', f.sig);
    end if;
  end loop;
end $$;
-- (va_ticket_ok lo necesita la política de Storage, que corre con el rol anon; solo responde true/false)

-- ---------------------------------------------------------------------
-- 9) STORAGE: bucket público de solo lectura, 200 KB máx, WebP/JPEG
-- ---------------------------------------------------------------------
insert into storage.buckets(id, name, public, file_size_limit, allowed_mime_types)
values ('va-imagenes', 'va-imagenes', true, 204800, array['image/webp', 'image/jpeg'])
on conflict (id) do update set public = true, file_size_limit = 204800, allowed_mime_types = array['image/webp', 'image/jpeg'];

drop policy if exists va_img_subir on storage.objects;
create policy va_img_subir on storage.objects for insert to anon, authenticated
  with check (bucket_id = 'va-imagenes' and public.va_ticket_ok(name));
-- No hay política de update/delete para anon: borrar lo hace el servidor con va_borrar_storage().

-- ---------------------------------------------------------------------
-- 10) TAREAS PROGRAMADAS (pg_cron)
-- ---------------------------------------------------------------------
select cron.unschedule(jobid) from cron.job where jobname = 'va-mantenimiento';
select cron.schedule('va-mantenimiento', '17 7 * * *', 'select public.va_mantenimiento()');  -- diario 07:17 UTC

-- ---------------------------------------------------------------------
-- 11) CLAVE DE SERVICIO EN VAULT (solo servidor) — se ejecuta aparte, NO se guarda aquí:
--   select vault.create_secret('<SERVICE_ROLE_KEY>', 'va_service_key', 'Borrado de imágenes va-imagenes');
-- ---------------------------------------------------------------------
