create or replace function public.is_deal_cell(p_cell_id text)
returns boolean
language sql
immutable
security definer
set search_path = public
as $$
  select p_cell_id in (
    'inner-deal-05',
    'inner-deal-09',
    'inner-deal-14'
  );
$$;

create or replace function public.get_deal_cell_params(p_cell_id text)
returns jsonb
language sql
immutable
security definer
set search_path = public
as $$
  select case
    when public.is_deal_cell(p_cell_id) then
      '{"incomeMin":1000,"incomeMax":10000,"importanceMin":2,"importanceMax":12}'::jsonb
    else null
  end;
$$;

create or replace function public.create_deal_pending_action(
  p_game_id uuid,
  p_player_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_game public.games%rowtype;
  v_player public.players%rowtype;
  v_players jsonb;
  v_player_json jsonb;
  v_state jsonb;
  v_params jsonb;
  v_pending_action jsonb;
  v_pending_action_id uuid := gen_random_uuid();
  v_player_index integer;
  v_turn_number integer;
  v_cell_id text;
  v_income integer;
  v_importance integer;
  v_now timestamptz := now();
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

  if v_game.current_turn_player_id is distinct from p_player_id then
    raise exception 'not_your_turn';
  end if;

  if v_game.state->'pendingAction' is not null
    and v_game.state->'pendingAction' <> 'null'::jsonb then
    raise exception 'pending_action_must_be_resolved';
  end if;

  select *
  into v_player
  from public.players
  where game_id = v_game.id
    and id = p_player_id;

  if not found then
    raise exception 'player_not_in_game';
  end if;

  if v_player.user_id is distinct from v_user_id then
    raise exception 'player_not_owned_by_user';
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
  v_cell_id := coalesce(nullif(v_player_json->>'cellId', ''), '');
  v_params := public.get_deal_cell_params(v_cell_id);

  if v_params is null then
    raise exception 'not_deal_cell';
  end if;

  v_income := public.random_int_between(
    coalesce((v_params->>'incomeMin')::integer, 1000),
    coalesce((v_params->>'incomeMax')::integer, 10000)
  );
  v_importance := public.random_int_between(
    coalesce((v_params->>'importanceMin')::integer, 2),
    coalesce((v_params->>'importanceMax')::integer, 12)
  );
  v_turn_number := coalesce((v_game.state#>>'{turn,number}')::integer, 0);
  v_pending_action := jsonb_build_object(
    'id', v_pending_action_id,
    'type', 'deal_decision',
    'playerId', v_player.id,
    'cellId', v_cell_id,
    'payload', jsonb_build_object(
      'dealId', gen_random_uuid(),
      'income', v_income,
      'importance', v_importance,
      'decisions', jsonb_build_array('accept', 'decline')
    ),
    'createdAt', v_now
  );

  v_state := v_game.state;
  v_state := jsonb_set(v_state, '{pendingAction}', v_pending_action, true);
  v_state := jsonb_set(v_state, '{turn,phase}', to_jsonb('awaiting_decision'::text), true);
  v_state := jsonb_set(v_state, '{turn,pendingActionId}', to_jsonb(v_pending_action_id::text), true);
  v_state := jsonb_set(v_state, '{turn,finishedAt}', 'null'::jsonb, true);
  v_state := jsonb_set(v_state, '{updatedAt}', to_jsonb(v_now), true);

  update public.games
  set state = v_state
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
    nullif(v_turn_number, 0),
    v_player.id,
    'cell_deal_pending',
    'Deal card requested',
    v_pending_action->'payload'
  );

  return jsonb_build_object(
    'game_id', v_game.id,
    'player_id', v_player.id,
    'cell_id', v_cell_id,
    'cell_type', 'deal',
    'handled', true,
    'has_pending_action', true,
    'event_type', 'cell_deal_pending',
    'payload', v_pending_action->'payload',
    'state', v_state
  );
end;
$$;

create or replace function public.resolve_deal(
  p_game_id uuid,
  p_decision text
)
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
  v_pending_action jsonb;
  v_payload jsonb;
  v_state jsonb;
  v_player_index integer;
  v_turn_number integer;
  v_balance integer;
  v_image integer;
  v_successful_deals integer;
  v_failed_deals integer;
  v_income integer;
  v_importance integer;
  v_die_one integer := null;
  v_die_two integer := null;
  v_dice_sum integer := null;
  v_modified_result integer := null;
  v_decision text := lower(coalesce(nullif(btrim(p_decision), ''), ''));
  v_successful boolean := null;
  v_ring text;
  v_cell_id text;
  v_debt_locked boolean;
  v_now timestamptz := now();
begin
  if v_user_id is null then
    raise exception 'auth_required' using errcode = '28000';
  end if;

  if v_decision not in ('accept', 'decline') then
    raise exception 'invalid_deal_decision';
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

  v_pending_action := v_game.state->'pendingAction';

  if v_pending_action is null
    or v_pending_action = 'null'::jsonb
    or v_pending_action->>'type' <> 'deal_decision' then
    raise exception 'deal_pending_action_required';
  end if;

  select *
  into v_player
  from public.players
  where game_id = v_game.id
    and user_id = v_user_id;

  if not found then
    raise exception 'player_not_in_game';
  end if;

  if v_game.current_turn_player_id is distinct from v_player.id then
    raise exception 'not_your_turn';
  end if;

  if v_pending_action->>'playerId' <> v_player.id::text then
    raise exception 'pending_action_belongs_to_another_player';
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
  v_updated_player := v_player_json;
  v_payload := coalesce(v_pending_action->'payload', '{}'::jsonb);
  v_income := coalesce((v_payload->>'income')::integer, 0);
  v_importance := coalesce((v_payload->>'importance')::integer, 12);
  v_balance := coalesce((v_player_json->>'balance')::integer, 0);
  v_image := coalesce((v_player_json->>'image')::integer, 0);
  v_successful_deals := coalesce((v_player_json->>'successfulDeals')::integer, 0);
  v_failed_deals := coalesce((v_player_json->>'failedDeals')::integer, 0);
  v_ring := coalesce(nullif(v_player_json->>'ring', ''), 'inner');
  v_cell_id := coalesce(nullif(v_player_json->>'cellId', ''), v_pending_action->>'cellId');
  v_debt_locked := coalesce((v_player_json->>'debtLocked')::boolean, false);
  v_turn_number := coalesce((v_game.state#>>'{turn,number}')::integer, 0);

  if v_decision = 'accept' then
    v_die_one := public.random_int_between(1, 6);
    v_die_two := public.random_int_between(1, 6);
    v_dice_sum := v_die_one + v_die_two;
    v_modified_result := v_dice_sum + v_image;
    v_successful := v_modified_result >= v_importance;

    if v_successful then
      v_balance := v_balance + v_income;
      v_successful_deals := v_successful_deals + 1;
    else
      v_balance := v_balance - v_income;
      v_failed_deals := v_failed_deals + 1;
    end if;
  end if;

  if v_balance < 0 and v_ring = 'outer' then
    v_ring := 'inner';
    v_cell_id := 'inner-start-01';
    v_debt_locked := true;
  elsif v_balance >= 0 then
    v_debt_locked := false;
  end if;

  v_next_player_id := public.get_next_turn_player_id(v_game.id, v_player.id);

  if v_next_player_id is null then
    raise exception 'next_turn_player_not_found';
  end if;

  v_updated_player := jsonb_set(v_updated_player, '{balance}', to_jsonb(v_balance), true);
  v_updated_player := jsonb_set(v_updated_player, '{successfulDeals}', to_jsonb(v_successful_deals), true);
  v_updated_player := jsonb_set(v_updated_player, '{failedDeals}', to_jsonb(v_failed_deals), true);
  v_updated_player := jsonb_set(v_updated_player, '{ring}', to_jsonb(v_ring), true);
  v_updated_player := jsonb_set(v_updated_player, '{cellId}', to_jsonb(v_cell_id), true);
  v_updated_player := jsonb_set(v_updated_player, '{debtLocked}', to_jsonb(v_debt_locked), true);
  v_updated_player := jsonb_set(v_updated_player, '{updatedAt}', to_jsonb(v_now), true);

  v_state := v_game.state;
  v_state := jsonb_set(
    v_state,
    array['players', (v_player_index - 1)::text],
    v_updated_player,
    false
  );
  v_state := jsonb_set(v_state, '{pendingAction}', 'null'::jsonb, true);
  v_state := jsonb_set(v_state, '{currentTurnPlayerId}', to_jsonb(v_next_player_id::text), true);
  v_state := jsonb_set(v_state, '{turn,phase}', to_jsonb('finished'::text), true);
  v_state := jsonb_set(v_state, '{turn,pendingActionId}', 'null'::jsonb, true);
  v_state := jsonb_set(v_state, '{turn,finishedAt}', to_jsonb(v_now), true);
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
    nullif(v_turn_number, 0),
    v_player.id,
    case
      when v_decision = 'decline' then 'deal_declined'
      when v_successful then 'deal_successful'
      else 'deal_failed'
    end,
    case
      when v_decision = 'decline' then 'Deal declined'
      when v_successful then 'Deal successful'
      else 'Deal failed'
    end,
    jsonb_build_object(
      'decision', v_decision,
      'income', v_income,
      'importance', v_importance,
      'dice', case
        when v_decision = 'accept' then jsonb_build_array(v_die_one, v_die_two)
        else '[]'::jsonb
      end,
      'diceSum', v_dice_sum,
      'image', v_image,
      'modifiedResult', v_modified_result,
      'successful', v_successful,
      'nextPlayerId', v_next_player_id,
      'debtLocked', v_debt_locked
    )
  );

  return jsonb_build_object(
    'game_id', v_game.id,
    'player_id', v_player.id,
    'decision', v_decision,
    'income', v_income,
    'importance', v_importance,
    'dice', case
      when v_decision = 'accept' then jsonb_build_array(v_die_one, v_die_two)
      else '[]'::jsonb
    end,
    'dice_sum', v_dice_sum,
    'modified_result', v_modified_result,
    'successful', v_successful,
    'next_player_id', v_next_player_id,
    'state', v_state
  );
end;
$$;

grant execute on function public.resolve_deal(uuid, text) to authenticated;

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
  v_resolve_result jsonb := null;
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
  v_has_pending_action boolean := false;
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

  if v_game.state->'pendingAction' is not null
    and v_game.state->'pendingAction' <> 'null'::jsonb then
    raise exception 'pending_action_must_be_resolved';
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

  v_updated_player := jsonb_set(v_updated_player, '{cellId}', to_jsonb(v_to_cell_id), true);
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
    '{turn}',
    jsonb_build_object(
      'id', gen_random_uuid(),
      'gameId', v_game.id,
      'number', v_turn_number,
      'playerId', v_player.id,
      'phase', case when v_skipped then 'finished' else 'resolving_cell' end,
      'dice', case when v_skipped then '[]'::jsonb else jsonb_build_array(v_die) end,
      'fromCellId', v_from_cell_id,
      'toCellId', v_to_cell_id,
      'startedAt', v_now,
      'finishedAt', case when v_skipped then v_now else null end
    ),
    true
  );
  v_state := jsonb_set(v_state, '{pendingAction}', 'null'::jsonb, true);
  v_state := jsonb_set(v_state, '{updatedAt}', to_jsonb(v_now), true);

  update public.games
  set state = v_state
  where id = v_game.id
  returning * into v_game;

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
    case when v_skipped then 'Turn skipped' else 'Dice rolled' end,
    jsonb_build_object(
      'die', v_die,
      'fromCellId', v_from_cell_id,
      'toCellId', v_to_cell_id,
      'skipped', v_skipped
    )
  );

  if not v_skipped then
    if public.is_deal_cell(v_to_cell_id) then
      v_resolve_result := public.create_deal_pending_action(v_game.id, v_player.id);
    else
      v_resolve_result := public.resolve_cell_basic(v_game.id, v_player.id);
    end if;

    v_state := v_resolve_result->'state';
    v_has_pending_action := coalesce((v_resolve_result->>'has_pending_action')::boolean, false);
  else
    v_state := v_game.state;
  end if;

  if v_has_pending_action then
    v_next_player_id := v_player.id;
  else
    v_state := jsonb_set(
      v_state,
      '{currentTurnPlayerId}',
      to_jsonb(v_next_player_id::text),
      true
    );
    v_state := jsonb_set(v_state, '{updatedAt}', to_jsonb(now()), true);

    update public.games
    set
      current_turn_player_id = v_next_player_id,
      state = v_state
    where id = v_game.id
    returning state into v_state;
  end if;

  return jsonb_build_object(
    'game_id', v_game.id,
    'player_id', v_player.id,
    'die', v_die,
    'from_cell_id', v_from_cell_id,
    'to_cell_id', v_to_cell_id,
    'next_player_id', v_next_player_id,
    'skipped', v_skipped,
    'cell_result', v_resolve_result,
    'state', v_state
  );
end;
$$;
