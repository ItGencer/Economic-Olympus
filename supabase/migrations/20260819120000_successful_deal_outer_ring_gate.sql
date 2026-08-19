create or replace function public.apply_player_balance_state(
  p_player jsonb,
  p_balance integer
)
returns jsonb
language plpgsql
immutable
set search_path = public
as $$
declare
  v_player jsonb := coalesce(p_player, '{}'::jsonb);
  v_balance integer := coalesce(p_balance, 0);
  v_ring text := coalesce(nullif(v_player->>'ring', ''), 'inner');
  v_cell_id text := coalesce(nullif(v_player->>'cellId', ''), 'inner-start-01');
  v_debt_locked boolean := coalesce((v_player->>'debtLocked')::boolean, false);
  v_debt_warning boolean := coalesce((v_player->>'debtWarning')::boolean, false);
  v_eliminated boolean := coalesce((v_player->>'eliminated')::boolean, false);
begin
  if v_balance < 0 then
    v_debt_locked := true;
    v_player := jsonb_set(v_player, '{successfulDeals}', '0'::jsonb, true);

    if v_ring = 'outer' then
      v_ring := 'inner';
      v_cell_id := 'inner-start-01';
    end if;
  elsif v_balance >= 0 then
    v_debt_locked := false;
  end if;

  v_eliminated := v_eliminated or v_balance <= -100000;
  v_debt_warning := v_eliminated or v_balance < -50000;

  v_player := jsonb_set(v_player, '{balance}', to_jsonb(v_balance), true);
  v_player := jsonb_set(v_player, '{ring}', to_jsonb(v_ring), true);
  v_player := jsonb_set(v_player, '{cellId}', to_jsonb(v_cell_id), true);
  v_player := jsonb_set(v_player, '{debtLocked}', to_jsonb(v_debt_locked), true);
  v_player := jsonb_set(v_player, '{debtWarning}', to_jsonb(v_debt_warning), true);
  v_player := jsonb_set(v_player, '{eliminated}', to_jsonb(v_eliminated), true);

  return v_player;
