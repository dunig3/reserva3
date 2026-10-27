-- =====================================================================
--  Agenda de citas · schema.sql  (prefijo agc_)
--  Pega TODO este archivo en Supabase → SQL Editor → New query → Run.
--  Se puede ejecutar varias veces sin dañar nada (no borra tus datos).
--  Seguridad: RLS activado. El público solo LEE lo publicado/activo y
--  puede CREAR pedidos/citas. Solo el dueño (usuario de Authentication)
--  puede editar, subir fotos y ver pedidos. Sin claves secretas en la app.
-- =====================================================================

-- ---------- Dueño del negocio ----------
-- El primer usuario que entra al panel queda registrado como dueño.
-- Recomendado: Authentication → Sign In / Providers → desactiva "Allow new users to sign up".
create table if not exists public.agc_duenos (
  user_id uuid primary key references auth.users(id) on delete cascade,
  creado timestamptz not null default now()
);
alter table public.agc_duenos enable row level security;
drop policy if exists "agc_duenos_ver" on public.agc_duenos;
create policy "agc_duenos_ver" on public.agc_duenos for select to authenticated using (user_id = auth.uid());

create or replace function public.agc_es_dueno() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.agc_duenos where user_id = auth.uid());
$$;

create or replace function public.agc_reclamar() returns boolean
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then return false; end if;
  lock table public.agc_duenos in exclusive mode;
  if not exists (select 1 from public.agc_duenos) then
    insert into public.agc_duenos(user_id) values (auth.uid());
  end if;
  return exists (select 1 from public.agc_duenos where user_id = auth.uid());
end $$;
revoke all on function public.agc_reclamar() from public, anon;
grant execute on function public.agc_reclamar() to authenticated;
grant execute on function public.agc_es_dueno() to anon, authenticated;

-- ---------- Ajustes del negocio (una sola fila, id = 1) ----------
create table if not exists public.agc_ajustes (
  id int primary key default 1 check (id = 1),
  datos jsonb not null default '{}'::jsonb,
  actualizado timestamptz not null default now()
);
alter table public.agc_ajustes enable row level security;
drop policy if exists "agc_ajustes_leer" on public.agc_ajustes;
create policy "agc_ajustes_leer" on public.agc_ajustes for select to anon, authenticated using (true);
drop policy if exists "agc_ajustes_dueno" on public.agc_ajustes;
create policy "agc_ajustes_dueno" on public.agc_ajustes for all to authenticated using (public.agc_es_dueno()) with check (public.agc_es_dueno());
grant select on public.agc_ajustes to anon;
grant select, insert, update, delete on public.agc_ajustes to authenticated;
insert into public.agc_ajustes(id, datos) values (1, '{}'::jsonb) on conflict (id) do nothing;

create table if not exists public.agc_servicios (
  id uuid primary key default gen_random_uuid(),
  nombre text not null check (length(nombre) between 1 and 80),
  precio numeric(10,2) not null default 0 check (precio >= 0),
  duracion int not null default 30 check (duracion between 5 and 600),
  foto text default '',
  etiqueta text default '' check (length(etiqueta) <= 20),
  activo boolean not null default true,
  orden int not null default 0,
  creado timestamptz not null default now()
);
alter table public.agc_servicios enable row level security;
drop policy if exists "agc_servicios_leer" on public.agc_servicios;
create policy "agc_servicios_leer" on public.agc_servicios for select to anon, authenticated using (activo or public.agc_es_dueno());
drop policy if exists "agc_servicios_dueno" on public.agc_servicios;
create policy "agc_servicios_dueno" on public.agc_servicios for all to authenticated using (public.agc_es_dueno()) with check (public.agc_es_dueno());
grant select on public.agc_servicios to anon;
grant select, insert, update, delete on public.agc_servicios to authenticated;

create table if not exists public.agc_bloqueos (
  id uuid primary key default gen_random_uuid(),
  fecha date not null unique,
  motivo text default '' check (length(motivo) <= 80),
  creado timestamptz not null default now()
);
alter table public.agc_bloqueos enable row level security;
drop policy if exists "agc_bloqueos_leer" on public.agc_bloqueos;
create policy "agc_bloqueos_leer" on public.agc_bloqueos for select to anon, authenticated using (true or public.agc_es_dueno());
drop policy if exists "agc_bloqueos_dueno" on public.agc_bloqueos;
create policy "agc_bloqueos_dueno" on public.agc_bloqueos for all to authenticated using (public.agc_es_dueno()) with check (public.agc_es_dueno());
grant select on public.agc_bloqueos to anon;
grant select, insert, update, delete on public.agc_bloqueos to authenticated;

