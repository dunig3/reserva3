-- =====================================================================
--  Catálogo por talla · schema.sql  (prefijo cat_)
--  Pega TODO este archivo en Supabase → SQL Editor → New query → Run.
--  Se puede ejecutar varias veces sin dañar nada (no borra tus datos).
--  Seguridad: RLS activado. El público solo LEE lo publicado/activo y
--  puede CREAR pedidos/citas. Solo el dueño (usuario de Authentication)
--  puede editar, subir fotos y ver pedidos. Sin claves secretas en la app.
-- =====================================================================

-- ---------- Dueño del negocio ----------
-- El primer usuario que entra al panel queda registrado como dueño.
-- Recomendado: Authentication → Sign In / Providers → desactiva "Allow new users to sign up".
create table if not exists public.cat_duenos (
  user_id uuid primary key references auth.users(id) on delete cascade,
  creado timestamptz not null default now()
);
alter table public.cat_duenos enable row level security;
drop policy if exists "cat_duenos_ver" on public.cat_duenos;
create policy "cat_duenos_ver" on public.cat_duenos for select to authenticated using (user_id = auth.uid());

create or replace function public.cat_es_dueno() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.cat_duenos where user_id = auth.uid());
$$;

create or replace function public.cat_reclamar() returns boolean
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then return false; end if;
  lock table public.cat_duenos in exclusive mode;
  if not exists (select 1 from public.cat_duenos) then
    insert into public.cat_duenos(user_id) values (auth.uid());
  end if;
  return exists (select 1 from public.cat_duenos where user_id = auth.uid());
end $$;
revoke all on function public.cat_reclamar() from public, anon;
grant execute on function public.cat_reclamar() to authenticated;
grant execute on function public.cat_es_dueno() to anon, authenticated;

-- ---------- Ajustes del negocio (una sola fila, id = 1) ----------
create table if not exists public.cat_ajustes (
  id int primary key default 1 check (id = 1),
  datos jsonb not null default '{}'::jsonb,
  actualizado timestamptz not null default now()
);
alter table public.cat_ajustes enable row level security;
drop policy if exists "cat_ajustes_leer" on public.cat_ajustes;
create policy "cat_ajustes_leer" on public.cat_ajustes for select to anon, authenticated using (true);
drop policy if exists "cat_ajustes_dueno" on public.cat_ajustes;
create policy "cat_ajustes_dueno" on public.cat_ajustes for all to authenticated using (public.cat_es_dueno()) with check (public.cat_es_dueno());
grant select on public.cat_ajustes to anon;
grant select, insert, update, delete on public.cat_ajustes to authenticated;
insert into public.cat_ajustes(id, datos) values (1, '{}'::jsonb) on conflict (id) do nothing;

create table if not exists public.cat_tallas (
  id uuid primary key default gen_random_uuid(),
  nombre text not null check (length(nombre) between 1 and 40),
  tallas jsonb not null default '[]'::jsonb check (jsonb_typeof(tallas) = 'array'),
  orden int not null default 0,
  creado timestamptz not null default now()
);
alter table public.cat_tallas enable row level security;
drop policy if exists "cat_tallas_leer" on public.cat_tallas;
create policy "cat_tallas_leer" on public.cat_tallas for select to anon, authenticated using (true or public.cat_es_dueno());
drop policy if exists "cat_tallas_dueno" on public.cat_tallas;
create policy "cat_tallas_dueno" on public.cat_tallas for all to authenticated using (public.cat_es_dueno()) with check (public.cat_es_dueno());
grant select on public.cat_tallas to anon;
grant select, insert, update, delete on public.cat_tallas to authenticated;

create table if not exists public.cat_categorias (
  id uuid primary key default gen_random_uuid(),
  nombre text not null check (length(nombre) between 1 and 40),
  tallas_id uuid references public.cat_tallas(id) on delete set null,
  orden int not null default 0,
  creado timestamptz not null default now()
);
alter table public.cat_categorias enable row level security;
drop policy if exists "cat_categorias_leer" on public.cat_categorias;
create policy "cat_categorias_leer" on public.cat_categorias for select to anon, authenticated using (true or public.cat_es_dueno());
drop policy if exists "cat_categorias_dueno" on public.cat_categorias;
create policy "cat_categorias_dueno" on public.cat_categorias for all to authenticated using (public.cat_es_dueno()) with check (public.cat_es_dueno());
grant select on public.cat_categorias to anon;
grant select, insert, update, delete on public.cat_categorias to authenticated;

create table if not exists public.cat_productos (
  id uuid primary key default gen_random_uuid(),
  categoria_id uuid references public.cat_categorias(id) on delete set null,
  nombre text not null check (length(nombre) between 1 and 80),
  descripcion text default '' check (length(descripcion) <= 400),
  precio numeric(10,2) not null default 0 check (precio >= 0),
  tallas jsonb not null default '[]'::jsonb check (jsonb_typeof(tallas) = 'array'),
  fotos jsonb not null default '[]'::jsonb check (jsonb_typeof(fotos) = 'array' and jsonb_array_length(fotos) <= 8),
  nuevo boolean not null default false,
  activo boolean not null default true,
  orden int not null default 0,
  creado timestamptz not null default now()
);
alter table public.cat_productos enable row level security;
drop policy if exists "cat_productos_leer" on public.cat_productos;
create policy "cat_productos_leer" on public.cat_productos for select to anon, authenticated using (activo or public.cat_es_dueno());
drop policy if exists "cat_productos_dueno" on public.cat_productos;
create policy "cat_productos_dueno" on public.cat_productos for all to authenticated using (public.cat_es_dueno()) with check (public.cat_es_dueno());
grant select on public.cat_productos to anon;
grant select, insert, update, delete on public.cat_productos to authenticated;
create index if not exists cat_productos_cat on public.cat_productos(categoria_id);

