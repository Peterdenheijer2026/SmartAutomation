-- Basis schema voor NRGYM PT-systeem (1 eigenaar, token-toegang voor leden)
-- Run dit in Supabase: SQL Editor.

-- Extensions
create extension if not exists pgcrypto;

-- Leden (zonder Supabase Auth; toegang via code/token)
create table if not exists public.members (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  full_name text not null,
  price_cents bigint not null check (price_cents >= 0),
  access_token_hash text not null,
  created_at timestamptz not null default now()
);

-- PT sessies
create table if not exists public.pt_sessions (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  member_id uuid not null references public.members(id) on delete cascade,
  scheduled_at timestamptz not null,
  attended boolean not null default false,
  attended_at timestamptz,
  created_by uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

-- Facturen
create table if not exists public.invoices (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  member_id uuid not null references public.members(id) on delete cascade,
  month text not null,
  session_count int not null default 0 check (session_count >= 0),
  total_cents bigint not null default 0 check (total_cents >= 0),
  status text not null default 'draft',
  created_at timestamptz not null default now(),
  unique (owner_id, member_id, month)
);

-- Indexen
create index if not exists pt_sessions_owner_member_scheduled_idx
  on public.pt_sessions(owner_id, member_id, scheduled_at);
create index if not exists pt_sessions_owner_attended_idx
  on public.pt_sessions(owner_id, attended, scheduled_at);

-- RLS aanzetten
alter table public.members enable row level security;
alter table public.pt_sessions enable row level security;
alter table public.invoices enable row level security;

-- Owner policies: owner ziet/maakt alleen eigen data
drop policy if exists members_owner_all on public.members;
create policy members_owner_all
  on public.members
  for all
  using (owner_id = auth.uid())
  with check (owner_id = auth.uid());

drop policy if exists pt_sessions_owner_all on public.pt_sessions;
create policy pt_sessions_owner_all
  on public.pt_sessions
  for all
  using (owner_id = auth.uid())
  with check (
    owner_id = auth.uid()
    and exists (
      select 1
      from public.members m
      where m.id = member_id
        and m.owner_id = auth.uid()
    )
  );

drop policy if exists invoices_owner_all on public.invoices;
create policy invoices_owner_all
  on public.invoices
  for all
  using (owner_id = auth.uid())
  with check (owner_id = auth.uid());

-- Member toegang via RPC met access token

-- Helper: token -> hash
-- (maakt hash berekenbaar in functies)

-- 1) Owner: member aanmaken + access token teruggeven
create or replace function public.create_member(
  p_full_name text,
  p_price_cents bigint
)
returns table (
  member_id uuid,
  access_code text,
  full_name text,
  price_cents bigint
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_owner_id uuid;
  v_access_code text;
  v_access_hash text;
begin
  v_owner_id := auth.uid();
  if v_owner_id is null then
    raise exception 'Authentication required (owner).';
  end if;

  v_access_code := encode(gen_random_bytes(16), 'hex'); -- 32 chars
  v_access_hash := encode(digest(v_access_code, 'sha256'), 'hex');

  insert into public.members (owner_id, full_name, price_cents, access_token_hash)
  values (v_owner_id, p_full_name, p_price_cents, v_access_hash)
  returning id, full_name, price_cents
  into member_id, full_name, price_cents;

  access_code := v_access_code;
  return next;
end;
$$;

-- 2) Member: sessies ophalen via access token
create or replace function public.get_member_sessions(
  p_access_token text
)
returns table (
  session_id uuid,
  scheduled_at timestamptz,
  attended boolean,
  attended_at timestamptz,
  member_name text,
  price_cents bigint
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_access_hash text;
  v_member record;
begin
  v_access_hash := encode(digest(p_access_token, 'sha256'), 'hex');

  select m.*
    into v_member
    from public.members m
   where m.access_token_hash = v_access_hash
   limit 1;

  if v_member is null then
    -- Token onbekend: lege set teruggeven
    return;
  end if;

  -- Zet RLS uit in de functie zodat we altijd correct data kunnen teruggeven
  set local row_security = off;

  return query
  select
    s.id as session_id,
    s.scheduled_at,
    s.attended,
    s.attended_at,
    v_member.full_name as member_name,
    v_member.price_cents as price_cents
  from public.pt_sessions s
  where s.member_id = v_member.id
    and s.scheduled_at >= now() - interval '30 days'
  order by s.scheduled_at asc
  limit 200;
end;
$$;

-- 3) Member: attendance toggle via RPC
create or replace function public.set_session_attended(
  p_session_id uuid,
  p_access_token text,
  p_attended boolean
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_access_hash text;
  v_member_id uuid;
  v_owner_id uuid;
begin
  v_access_hash := encode(digest(p_access_token, 'sha256'), 'hex');

  select s.member_id, s.owner_id
    into v_member_id, v_owner_id
  from public.pt_sessions s
  where s.id = p_session_id
  limit 1;

  if v_member_id is null then
    raise exception 'Session not found.';
  end if;

  -- Valideer token hoort bij dit lid
  if not exists (
    select 1
    from public.members m
    where m.id = v_member_id
      and m.access_token_hash = v_access_hash
  ) then
    raise exception 'Invalid access token.';
  end if;

  set local row_security = off;

  if p_attended then
    update public.pt_sessions
      set attended = true,
          attended_at = now()
    where id = p_session_id;
  else
    update public.pt_sessions
      set attended = false,
          attended_at = null
    where id = p_session_id;
  end if;
end;
$$;

-- 4) Owner: facturen genereren voor maand (YYYY-MM)
create or replace function public.generate_invoices_for_month(
  p_month text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_owner_id uuid;
  v_start timestamptz;
  v_end timestamptz;
begin
  v_owner_id := auth.uid();
  if v_owner_id is null then
    raise exception 'Authentication required (owner).';
  end if;

  -- Valideer maand formaat globaal (simpel)
  if p_month !~ '^[0-9]{4}-[0-9]{2}$' then
    raise exception 'month must be YYYY-MM';
  end if;

  v_start := to_timestamp(p_month || '-01', 'YYYY-MM-DD');
  v_end := (v_start + interval '1 month');

  set local row_security = off;

  with per_member as (
    select
      s.member_id,
      count(*)::int as session_count
    from public.pt_sessions s
    where s.owner_id = v_owner_id
      and s.attended = true
      and s.scheduled_at >= v_start
      and s.scheduled_at < v_end
    group by s.member_id
  )
  insert into public.invoices (
    owner_id,
    member_id,
    month,
    session_count,
    total_cents,
    status
  )
  select
    v_owner_id as owner_id,
    pm.member_id,
    p_month as month,
    pm.session_count,
    (pm.session_count * m.price_cents)::bigint as total_cents,
    'draft' as status
  from per_member pm
  join public.members m on m.id = pm.member_id
  on conflict (owner_id, member_id, month)
  do update set
    session_count = excluded.session_count,
    total_cents = excluded.total_cents,
    status = 'draft';
end;
$$;

-- Grants (zodat anon RPC kan gebruiken)
grant execute on function public.get_member_sessions(text) to anon;
grant execute on function public.set_session_attended(uuid, text, boolean) to anon;

-- Owner functions (authenticated)
grant execute on function public.create_member(text, bigint) to authenticated;
grant execute on function public.generate_invoices_for_month(text) to authenticated;

