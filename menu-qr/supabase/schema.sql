-- =====================================================================
--  Menú QR · schema.sql  (prefijo mqr_)
--  Pega TODO este archivo en Supabase → SQL Editor → New query → Run.
--  Se puede ejecutar varias veces sin dañar nada (no borra tus datos).
--  Seguridad: RLS activado. El público solo LEE lo publicado/activo y
--  puede CREAR pedidos/citas. Solo el dueño (usuario de Authentication)
--  puede editar, subir fotos y ver pedidos. Sin claves secretas en la app.
-- =====================================================================

-- ---------- Dueño del negocio ----------
-- El primer usuario que entra al panel queda registrado como dueño.
-- Recomendado: Authentication → Sign In / Providers → desactiva "Allow new users to sign up".
create table if not exists public.mqr_duenos (
  user_id uuid primary key references auth.users(id) on delete cascade,
  creado timestamptz not null default now()
);
alter table public.mqr_duenos enable row level security;
drop policy if exists "mqr_duenos_ver" on public.mqr_duenos;
create policy "mqr_duenos_ver" on public.mqr_duenos for select to authenticated using (user_id = auth.uid());

create or replace function public.mqr_es_dueno() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.mqr_duenos where user_id = auth.uid());
$$;

create or replace function public.mqr_reclamar() returns boolean
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then return false; end if;
  lock table public.mqr_duenos in exclusive mode;
  if not exists (select 1 from public.mqr_duenos) then
    insert into public.mqr_duenos(user_id) values (auth.uid());
  end if;
  return exists (select 1 from public.mqr_duenos where user_id = auth.uid());
end $$;
revoke all on function public.mqr_reclamar() from public, anon;
grant execute on function public.mqr_reclamar() to authenticated;
grant execute on function public.mqr_es_dueno() to anon, authenticated;

-- ---------- Ajustes del negocio (una sola fila, id = 1) ----------
create table if not exists public.mqr_ajustes (
  id int primary key default 1 check (id = 1),
  datos jsonb not null default '{}'::jsonb,
  actualizado timestamptz not null default now()
);
alter table public.mqr_ajustes enable row level security;
drop policy if exists "mqr_ajustes_leer" on public.mqr_ajustes;
create policy "mqr_ajustes_leer" on public.mqr_ajustes for select to anon, authenticated using (true);
drop policy if exists "mqr_ajustes_dueno" on public.mqr_ajustes;
create policy "mqr_ajustes_dueno" on public.mqr_ajustes for all to authenticated using (public.mqr_es_dueno()) with check (public.mqr_es_dueno());
grant select on public.mqr_ajustes to anon;
grant select, insert, update, delete on public.mqr_ajustes to authenticated;
insert into public.mqr_ajustes(id, datos) values (1, '{}'::jsonb) on conflict (id) do nothing;

create table if not exists public.mqr_categorias (
  id uuid primary key default gen_random_uuid(),
  nombre text not null check (length(nombre) between 1 and 60),
  orden int not null default 0,
  activo boolean not null default true,
  creado timestamptz not null default now()
);
alter table public.mqr_categorias enable row level security;
drop policy if exists "mqr_categorias_leer" on public.mqr_categorias;
create policy "mqr_categorias_leer" on public.mqr_categorias for select to anon, authenticated using (activo or public.mqr_es_dueno());
drop policy if exists "mqr_categorias_dueno" on public.mqr_categorias;
create policy "mqr_categorias_dueno" on public.mqr_categorias for all to authenticated using (public.mqr_es_dueno()) with check (public.mqr_es_dueno());
grant select on public.mqr_categorias to anon;
grant select, insert, update, delete on public.mqr_categorias to authenticated;

create table if not exists public.mqr_productos (
  id uuid primary key default gen_random_uuid(),
  categoria_id uuid references public.mqr_categorias(id) on delete set null,
  nombre text not null check (length(nombre) between 1 and 80),
  descripcion text default '' check (length(descripcion) <= 300),
  precio numeric(10,2) not null default 0 check (precio >= 0),
  foto text default '',
  etiqueta text default '' check (length(etiqueta) <= 20),
  disponible boolean not null default true,
  orden int not null default 0,
  creado timestamptz not null default now()
);
alter table public.mqr_productos enable row level security;
drop policy if exists "mqr_productos_leer" on public.mqr_productos;
create policy "mqr_productos_leer" on public.mqr_productos for select to anon, authenticated using (disponible or public.mqr_es_dueno());
drop policy if exists "mqr_productos_dueno" on public.mqr_productos;
create policy "mqr_productos_dueno" on public.mqr_productos for all to authenticated using (public.mqr_es_dueno()) with check (public.mqr_es_dueno());
grant select on public.mqr_productos to anon;
grant select, insert, update, delete on public.mqr_productos to authenticated;
create index if not exists mqr_productos_cat on public.mqr_productos(categoria_id, orden);

