create or replace function public.generate_join_code()
returns text
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_code text;
begin
  loop
    v_code := upper(substr(encode(extensions.gen_random_bytes(4), 'hex'), 1, 6));
    exit when not exists (
      select 1
      from public.games
      where join_code = v_code
    );
  end loop;

  return v_code;
end;
$$;

create or replace function public.build_lobby_state(p_game_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'gameId', g.id,
    'status', g.status,
    'joinCode', g.join_code,
    'maxPlayers', g.max_players,
    'currentTurnPlayerId', g.current_turn_player_id,
    'winnerPlayerId', g.winner_player_id,
    'players', coalesce(players.players, '[]'::jsonb),
    'turn', null,
    'pendingAction', null,
    'companies', '{}'::jsonb,
    'tenders', '{}'::jsonb,
    'directors', '{}'::jsonb,
    'log', '[]'::jsonb,
    'createdAt', g.created_at,
    'updatedAt', g.updated_at
  )
  from public.games g
  left join lateral (
    select jsonb_agg(
      jsonb_build_object(
        'id', p.id,
        'gameId', p.game_id,
        'userId', p.user_id,
        'seatNumber', p.seat_number,
        'name', p.display_name,
        'isBot', p.is_bot,
        'ring', 'inner',
        'cellId', 'inner-start-01',
        'balance', 10000,
        'image', 0,
        'inventory', 0,
        'successfulDeals', 0,
        'failedDeals', 0,
        'debtLocked', false,
        'skipTurns', 0,
        'shares', '{}'::jsonb,
        'tenderIds', '[]'::jsonb,
        'directorIds', '[]'::jsonb,
        'createdAt', p.created_at,
        'updatedAt', p.updated_at
      )
      order by p.seat_number
    ) as players
    from public.players p
    where p.game_id = g.id
  ) players on true
  where g.id = p_game_id;
$$;

create or replace function public.create_game(
  p_max_players integer default 6,
  p_display_name text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_game_id uuid;
  v_player_id uuid;
  v_join_code text;
  v_state jsonb;
  v_display_name text := coalesce(nullif(btrim(p_display_name), ''), 'Гравець');
begin
  if v_user_id is null then
    raise exception 'auth_required' using errcode = '28000';
  end if;

  if p_max_players is null or p_max_players < 2 or p_max_players > 6 then
    raise exception 'max_players_must_be_between_2_and_6';
  end if;

  v_join_code := public.generate_join_code();

  insert into public.games (join_code, max_players, created_by_user_id)
  values (v_join_code, p_max_players, v_user_id)
  returning id into v_game_id;

  insert into public.players (
    game_id,
    user_id,
    seat_number,
    display_name,
    is_bot
  )
  values (
    v_game_id,
    v_user_id,
    1,
    v_display_name,
    false
  )
  returning id into v_player_id;

  update public.games
  set state = public.build_lobby_state(v_game_id)
  where id = v_game_id
  returning state into v_state;

  return jsonb_build_object(
    'game_id', v_game_id,
    'join_code', v_join_code,
    'player_id', v_player_id,
    'state', v_state
  );
end;
$$;

create or replace function public.join_game(
  p_join_code text,
  p_display_name text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_join_code text := upper(regexp_replace(coalesce(p_join_code, ''), '[[:space:]]+', '', 'g'));
  v_game public.games%rowtype;
  v_existing_player public.players%rowtype;
  v_player_id uuid;
  v_player_count integer;
  v_seat_number integer;
  v_state jsonb;
  v_display_name text := coalesce(nullif(btrim(p_display_name), ''), 'Гравець');
begin
  if v_user_id is null then
    raise exception 'auth_required' using errcode = '28000';
  end if;

  if v_join_code = '' then
    raise exception 'join_code_required';
  end if;

  select *
  into v_game
  from public.games
  where join_code = v_join_code
  for update;

  if not found then
    raise exception 'game_not_found';
  end if;

  if v_game.status <> 'lobby' then
    raise exception 'game_already_started';
  end if;

  select *
  into v_existing_player
  from public.players
  where game_id = v_game.id
    and user_id = v_user_id;

  if found then
    update public.players
    set display_name = v_display_name
    where id = v_existing_player.id
    returning id into v_player_id;

    update public.games
    set state = public.build_lobby_state(v_game.id)
    where id = v_game.id
    returning state into v_state;

    return jsonb_build_object(
      'game_id', v_game.id,
      'join_code', v_game.join_code,
      'player_id', v_player_id,
      'state', v_state
    );
  end if;

  select count(*)
  into v_player_count
  from public.players
  where game_id = v_game.id;

  if v_player_count >= v_game.max_players then
    raise exception 'game_is_full';
  end if;

  select seat_number
  into v_seat_number
  from generate_series(1, v_game.max_players) as seats(seat_number)
  where not exists (
    select 1
    from public.players p
    where p.game_id = v_game.id
      and p.seat_number = seat_number
  )
  order by seat_number
  limit 1;

  if v_seat_number is null then
    raise exception 'no_free_seat';
  end if;

  insert into public.players (
    game_id,
    user_id,
    seat_number,
    display_name,
    is_bot
  )
  values (
    v_game.id,
    v_user_id,
    v_seat_number,
    v_display_name,
    false
  )
  returning id into v_player_id;

  update public.games
  set state = public.build_lobby_state(v_game.id)
  where id = v_game.id
  returning state into v_state;

  return jsonb_build_object(
    'game_id', v_game.id,
    'join_code', v_game.join_code,
    'player_id', v_player_id,
    'state', v_state
  );
end;
$$;

create or replace function public.start_game(p_game_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_game public.games%rowtype;
  v_player_count integer;
  v_first_player_id uuid;
  v_state jsonb;
begin
  if v_user_id is null then
    raise exception 'auth_required' using errcode = '28000';
  end if;

  select *
  into v_game
  from public.games
  where id = p_game_id
  for update;

  if not found then
    raise exception 'game_not_found';
  end if;

  if v_game.created_by_user_id is distinct from v_user_id then
    raise exception 'only_owner_can_start_game';
  end if;

  if v_game.status <> 'lobby' then
    raise exception 'game_is_not_in_lobby';
  end if;

  select count(*)
  into v_player_count
  from public.players
  where game_id = v_game.id;

  if v_player_count < 2 or v_player_count > v_game.max_players then
    raise exception 'player_count_must_be_between_2_and_max_players';
  end if;

  select id
  into v_first_player_id
  from public.players
  where game_id = v_game.id
  order by seat_number
  limit 1;

  update public.games
  set
    status = 'in_progress',
    started_at = now(),
    current_turn_player_id = v_first_player_id
  where id = v_game.id;

  update public.games
  set state = public.build_lobby_state(v_game.id)
  where id = v_game.id
  returning state into v_state;

  insert into public.game_log (
    game_id,
    player_id,
    event_type,
    message,
    payload
  )
  values (
    v_game.id,
    v_first_player_id,
    'game_started',
    'Гру почато',
    jsonb_build_object('playerCount', v_player_count)
  );

  return jsonb_build_object(
    'game_id', v_game.id,
    'join_code', v_game.join_code,
    'current_turn_player_id', v_first_player_id,
    'state', v_state
  );
end;
$$;

grant execute on function public.create_game(integer, text) to authenticated;
grant execute on function public.join_game(text, text) to authenticated;
grant execute on function public.start_game(uuid) to authenticated;

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    begin
      alter publication supabase_realtime add table public.players;
    exception
      when duplicate_object then null;
    end;
  end if;
end $$;
