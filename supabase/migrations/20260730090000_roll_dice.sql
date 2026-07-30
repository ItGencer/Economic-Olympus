create or replace function public.get_board_cell_ids(p_ring text)
returns text[]
language sql
immutable
security definer
set search_path = public
as $$
  select case p_ring
    when 'outer' then array[
      'outer-image-01',
      'outer-tender-ukraine-02',
      'outer-tax-03',
      'outer-company-logistics-04',
      'outer-advertising-05',
      'outer-casino-06',
      'outer-client-07',
      'outer-director-08',
      'outer-negative-reputation-09',
      'outer-tender-germany-10',
      'outer-company-retail-11',
      'outer-salary-12',
      'outer-random-13',
      'outer-company-tech-14',
      'outer-positive-reputation-15',
      'outer-tender-mexico-16',
      'outer-vacation-17',
      'outer-company-finance-18',
      'outer-client-19',
      'outer-tax-20',
      'outer-tender-brazil-21',
      'outer-company-energy-22',
      'outer-advertising-23',
      'outer-casino-24',
      'outer-director-25',
      'outer-tender-italy-26',
      'outer-company-media-27',
      'outer-image-28',
      'outer-random-29',
      'outer-tender-france-30',
      'outer-positive-reputation-31',
      'outer-salary-32'
    ]
    else array[
      'inner-start-01',
      'inner-casino-02',
      'inner-random-03',
      'inner-vacation-04',
      'inner-deal-05',
      'inner-image-06',
      'inner-negative-reputation-07',
      'inner-salary-08',
      'inner-deal-09',
      'inner-random-10',
      'inner-casino-11',
      'inner-image-12',
      'inner-vacation-13',
      'inner-deal-14',
      'inner-negative-reputation-15',
      'inner-salary-16'
    ]
  end;
$$;

create or replace function public.get_next_turn_player_id(
  p_game_id uuid,
  p_current_player_id uuid
)
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  with current_player as (
    select seat_number
    from public.players
    where id = p_current_player_id
      and game_id = p_game_id
  ),
  next_player as (
    select p.id
    from public.players p
    cross join current_player cp
    where p.game_id = p_game_id
      and p.seat_number > cp.seat_number
    order by p.seat_number
    limit 1
  ),
  first_player as (
    select p.id
    from public.players p
    where p.game_id = p_game_id
    order by p.seat_number
    limit 1
  )
  select coalesce(
    (select id from next_player),
    (select id from first_player)
  );
$$;

