-- =====================================================================
--  Calculadora para reposteras · schema.sql  (prefijo rep_)
--  Pega TODO este archivo en Supabase → SQL Editor → New query → Run.
--  Se puede ejecutar varias veces sin dañar nada (no borra tus datos).
--  Cada usuaria (Authentication → Users) ve y edita SOLO sus propios
--  ingredientes, recetas y ajustes (RLS por user_id). El público no ve nada.
-- =====================================================================

create table if not exists public.rep_ajustes (
  id int not null default 1 check (id = 1),
  user_id uuid primary key default auth.uid() references auth.users(id) on delete cascade,
  datos jsonb not null default '{}'::jsonb,
  actualizado timestamptz not null default now()
);
alter table public.rep_ajustes enable row level security;
drop policy if exists "rep_ajustes_propio" on public.rep_ajustes;
create policy "rep_ajustes_propio" on public.rep_ajustes for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
revoke all on public.rep_ajustes from anon;
grant select, insert, update, delete on public.rep_ajustes to authenticated;
create index if not exists rep_ajustes_usuario on public.rep_ajustes(user_id);

create table if not exists public.rep_ingredientes (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  nombre text not null check (length(nombre) between 1 and 80),
  unidad text not null default 'g' check (unidad in ('g','kg','ml','l','und')),
  cantidad numeric(12,3) not null default 1 check (cantidad > 0),
  precio numeric(12,2) not null default 0 check (precio >= 0),
  creado timestamptz not null default now()
);
alter table public.rep_ingredientes enable row level security;
drop policy if exists "rep_ingredientes_propio" on public.rep_ingredientes;
create policy "rep_ingredientes_propio" on public.rep_ingredientes for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
revoke all on public.rep_ingredientes from anon;
grant select, insert, update, delete on public.rep_ingredientes to authenticated;
create index if not exists rep_ingredientes_usuario on public.rep_ingredientes(user_id);

create table if not exists public.rep_recetas (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  nombre text not null check (length(nombre) between 1 and 80),
  items jsonb not null default '[]'::jsonb check (jsonb_typeof(items) = 'array' and jsonb_array_length(items) <= 80),
  margen numeric(6,2) not null default 60 check (margen between 0 and 1000),
  porciones int not null default 12 check (porciones between 1 and 500),
  creado timestamptz not null default now(),
  actualizado timestamptz not null default now()
);
alter table public.rep_recetas enable row level security;
drop policy if exists "rep_recetas_propio" on public.rep_recetas;
create policy "rep_recetas_propio" on public.rep_recetas for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
revoke all on public.rep_recetas from anon;
grant select, insert, update, delete on public.rep_recetas to authenticated;
create index if not exists rep_recetas_usuario on public.rep_recetas(user_id);

-- Listo ✓  Ahora crea tu usuario en Authentication → Users → Add user (marca Auto Confirm User).
notify pgrst, 'reload schema';