create table if not exists public.mqr_pedidos (
  id uuid primary key default gen_random_uuid(),
  codigo text not null check (length(codigo) <= 20),
  mesa text not null default '' check (length(mesa) <= 10),
  items jsonb not null default '[]'::jsonb check (jsonb_typeof(items) = 'array' and jsonb_array_length(items) between 1 and 60),
  total numeric(10,2) not null default 0,
  nota text default '' check (length(nota) <= 400),
  estado text not null default 'nuevo' check (estado in ('nuevo','preparando','entregado','cancelado')),
  creado timestamptz not null default now()
);
alter table public.mqr_pedidos enable row level security;
drop policy if exists "mqr_pedidos_crear" on public.mqr_pedidos;
create policy "mqr_pedidos_crear" on public.mqr_pedidos for insert to anon, authenticated with check (estado = 'nuevo');
drop policy if exists "mqr_pedidos_dueno" on public.mqr_pedidos;
create policy "mqr_pedidos_dueno" on public.mqr_pedidos for all to authenticated using (public.mqr_es_dueno()) with check (public.mqr_es_dueno());
grant insert on public.mqr_pedidos to anon;
grant select, insert, update, delete on public.mqr_pedidos to authenticated;

create index if not exists mqr_pedidos_creado on public.mqr_pedidos(creado desc);
-- Al crear un pedido, el servidor recalcula precios y total con los datos reales (nadie puede inventar precios).
create or replace function public.mqr_pedido_validar() returns trigger
language plpgsql security definer set search_path = public as $$
declare it jsonb; pr record; nuevos jsonb := '[]'::jsonb; tot numeric := 0; q int;
begin
  if public.mqr_es_dueno() then return new; end if;
  if coalesce((select (datos->>'abierto')::boolean from public.mqr_ajustes where id = 1), true) = false then
    raise exception 'El local está cerrado en este momento';
  end if;
  for it in select * from jsonb_array_elements(new.items) loop
    select id, nombre, precio into pr from public.mqr_productos where id = (it->>'id')::uuid and disponible;
    if not found then raise exception 'Un producto del pedido ya no está disponible'; end if;
    q := greatest(1, least(50, coalesce((it->>'cant')::int, 1)));
    nuevos := nuevos || jsonb_build_object('id', pr.id, 'nombre', pr.nombre, 'precio', pr.precio, 'cant', q);
    tot := tot + pr.precio * q;
  end loop;
  new.items := nuevos; new.total := tot; new.estado := 'nuevo'; new.creado := now();
  return new;
end $$;
drop trigger if exists mqr_pedido_validar on public.mqr_pedidos;
create trigger mqr_pedido_validar before insert on public.mqr_pedidos for each row execute function public.mqr_pedido_validar();

-- Tiempo real (el panel recibe los nuevos al instante; RLS impide que el público los vea)
do $$ begin
  if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'mqr_pedidos') then
    alter publication supabase_realtime add table public.mqr_pedidos;
  end if;
exception when undefined_object then null; end $$;

-- ---------- Fotos (Storage). Lectura pública; solo el dueño sube/borra. Máx 200 KB ----------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('mqr-imagenes', 'mqr-imagenes', true, 204800, array['image/webp','image/jpeg','image/png'])
on conflict (id) do update set public = true, file_size_limit = 204800, allowed_mime_types = excluded.allowed_mime_types;
drop policy if exists "mqr_img_subir" on storage.objects;
create policy "mqr_img_subir" on storage.objects for insert to authenticated with check (bucket_id = 'mqr-imagenes' and public.mqr_es_dueno());
drop policy if exists "mqr_img_cambiar" on storage.objects;
create policy "mqr_img_cambiar" on storage.objects for update to authenticated using (bucket_id = 'mqr-imagenes' and public.mqr_es_dueno());
drop policy if exists "mqr_img_borrar" on storage.objects;
create policy "mqr_img_borrar" on storage.objects for delete to authenticated using (bucket_id = 'mqr-imagenes' and public.mqr_es_dueno());
drop policy if exists "mqr_img_ver" on storage.objects;
create policy "mqr_img_ver" on storage.objects for select to authenticated using (bucket_id = 'mqr-imagenes' and public.mqr_es_dueno());

-- Listo ✓  Ahora crea tu usuario en Authentication → Users → Add user (marca Auto Confirm User).
notify pgrst, 'reload schema';