end;
$$;

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
  v_required_successful_deals integer := 5;
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
  v_ring := coalesce(nullif(v_player_json->>'ring', ''), 'inner');
  v_cell_id := coalesce(nullif(v_player_json->>'cellId', ''), v_pending_action->>'cellId', 'inner-start-01');
  v_debt_locked := coalesce((v_player_json->>'debtLocked')::boolean, false);
  v_turn_number := coalesce((v_game.state#>>'{turn,number}')::integer, 0);

  if v_balance < 0 then
    v_debt_locked := true;
    v_successful_deals := 0;
  end if;

  if v_decision = 'move_to_outer' then
    if v_ring <> 'inner' then
      raise exception 'outer_transition_requires_inner_ring';
    end if;

    if v_balance < 0 then
      raise exception 'outer_transition_requires_no_debt';
    end if;

    if v_debt_locked then
      raise exception 'outer_transition_blocked_by_debt';
    end if;

    if v_successful_deals < v_required_successful_deals then
      raise exception 'outer_transition_requires_successful_deals';
    end if;

    v_ring := 'outer';
    v_cell_id := v_outer_entry_cell_id;
  else
    v_successful_deals := 0;

    if v_balance >= 0 then
      v_debt_locked := false;
    end if;
  end if;

  v_next_player_id := public.get_next_turn_player_id(v_game.id, v_player.id);

  if v_next_player_id is null then
    raise exception 'next_turn_player_not_found';
  end if;

  v_updated_player := jsonb_set(v_updated_player, '{ring}', to_jsonb(v_ring), true);
  v_updated_player := jsonb_set(v_updated_player, '{cellId}', to_jsonb(v_cell_id), true);
  v_updated_player := jsonb_set(v_updated_player, '{debtLocked}', to_jsonb(v_debt_locked), true);
  v_updated_player := jsonb_set(v_updated_player, '{successfulDeals}', to_jsonb(v_successful_deals), true);
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
    case when v_decision = 'move_to_outer' then 'Moved to outer ring' else 'Stayed on inner ring and reset successful deals' end,
    jsonb_build_object(
      'decision', v_decision,
      'requiredSuccessfulDeals', v_required_successful_deals,
      'successfulDeals', v_successful_deals,
      'successfulDealUser', v_successful_deals,
      'balance', v_balance,
      'ring', v_ring,
      'cellId', v_cell_id,
      'debtLocked', v_debt_locked,
      'nextPlayerId', v_next_player_id,
      'payload', v_payload
    )
  );

  return jsonb_build_object(
    'game_id', v_game.id,
    'player_id', v_player.id,
    'decision', v_decision,
    'ring', v_ring,
    'cell_id', v_cell_id,
    'successful_deals', v_successful_deals,
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
  v_balance_before integer;
  v_image integer;
  v_successful_deals integer;
  v_failed_deals integer;
  v_coefficient integer;
  v_unit_value integer;
  v_die integer := null;
  v_score integer := null;
  v_difference integer := null;
  v_amount integer := 0;
  v_decision text := lower(coalesce(nullif(btrim(p_decision), ''), ''));
  v_phase text;
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

  if v_decision = 'accept' then
    v_decision := 'roll';
  end if;

  if v_decision not in ('roll', 'decline', 'confirm') then
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

  v_payload := coalesce(v_pending_action->'payload', '{}'::jsonb);
  v_phase := coalesce(nullif(v_payload->>'phase', ''), 'initial');
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
  v_image := coalesce((v_player_json->>'image')::integer, 0);
  v_successful_deals := case
    when v_balance < 0 then 0
    else coalesce((v_player_json->>'successfulDeals')::integer, 0)
  end;
  v_failed_deals := coalesce((v_player_json->>'failedDeals')::integer, 0);
  v_ring := coalesce(nullif(v_player_json->>'ring', ''), 'inner');
  v_cell_id := coalesce(nullif(v_player_json->>'cellId', ''), v_pending_action->>'cellId');
  v_debt_locked := coalesce((v_player_json->>'debtLocked')::boolean, false);
  v_turn_number := coalesce((v_game.state#>>'{turn,number}')::integer, 0);
  v_coefficient := coalesce(
    nullif(v_payload->>'coefficient', '')::integer,
    nullif(v_payload->>'importance', '')::integer,
    public.random_int_between(5, 50)
  );
  v_unit_value := coalesce(nullif(v_payload->>'unitValue', '')::integer, 1000);

  if v_decision = 'roll' then
    if v_phase <> 'initial' then
      raise exception 'deal_roll_already_resolved';
    end if;

    v_die := public.random_int_between(1, 20);
    v_score := v_coefficient + v_die;
    v_difference := v_image - v_score;
    v_amount := v_difference * v_unit_value;
    v_successful := v_score <= v_image;

    v_payload := v_payload || jsonb_build_object(
      'phase', 'rolled',
      'decision', 'accept',
      'coefficient', v_coefficient,
      'importance', v_coefficient,
      'unitValue', v_unit_value,
      'die', v_die,
      'score', v_score,
      'image', v_image,
      'difference', v_difference,
      'amount', v_amount,
      'successful', v_successful,
      'decisions', jsonb_build_array('confirm')
    );

    v_pending_action := jsonb_set(v_pending_action, '{payload}', v_payload, true);
    v_state := jsonb_set(v_game.state, '{pendingAction}', v_pending_action, true);
    v_state := jsonb_set(v_state, '{updatedAt}', to_jsonb(v_now), true);

    update public.games
    set state = v_state
    where id = v_game.id
    returning state into v_state;

    return jsonb_build_object(
      'game_id', v_game.id,
      'player_id', v_player.id,
      'decision', v_decision,
      'die', v_die,
      'score', v_score,
      'amount', v_amount,
      'successful', v_successful,
      'state', v_state
    );
  end if;

  if v_decision = 'decline' then
    if v_phase <> 'initial' then
      raise exception 'deal_already_started';
    end if;

    if v_balance < 0 then
      v_successful_deals := 0;
      v_updated_player := public.apply_player_balance_state(v_updated_player, v_balance);
      v_ring := coalesce(nullif(v_updated_player->>'ring', ''), v_ring);
      v_cell_id := coalesce(nullif(v_updated_player->>'cellId', ''), v_cell_id);
      v_debt_locked := coalesce((v_updated_player->>'debtLocked')::boolean, v_debt_locked);
    end if;
  else
    if v_phase <> 'rolled' then
      raise exception 'deal_roll_required';
    end if;

    v_die := nullif(v_payload->>'die', '')::integer;

    if v_die is null then
      raise exception 'deal_roll_required';
    end if;

    v_image := coalesce(nullif(v_payload->>'image', '')::integer, v_image);
    v_score := coalesce(nullif(v_payload->>'score', '')::integer, v_coefficient + v_die);
    v_difference := coalesce(nullif(v_payload->>'difference', '')::integer, v_image - v_score);
    v_amount := coalesce(nullif(v_payload->>'amount', '')::integer, v_difference * v_unit_value);
    v_successful := coalesce(nullif(v_payload->>'successful', '')::boolean, v_score <= v_image);
    v_balance_before := v_balance;
    v_balance := v_balance + v_amount;

    if v_successful then
      if v_balance_before >= 0 and v_balance >= 0 then
        v_successful_deals := v_successful_deals + 1;
      else
        v_successful_deals := 0;
      end if;
    else
      v_failed_deals := v_failed_deals + 1;
    end if;

    if v_balance < 0 then
      v_successful_deals := 0;
    end if;

    v_updated_player := public.apply_player_balance_state(v_updated_player, v_balance);
    v_balance := coalesce((v_updated_player->>'balance')::integer, v_balance);
    v_ring := coalesce(nullif(v_updated_player->>'ring', ''), v_ring);
    v_cell_id := coalesce(nullif(v_updated_player->>'cellId', ''), v_cell_id);
    v_debt_locked := coalesce((v_updated_player->>'debtLocked')::boolean, v_debt_locked);
  end if;

  v_transition_pending := v_decision = 'confirm'
    and v_successful is true
    and v_ring = 'inner'
    and v_balance >= 0
    and not v_debt_locked
    and v_successful_deals >= 5;

  if v_transition_pending then
    v_transition_action := jsonb_build_object(
      'id', v_transition_action_id,
      'type', 'outer_ring_choice',
      'playerId', v_player.id,
      'cellId', v_cell_id,
      'payload', jsonb_build_object(
        'message', 'У вас 5 вдалих угод у Вас немає боргів. Ви можете перейти на зовнішнє коло',
        'requiredSuccessfulDeals', 5,
        'successfulDeals', v_successful_deals,
        'successfulDealUser', v_successful_deals,
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

  v_updated_player := jsonb_set(v_updated_player, '{successfulDeals}', to_jsonb(v_successful_deals), true);
  v_updated_player := jsonb_set(v_updated_player, '{failedDeals}', to_jsonb(v_failed_deals), true);
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
      when v_decision = 'decline' then 'Ділову зустріч відхилено'
      when v_successful then 'Ділова зустріч успішна'
      else 'Ділову зустріч провалено'
    end,
    jsonb_build_object(
      'actionId', v_pending_action->>'id',
      'decision', case when v_decision = 'decline' then 'decline' else 'accept' end,
      'coefficient', v_coefficient,
      'importance', v_coefficient,
      'unitValue', v_unit_value,
      'die', v_die,
      'score', v_score,
      'image', v_image,
      'difference', v_difference,
      'amount', case when v_decision = 'decline' then 0 else v_amount end,
      'balance', v_balance,
      'successful', v_successful,
      'successfulDeals', v_successful_deals,
      'successfulDealUser', v_successful_deals,
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
      'Outer ring choice requested after 5 successful deals',
      v_transition_action->'payload'
    );
  end if;

  return jsonb_build_object(
    'game_id', v_game.id,
    'player_id', v_player.id,
    'decision', v_decision,
    'coefficient', v_coefficient,
    'die', v_die,
    'score', v_score,
    'image', v_image,
    'amount', case when v_decision = 'decline' then 0 else v_amount end,
    'successful', v_successful,
    'successful_deals', v_successful_deals,
    'has_pending_action', v_transition_pending,
    'pending_action', case when v_transition_pending then v_transition_action else null end,
    'next_player_id', case when v_transition_pending then null else v_next_player_id end,
    'state', v_state
  );
end;
$$;

grant execute on function public.resolve_deal(uuid, text) to authenticated;