create table if not exists public.cat_pedidos (
  id uuid primary key default gen_random_uuid(),
  codigo text not null check (length(codigo) <= 20),
  cliente text not null default '' check (length(cliente) <= 80),
  telefono text not null default '' check (length(telefono) <= 30),
  items jsonb not null default '[]'::jsonb check (jsonb_typeof(items) = 'array' and jsonb_array_length(items) between 1 and 30),
  total numeric(10,2) not null default 0,
  nota text default '' check (length(nota) <= 400),
  estado text not null default 'nuevo' check (estado in ('nuevo','confirmado','enviado','entregado','cancelado')),
  creado timestamptz not null default now()
);
alter table public.cat_pedidos enable row level security;
drop policy if exists "cat_pedidos_crear" on public.cat_pedidos;
create policy "cat_pedidos_crear" on public.cat_pedidos for insert to anon, authenticated with check (estado = 'nuevo');
drop policy if exists "cat_pedidos_dueno" on public.cat_pedidos;
create policy "cat_pedidos_dueno" on public.cat_pedidos for all to authenticated using (public.cat_es_dueno()) with check (public.cat_es_dueno());
grant insert on public.cat_pedidos to anon;
grant select, insert, update, delete on public.cat_pedidos to authenticated;

create index if not exists cat_pedidos_creado on public.cat_pedidos(creado desc);
-- Al crear un pedido, el servidor recalcula precios y revisa que la talla exista y tenga stock.
create or replace function public.cat_pedido_validar() returns trigger
language plpgsql security definer set search_path = public as $$
declare it jsonb; pr record; nuevos jsonb := '[]'::jsonb; tot numeric := 0; q int; t text; st jsonb;
begin
  if public.cat_es_dueno() then return new; end if;
  for it in select * from jsonb_array_elements(new.items) loop
    select id, nombre, precio, tallas into pr from public.cat_productos where id = (it->>'id')::uuid and activo;
    if not found then raise exception 'Un producto del pedido ya no está disponible'; end if;
    t := coalesce(it->>'talla', '');
    select x into st from jsonb_array_elements(pr.tallas) x where x->>'t' = t limit 1;
    if st is null then raise exception 'La talla % no está disponible', t; end if;
    if (st->>'stock') is not null and (st->>'stock')::int <= 0 then raise exception 'La talla % está agotada', t; end if;
    q := greatest(1, least(20, coalesce((it->>'cant')::int, 1)));
    nuevos := nuevos || jsonb_build_object('id', pr.id, 'nombre', pr.nombre, 'precio', pr.precio, 'talla', t, 'cant', q);
    tot := tot + pr.precio * q;
  end loop;
  new.items := nuevos; new.total := tot; new.estado := 'nuevo'; new.creado := now();
  return new;
end $$;
drop trigger if exists cat_pedido_validar on public.cat_pedidos;
create trigger cat_pedido_validar before insert on public.cat_pedidos for each row execute function public.cat_pedido_validar();

-- Tiempo real (el panel recibe los nuevos al instante; RLS impide que el público los vea)
do $$ begin
  if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'cat_pedidos') then
    alter publication supabase_realtime add table public.cat_pedidos;
  end if;
exception when undefined_object then null; end $$;

-- ---------- Fotos (Storage). Lectura pública; solo el dueño sube/borra. Máx 200 KB ----------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('cat-imagenes', 'cat-imagenes', true, 204800, array['image/webp','image/jpeg','image/png'])
on conflict (id) do update set public = true, file_size_limit = 204800, allowed_mime_types = excluded.allowed_mime_types;
drop policy if exists "cat_img_subir" on storage.objects;
create policy "cat_img_subir" on storage.objects for insert to authenticated with check (bucket_id = 'cat-imagenes' and public.cat_es_dueno());
drop policy if exists "cat_img_cambiar" on storage.objects;
create policy "cat_img_cambiar" on storage.objects for update to authenticated using (bucket_id = 'cat-imagenes' and public.cat_es_dueno());
drop policy if exists "cat_img_borrar" on storage.objects;
create policy "cat_img_borrar" on storage.objects for delete to authenticated using (bucket_id = 'cat-imagenes' and public.cat_es_dueno());
drop policy if exists "cat_img_ver" on storage.objects;
create policy "cat_img_ver" on storage.objects for select to authenticated using (bucket_id = 'cat-imagenes' and public.cat_es_dueno());

-- Listo ✓  Ahora crea tu usuario en Authentication → Users → Add user (marca Auto Confirm User).
notify pgrst, 'reload schema';
