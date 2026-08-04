create extension if not exists pgcrypto;

do $$
begin
  create type public.game_status as enum ('lobby', 'in_progress', 'finished');
exception
  when duplicate_object then null;
end $$;

do $$
begin
  create type public.director_status as enum ('candidate', 'active', 'former');
exception
  when duplicate_object then null;
end $$;

create table if not exists public.games (
  id uuid primary key default gen_random_uuid(),
  status public.game_status not null default 'lobby',
  join_code text not null unique,
  max_players integer not null default 6 check (max_players between 2 and 6),
  state jsonb not null default '{}'::jsonb,
  current_turn_player_id uuid,
  winner_player_id uuid,
  created_by_user_id uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  started_at timestamptz,
  finished_at timestamptz,
  constraint games_join_code_format check (join_code ~ '^[A-Z0-9]{4,12}$'),
  constraint games_started_status_check check (
    (status <> 'in_progress' and started_at is null)
    or (status = 'in_progress' and started_at is not null)
    or status = 'finished'
  ),
  constraint games_finished_status_check check (
    (status <> 'finished' and finished_at is null)
    or (status = 'finished' and finished_at is not null)
  )
);

create table if not exists public.players (
  id uuid primary key default gen_random_uuid(),
  game_id uuid not null references public.games(id) on delete cascade,
  user_id uuid references auth.users(id) on delete cascade,
  seat_number integer not null check (seat_number between 1 and 6),
  display_name text not null default 'Гравець',
  is_bot boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint players_user_or_bot_check check (
    (is_bot = true and user_id is null)
    or (is_bot = false and user_id is not null)
  ),
  constraint players_unique_seat unique (game_id, seat_number),
  constraint players_unique_user unique (game_id, user_id)
);

do $$
begin
  alter table public.games
    add constraint games_current_turn_player_id_fkey
    foreign key (current_turn_player_id)
    references public.players(id)
    on delete set null
    deferrable initially deferred;
exception
  when duplicate_object then null;
end $$;

do $$
begin
  alter table public.games
    add constraint games_winner_player_id_fkey
    foreign key (winner_player_id)
    references public.players(id)
    on delete set null
    deferrable initially deferred;
exception
  when duplicate_object then null;
end $$;

create table if not exists public.game_log (
  id uuid primary key default gen_random_uuid(),
  game_id uuid not null references public.games(id) on delete cascade,
  turn_number integer,
  player_id uuid references public.players(id) on delete set null,
  event_type text not null,
  message text not null,
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create table if not exists public.companies (
  id uuid primary key default gen_random_uuid(),
  game_id uuid not null references public.games(id) on delete cascade,
  config_id text not null,
  name text not null,
  total_shares integer not null default 2000 check (total_shares = 2000),
  share_price numeric(12, 2) not null check (share_price > 0),
  inventory_per_share numeric(12, 2) not null default 1 check (inventory_per_share >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint companies_unique_config unique (game_id, config_id)
);

create table if not exists public.shares (
  id uuid primary key default gen_random_uuid(),
  game_id uuid not null references public.games(id) on delete cascade,
  company_id uuid not null references public.companies(id) on delete cascade,
  player_id uuid not null references public.players(id) on delete cascade,
  share_count integer not null default 0 check (share_count between 0 and 2000),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint shares_unique_player_company unique (company_id, player_id)
);

create table if not exists public.tenders (
  id uuid primary key default gen_random_uuid(),
  game_id uuid not null references public.games(id) on delete cascade,
  config_id text not null,
  country text not null,
  buyout_amount numeric(12, 2) not null check (buyout_amount > 0),
  fee_amount numeric(12, 2) not null check (fee_amount > 0),
  owner_player_id uuid references public.players(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint tenders_unique_config unique (game_id, config_id)
);

create table if not exists public.directors (
  id uuid primary key default gen_random_uuid(),
  game_id uuid not null references public.games(id) on delete cascade,
  company_id uuid not null references public.companies(id) on delete cascade,
  player_id uuid not null references public.players(id) on delete cascade,
  status public.director_status not null default 'active',
  voting_coefficient numeric(8, 2) not null default 1 check (voting_coefficient > 0),
  vote_difficulty integer not null default 7 check (vote_difficulty between 2 and 12),
  elected_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists directors_one_active_per_company
  on public.directors (company_id)
  where status = 'active';

create index if not exists games_status_idx on public.games (status);
create index if not exists games_join_code_idx on public.games (join_code);
create index if not exists players_game_id_idx on public.players (game_id);
create index if not exists game_log_game_id_created_at_idx on public.game_log (game_id, created_at);
create index if not exists companies_game_id_idx on public.companies (game_id);
create index if not exists shares_game_id_idx on public.shares (game_id);
create index if not exists shares_player_id_idx on public.shares (player_id);
create index if not exists tenders_game_id_idx on public.tenders (game_id);
create index if not exists directors_game_id_idx on public.directors (game_id);
create index if not exists directors_player_id_idx on public.directors (player_id);

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists games_set_updated_at on public.games;
create trigger games_set_updated_at
before update on public.games
for each row execute function public.set_updated_at();

drop trigger if exists players_set_updated_at on public.players;
create trigger players_set_updated_at
before update on public.players
for each row execute function public.set_updated_at();

drop trigger if exists companies_set_updated_at on public.companies;
create trigger companies_set_updated_at
before update on public.companies
for each row execute function public.set_updated_at();

drop trigger if exists shares_set_updated_at on public.shares;
create trigger shares_set_updated_at
before update on public.shares
for each row execute function public.set_updated_at();

drop trigger if exists tenders_set_updated_at on public.tenders;
create trigger tenders_set_updated_at
before update on public.tenders
for each row execute function public.set_updated_at();

drop trigger if exists directors_set_updated_at on public.directors;
create trigger directors_set_updated_at
before update on public.directors
for each row execute function public.set_updated_at();

alter table public.games enable row level security;
alter table public.players enable row level security;
alter table public.game_log enable row level security;
alter table public.companies enable row level security;
alter table public.shares enable row level security;
alter table public.tenders enable row level security;
alter table public.directors enable row level security;

drop policy if exists "Authenticated users can read games" on public.games;
create policy "Authenticated users can read games"
on public.games for select
to authenticated
using (true);

drop policy if exists "Authenticated users can read players" on public.players;
create policy "Authenticated users can read players"
on public.players for select
to authenticated
using (true);

drop policy if exists "Authenticated users can read game log" on public.game_log;
create policy "Authenticated users can read game log"
on public.game_log for select
to authenticated
using (true);

drop policy if exists "Authenticated users can read companies" on public.companies;
create policy "Authenticated users can read companies"
on public.companies for select
to authenticated
using (true);

drop policy if exists "Authenticated users can read shares" on public.shares;
create policy "Authenticated users can read shares"
on public.shares for select
to authenticated
using (true);

drop policy if exists "Authenticated users can read tenders" on public.tenders;
create policy "Authenticated users can read tenders"
on public.tenders for select
to authenticated
using (true);

drop policy if exists "Authenticated users can read directors" on public.directors;
create policy "Authenticated users can read directors"
on public.directors for select
to authenticated
using (true);

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    begin
      alter publication supabase_realtime add table public.games;
    exception
      when duplicate_object then null;
    end;
  end if;
end $$;
