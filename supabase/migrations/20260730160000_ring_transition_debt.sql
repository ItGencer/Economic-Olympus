create or replace function public.get_outer_entry_cell_id()
returns text
language sql
immutable
security definer
set search_path = public
as $$
  select 'outer-image-01';
$$;

create or replace function public.handle_debt(
  p_game_id uuid,
  p_player_id uuid default null
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
  v_updated_player jsonb;
  v_state jsonb;
  v_player_index integer;
  v_turn_number integer;
  v_balance integer;
  v_ring text;
  v_cell_id text;
  v_debt_locked boolean;
  v_changed boolean := false;
  v_event_type text := 'debt_unchanged';
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

  if v_game.state->'pendingAction' is not null
    and v_game.state->'pendingAction' <> 'null'::jsonb then
    raise exception 'pending_action_must_be_resolved';
  end if;

  if p_player_id is null then
    select *
    into v_player
    from public.players
    where game_id = v_game.id
      and user_id = v_user_id;
  else
    select *
    into v_player
    from public.players
    where game_id = v_game.id
      and id = p_player_id;
  end if;

  if not found then
    raise exception 'player_not_in_game';
  end if;

  if v_player.user_id is distinct from v_user_id then
    raise exception 'player_not_owned_by_user';
  end if;

  if v_game.current_turn_player_id is distinct from v_player.id then
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
  v_updated_player := v_player_json;
  v_balance := coalesce((v_player_json->>'balance')::integer, 0);
  v_ring := coalesce(nullif(v_player_json->>'ring', ''), 'inner');
  v_cell_id := coalesce(nullif(v_player_json->>'cellId', ''), 'inner-start-01');
  v_debt_locked := coalesce((v_player_json->>'debtLocked')::boolean, false);
  v_turn_number := coalesce((v_game.state#>>'{turn,number}')::integer, 0);

  if v_balance < 0 and v_ring = 'outer' then
    v_ring := 'inner';
    v_cell_id := 'inner-start-01';
    v_debt_locked := true;
    v_changed := true;
    v_event_type := 'debt_locked';
  elsif v_balance >= 0 and v_debt_locked then
    v_debt_locked := false;
    v_changed := true;
    v_event_type := 'debt_unlocked';
  end if;

  if v_changed then
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
      v_event_type,
      case when v_event_type = 'debt_locked' then 'Debt locked' else 'Debt unlocked' end,
      jsonb_build_object(
        'balance', v_balance,
        'ring', v_ring,
        'cellId', v_cell_id,
        'debtLocked', v_debt_locked
      )
    );
  else
    v_state := v_game.state;
  end if;

  return jsonb_build_object(
    'game_id', v_game.id,
    'player_id', v_player.id,
    'changed', v_changed,
    'balance', v_balance,
    'ring', v_ring,
    'cell_id', v_cell_id,
    'debt_locked', v_debt_locked,
    'state', v_state
  );
end;
$$;

grant execute on function public.handle_debt(uuid, uuid) to authenticated;

create or replace function public.ring_transition(
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
  v_successful_deals integer;
  v_required_successful_deals integer;
  v_decision text := lower(coalesce(nullif(btrim(p_decision), ''), ''));
  v_ring text;
  v_cell_id text;
  v_debt_locked boolean;
  v_outer_entry_cell_id text := public.get_outer_entry_cell_id();
  v_now timestamptz := now();
begin
  if v_user_id is null then
    raise exception 'auth_required' using errcode = '28000';
  end if;

  if v_decision not in ('move_to_outer', 'stay_inner') then
    raise exception 'invalid_ring_transition_decision';
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
    or v_pending_action->>'type' <> 'outer_ring_choice' then
    raise exception 'outer_ring_choice_required';
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
  v_balance := coalesce((v_player_json->>'balance')::integer, 0);
  v_successful_deals := coalesce((v_player_json->>'successfulDeals')::integer, 0);
  v_required_successful_deals := coalesce((v_payload->>'requiredSuccessfulDeals')::integer, 7);
  v_ring := coalesce(nullif(v_player_json->>'ring', ''), 'inner');
  v_cell_id := coalesce(nullif(v_player_json->>'cellId', ''), v_pending_action->>'cellId', 'inner-start-01');
  v_debt_locked := coalesce((v_player_json->>'debtLocked')::boolean, false);
  v_turn_number := coalesce((v_game.state#>>'{turn,number}')::integer, 0);

  if v_decision = 'move_to_outer' then
    if v_ring <> 'inner' then
      raise exception 'outer_transition_requires_inner_ring';
    end if;

    if v_balance <= 0 then
      raise exception 'outer_transition_requires_positive_balance';
    end if;

    if v_debt_locked then
      raise exception 'outer_transition_blocked_by_debt';
    end if;

    if v_successful_deals < v_required_successful_deals then
      raise exception 'outer_transition_requires_successful_deals';
    end if;

    v_ring := 'outer';
    v_cell_id := v_outer_entry_cell_id;
  elsif v_balance >= 0 then
    v_debt_locked := false;
  end if;

  v_next_player_id := public.get_next_turn_player_id(v_game.id, v_player.id);

  if v_next_player_id is null then
    raise exception 'next_turn_player_not_found';
  end if;

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
    case when v_decision = 'move_to_outer' then 'outer_ring_moved' else 'outer_ring_stayed' end,
    case when v_decision = 'move_to_outer' then 'Moved to outer ring' else 'Stayed on inner ring' end,
    jsonb_build_object(
      'decision', v_decision,
      'requiredSuccessfulDeals', v_required_successful_deals,
      'successfulDeals', v_successful_deals,
      'balance', v_balance,
      'ring', v_ring,
      'cellId', v_cell_id,
      'debtLocked', v_debt_locked,
      'nextPlayerId', v_next_player_id
    )
  );

  return jsonb_build_object(
    'game_id', v_game.id,
    'player_id', v_player.id,
    'decision', v_decision,
    'ring', v_ring,
    'cell_id', v_cell_id,
    'next_player_id', v_next_player_id,
    'state', v_state
  );
end;
$$;

grant execute on function public.ring_transition(uuid, text) to authenticated;

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
  v_transition_pending boolean := false;
  v_transition_action_id uuid := gen_random_uuid();
  v_transition_action jsonb := 'null'::jsonb;
  v_outer_entry_cell_id text := public.get_outer_entry_cell_id();
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

  v_transition_pending := (v_successful is true)
    and v_ring = 'inner'
    and v_balance > 0
    and not v_debt_locked
    and v_successful_deals >= 7;

  if v_transition_pending then
    v_transition_action := jsonb_build_object(
      'id', v_transition_action_id,
      'type', 'outer_ring_choice',
      'playerId', v_player.id,
      'cellId', v_cell_id,
      'payload', jsonb_build_object(
        'requiredSuccessfulDeals', 7,
        'mandatoryAtSuccessfulDeals', 10,
        'successfulDeals', v_successful_deals,
        'balance', v_balance,
        'debtLocked', v_debt_locked,
        'targetRing', 'outer',
        'targetCellId', v_outer_entry_cell_id,
        'choices', jsonb_build_array('move_to_outer', 'stay_inner')
      ),
      'createdAt', v_now
    );
  else
    v_next_player_id := public.get_next_turn_player_id(v_game.id, v_player.id);

    if v_next_player_id is null then
      raise exception 'next_turn_player_not_found';
    end if;
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
  v_state := jsonb_set(v_state, '{pendingAction}', v_transition_action, true);
  v_state := jsonb_set(
    v_state,
    '{currentTurnPlayerId}',
    to_jsonb((case when v_transition_pending then v_player.id else v_next_player_id end)::text),
    true
  );
  v_state := jsonb_set(
    v_state,
    '{turn,phase}',
    to_jsonb((case when v_transition_pending then 'awaiting_decision' else 'finished' end)::text),
    true
  );
  v_state := jsonb_set(
    v_state,
    '{turn,pendingActionId}',
    case when v_transition_pending then to_jsonb(v_transition_action_id::text) else 'null'::jsonb end,
    true
  );
  v_state := jsonb_set(
    v_state,
    '{turn,finishedAt}',
    case when v_transition_pending then 'null'::jsonb else to_jsonb(v_now) end,
    true
  );
  v_state := jsonb_set(v_state, '{updatedAt}', to_jsonb(v_now), true);

  update public.games
  set
    current_turn_player_id = case when v_transition_pending then v_player.id else v_next_player_id end,
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
      'successfulDeals', v_successful_deals,
      'hasPendingAction', v_transition_pending,
      'pendingActionType', case when v_transition_pending then 'outer_ring_choice' else null end,
      'nextPlayerId', case when v_transition_pending then null else v_next_player_id end,
      'debtLocked', v_debt_locked
    )
  );

  if v_transition_pending then
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
      'outer_ring_choice_pending',
      'Outer ring choice requested',
      v_transition_action->'payload'
    );
  end if;

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
    'has_pending_action', v_transition_pending,
    'pending_action', case when v_transition_pending then v_transition_action else null end,
    'next_player_id', case when v_transition_pending then null else v_next_player_id end,
    'state', v_state
  );
end;
$$;

grant execute on function public.resolve_deal(uuid, text) to authenticated;