create table if not exists public.agc_citas (
  id uuid primary key default gen_random_uuid(),
  servicio_id uuid references public.agc_servicios(id) on delete set null,
  servicio text not null default '',
  precio numeric(10,2) not null default 0,
  duracion int not null default 30,
  fecha date not null,
  hora text not null check (hora ~ '^[0-2][0-9]:[0-5][0-9]$'),
  cliente text not null check (length(cliente) between 2 and 80),
  telefono text not null check (length(telefono) between 7 and 30),
  nota text default '' check (length(nota) <= 300),
  estado text not null default 'pendiente' check (estado in ('pendiente','confirmada','cancelada','atendida')),
  creado timestamptz not null default now()
);
alter table public.agc_citas enable row level security;
drop policy if exists "agc_citas_crear" on public.agc_citas;
create policy "agc_citas_crear" on public.agc_citas for insert to anon, authenticated with check (estado = 'pendiente' and fecha >= current_date - 1 and fecha <= current_date + 120);
drop policy if exists "agc_citas_dueno" on public.agc_citas;
create policy "agc_citas_dueno" on public.agc_citas for all to authenticated using (public.agc_es_dueno()) with check (public.agc_es_dueno());
grant insert on public.agc_citas to anon;
grant select, insert, update, delete on public.agc_citas to authenticated;

-- Evita reservas dobles: una sola cita activa por fecha y hora (las canceladas liberan el turno).
create unique index if not exists agc_citas_unica on public.agc_citas(fecha, hora) where estado <> 'cancelada';
create index if not exists agc_citas_fecha on public.agc_citas(fecha, hora);
-- Horas ocupadas (sin datos personales) para que TODOS los clientes vean la disponibilidad real.
create or replace function public.agc_ocupados(p_desde date, p_hasta date)
returns table(fecha date, hora text) language sql stable security definer set search_path = public as $$
  select c.fecha, c.hora from public.agc_citas c
  where c.estado <> 'cancelada' and c.fecha between p_desde and least(p_hasta, p_desde + 120);
$$;
grant execute on function public.agc_ocupados(date, date) to anon, authenticated;
-- Al crear una cita: toma nombre/precio reales del servicio y rechaza días bloqueados.
create or replace function public.agc_cita_validar() returns trigger
language plpgsql security definer set search_path = public as $$
declare s record;
begin
  if public.agc_es_dueno() then return new; end if;
  if exists (select 1 from public.agc_bloqueos b where b.fecha = new.fecha) then raise exception 'Ese día no hay atención'; end if;
  select nombre, precio, duracion into s from public.agc_servicios where id = new.servicio_id and activo;
  if not found then raise exception 'Ese servicio ya no está disponible'; end if;
  new.servicio := s.nombre; new.precio := s.precio; new.duracion := s.duracion; new.estado := 'pendiente'; new.creado := now();
  return new;
end $$;
drop trigger if exists agc_cita_validar on public.agc_citas;
create trigger agc_cita_validar before insert on public.agc_citas for each row execute function public.agc_cita_validar();

-- Tiempo real (el panel recibe los nuevos al instante; RLS impide que el público los vea)
do $$ begin
  if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'agc_citas') then
    alter publication supabase_realtime add table public.agc_citas;
  end if;
exception when undefined_object then null; end $$;

-- ---------- Fotos (Storage). Lectura pública; solo el dueño sube/borra. Máx 200 KB ----------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('agc-imagenes', 'agc-imagenes', true, 204800, array['image/webp','image/jpeg','image/png'])
on conflict (id) do update set public = true, file_size_limit = 204800, allowed_mime_types = excluded.allowed_mime_types;
drop policy if exists "agc_img_subir" on storage.objects;
create policy "agc_img_subir" on storage.objects for insert to authenticated with check (bucket_id = 'agc-imagenes' and public.agc_es_dueno());
drop policy if exists "agc_img_cambiar" on storage.objects;
create policy "agc_img_cambiar" on storage.objects for update to authenticated using (bucket_id = 'agc-imagenes' and public.agc_es_dueno());
drop policy if exists "agc_img_borrar" on storage.objects;
create policy "agc_img_borrar" on storage.objects for delete to authenticated using (bucket_id = 'agc-imagenes' and public.agc_es_dueno());
drop policy if exists "agc_img_ver" on storage.objects;
create policy "agc_img_ver" on storage.objects for select to authenticated using (bucket_id = 'agc-imagenes' and public.agc_es_dueno());

-- Listo ✓  Ahora crea tu usuario en Authentication → Users → Add user (marca Auto Confirm User).
notify pgrst, 'reload schema';