create or replace function public.roll_dice(p_game_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_game public.games%rowtype;
  v_player public.players%rowtype;
  v_next_player_id uuid;
  v_players jsonb;
  v_player_json jsonb;
  v_updated_player jsonb;
  v_state jsonb;
  v_player_index integer;
  v_die integer;
  v_skip_turns integer;
  v_ring text;
  v_cell_ids text[];
  v_cell_count integer;
  v_from_cell_id text;
  v_to_cell_id text;
  v_from_index integer;
  v_to_index integer;
  v_now timestamptz := now();
  v_turn_number integer;
  v_skipped boolean := false;
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

  if v_game.status <> 'in_progress' then
    raise exception 'game_is_not_in_progress';
  end if;

  if v_game.current_turn_player_id is null then
    raise exception 'current_turn_player_required';
  end if;

  select *
  into v_player
  from public.players
  where game_id = v_game.id
    and user_id = v_user_id;

  if not found then
    raise exception 'player_not_in_game';
  end if;

  if v_player.id <> v_game.current_turn_player_id then
    raise exception 'not_your_turn';
  end if;

  v_players := coalesce(v_game.state->'players', '[]'::jsonb);

  select ordinality::integer
  into v_player_index
  from jsonb_array_elements(v_players) with ordinality as players(player_data, ordinality)
  where player_data->>'id' = v_player.id::text
  limit 1;

  if v_player_index is null then
    raise exception 'player_missing_from_state';
  end if;

  v_player_json := v_players->(v_player_index - 1);
  v_ring := coalesce(nullif(v_player_json->>'ring', ''), 'inner');

  if v_ring not in ('inner', 'outer') then
    v_ring := 'inner';
  end if;

  v_cell_ids := public.get_board_cell_ids(v_ring);
  v_cell_count := array_length(v_cell_ids, 1);
  v_from_cell_id := coalesce(nullif(v_player_json->>'cellId', ''), v_cell_ids[1]);
  v_from_index := array_position(v_cell_ids, v_from_cell_id);

  if v_from_index is null then
    v_from_index := 1;
    v_from_cell_id := v_cell_ids[1];
  end if;

  v_skip_turns := coalesce((v_player_json->>'skipTurns')::integer, 0);
  v_next_player_id := public.get_next_turn_player_id(v_game.id, v_player.id);

  if v_next_player_id is null then
    raise exception 'next_turn_player_not_found';
  end if;

  v_turn_number := coalesce((v_game.state#>>'{turn,number}')::integer, 0) + 1;

  if v_skip_turns > 0 then
    v_skipped := true;
    v_die := null;
    v_to_cell_id := v_from_cell_id;
    v_updated_player := jsonb_set(
      v_player_json,
      '{skipTurns}',
      to_jsonb(v_skip_turns - 1),
      true
    );
  else
    v_die := floor(random() * 6)::integer + 1;
    v_to_index := ((v_from_index - 1 + v_die) % v_cell_count) + 1;
    v_to_cell_id := v_cell_ids[v_to_index];
    v_updated_player := jsonb_set(
      v_player_json,
      '{cellId}',
      to_jsonb(v_to_cell_id),
      true
    );
  end if;

  v_updated_player := jsonb_set(
    v_updated_player,
    '{cellId}',
    to_jsonb(v_to_cell_id),
    true
  );
  v_updated_player := jsonb_set(v_updated_player, '{ring}', to_jsonb(v_ring), true);
  v_updated_player := jsonb_set(v_updated_player, '{updatedAt}', to_jsonb(v_now), true);

  v_state := v_game.state;
  v_state := jsonb_set(
    v_state,
    array['players', (v_player_index - 1)::text],
    v_updated_player,
    false
  );
  v_state := jsonb_set(
    v_state,
    '{currentTurnPlayerId}',
    to_jsonb(v_next_player_id::text),
    true
  );
  v_state := jsonb_set(
    v_state,
    '{turn}',
    jsonb_build_object(
      'id', gen_random_uuid(),
      'gameId', v_game.id,
      'number', v_turn_number,
      'playerId', v_player.id,
      'phase', 'finished',
      'dice', case when v_skipped then '[]'::jsonb else jsonb_build_array(v_die) end,
      'fromCellId', v_from_cell_id,
      'toCellId', v_to_cell_id,
      'startedAt', v_now,
      'finishedAt', v_now
    ),
    true
  );
  v_state := jsonb_set(v_state, '{pendingAction}', 'null'::jsonb, true);
  v_state := jsonb_set(v_state, '{updatedAt}', to_jsonb(v_now), true);

  update public.games
  set
    current_turn_player_id = v_next_player_id,
    state = v_state
  where id = v_game.id
  returning state into v_state;

  insert into public.game_log (
    game_id,
    turn_number,
    player_id,
    event_type,
    message,
    payload
  )
  values (
    v_game.id,
    v_turn_number,
    v_player.id,
    case when v_skipped then 'turn_skipped' else 'dice_rolled' end,
    case when v_skipped then 'Хід пропущено' else 'Кинуто кубик' end,
    jsonb_build_object(
      'die', v_die,
      'fromCellId', v_from_cell_id,
      'toCellId', v_to_cell_id,
      'nextPlayerId', v_next_player_id,
      'skipped', v_skipped
    )
  );

  return jsonb_build_object(
    'game_id', v_game.id,
    'player_id', v_player.id,
    'die', v_die,
    'from_cell_id', v_from_cell_id,
    'to_cell_id', v_to_cell_id,
    'next_player_id', v_next_player_id,
    'skipped', v_skipped,
    'state', v_state
  );
end;
$$;

grant execute on function public.roll_dice(uuid) to authenticated;
