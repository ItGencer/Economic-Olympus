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
begin
  if v_balance < 0 then
    v_debt_locked := true;

    if v_ring = 'outer' then
      v_ring := 'inner';
      v_cell_id := 'inner-start-01';
    end if;
  elsif v_balance >= 0 then
    v_debt_locked := false;
  end if;

  v_player := jsonb_set(v_player, '{balance}', to_jsonb(v_balance), true);
  v_player := jsonb_set(v_player, '{ring}', to_jsonb(v_ring), true);
  v_player := jsonb_set(v_player, '{cellId}', to_jsonb(v_cell_id), true);
  v_player := jsonb_set(v_player, '{debtLocked}', to_jsonb(v_debt_locked), true);

  return v_player;
end;
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
      '{"coefficientMin":5,"coefficientMax":50,"unitValue":1000,"incomeMin":1000,"incomeMax":10000,"importanceMin":5,"importanceMax":50}'::jsonb
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
  v_coefficient integer;
  v_unit_value integer;
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

  v_coefficient := public.random_int_between(
    coalesce((v_params->>'coefficientMin')::integer, 5),
    coalesce((v_params->>'coefficientMax')::integer, 50)
  );
  v_unit_value := coalesce((v_params->>'unitValue')::integer, 1000);
  v_turn_number := coalesce((v_game.state#>>'{turn,number}')::integer, 0);
  v_pending_action := jsonb_build_object(
    'id', v_pending_action_id,
    'type', 'deal_decision',
    'playerId', v_player.id,
    'cellId', v_cell_id,
    'payload', jsonb_build_object(
      'dealId', gen_random_uuid(),
      'phase', 'initial',
      'coefficient', v_coefficient,
      'importance', v_coefficient,
      'unitValue', v_unit_value,
      'decisions', jsonb_build_array('roll', 'decline')
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
    'Ділова зустріч очікує рішення',
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
  v_successful_deals := coalesce((v_player_json->>'successfulDeals')::integer, 0);
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
    v_balance := v_balance + v_amount;

    if v_successful then
      v_successful_deals := v_successful_deals + 1;
    else
      v_failed_deals := v_failed_deals + 1;
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
      when v_decision = 'decline' then 'Відмова від ділової зустрічі'
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
    'coefficient', v_coefficient,
    'die', v_die,
    'score', v_score,
    'image', v_image,
    'amount', case when v_decision = 'decline' then 0 else v_amount end,
    'successful', v_successful,
    'has_pending_action', v_transition_pending,
    'pending_action', case when v_transition_pending then v_transition_action else null end,
    'next_player_id', case when v_transition_pending then null else v_next_player_id end,
    'state', v_state
  );
end;
$$;

grant execute on function public.resolve_deal(uuid, text) to authenticated;

create or replace function public.resolve_casino_bet(
  p_game_id uuid,
  p_decision text,
  p_bet_amount integer,
  p_parity text
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
  v_pending_action jsonb;
  v_payload jsonb;
  v_players jsonb;
  v_player_json jsonb;
  v_updated_player jsonb;
  v_state jsonb;
  v_player_index integer;
  v_balance integer;
  v_ring text;
  v_cell_id text;
  v_debt_locked boolean;
  v_next_player_id uuid;
  v_turn_number integer;
  v_decision text := lower(trim(coalesce(p_decision, '')));
  v_phase text;
  v_parity text := lower(trim(coalesce(p_parity, '')));
  v_bet_amount integer := coalesce(p_bet_amount, 0);
  v_die_one integer := null;
  v_die_two integer := null;
  v_total integer := null;
  v_multiplier integer := null;
  v_payout integer := 0;
  v_won boolean := false;
  v_now timestamptz := now();
begin
  if v_user_id is null then
    raise exception 'auth_required' using errcode = '28000';
  end if;

  if v_decision not in ('decline', 'roll', 'multiplier', 'collect') then
    raise exception 'invalid_casino_decision';
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
    or v_pending_action->>'type' <> 'casino_bet' then
    raise exception 'casino_pending_action_required';
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
  v_ring := coalesce(nullif(v_player_json->>'ring', ''), 'inner');
  v_cell_id := coalesce(nullif(v_player_json->>'cellId', ''), v_pending_action->>'cellId');
  v_debt_locked := coalesce((v_player_json->>'debtLocked')::boolean, false);
  v_turn_number := coalesce((v_game.state#>>'{turn,number}')::integer, 0);

  if v_decision = 'roll' then
    if v_phase <> 'initial' then
      raise exception 'casino_roll_already_resolved';
    end if;

    if v_balance <= 0 then
      raise exception 'casino_positive_balance_required';
    end if;

    if v_bet_amount < 0 then
      raise exception 'casino_bet_must_not_be_negative';
    end if;

    if v_balance < v_bet_amount then
      raise exception 'casino_bet_exceeds_balance';
    end if;

    if v_parity not in ('even', 'odd') then
      raise exception 'casino_parity_required';
    end if;

    v_die_one := public.random_int_between(1, 6);
    v_die_two := public.random_int_between(1, 6);
    v_total := v_die_one + v_die_two;
    v_won := (v_total % 2 = 0 and v_parity = 'even')
      or (v_total % 2 = 1 and v_parity = 'odd');

    v_payload := v_payload || jsonb_build_object(
      'phase', 'dice_rolled',
      'betAmount', v_bet_amount,
      'parity', v_parity,
      'dice', jsonb_build_array(v_die_one, v_die_two),
      'total', v_total,
      'won', v_won,
      'multiplier', null,
      'payout', 0
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
      'state', v_state
    );
  end if;

  if v_decision = 'multiplier' then
    if v_phase <> 'dice_rolled' then
      raise exception 'casino_dice_roll_required';
    end if;

    v_won := coalesce((v_payload->>'won')::boolean, false);

    if not v_won then
      raise exception 'casino_multiplier_requires_win';
    end if;

    v_bet_amount := coalesce((v_payload->>'betAmount')::integer, 0);

    if v_bet_amount < 0 then
      raise exception 'casino_bet_must_not_be_negative';
    end if;

    v_multiplier := public.random_int_between(2, 10);
    v_payout := v_bet_amount * v_multiplier;

    v_payload := v_payload || jsonb_build_object(
      'phase', 'multiplier_ready',
      'multiplier', v_multiplier,
      'payout', v_payout
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
      'state', v_state
    );
  end if;

  if v_decision = 'decline' then
    if v_phase <> 'initial' then
      raise exception 'casino_already_started';
    end if;
  else
    if v_phase not in ('dice_rolled', 'multiplier_ready') then
      raise exception 'casino_collect_not_ready';
    end if;

    v_bet_amount := coalesce((v_payload->>'betAmount')::integer, 0);
    v_parity := coalesce(nullif(v_payload->>'parity', ''), '');
    v_die_one := coalesce((v_payload#>>'{dice,0}')::integer, null);
    v_die_two := coalesce((v_payload#>>'{dice,1}')::integer, null);
    v_total := coalesce((v_payload->>'total')::integer, null);
    v_won := coalesce((v_payload->>'won')::boolean, false);
    v_multiplier := coalesce((v_payload->>'multiplier')::integer, null);
    v_payout := coalesce((v_payload->>'payout')::integer, 0);

    if v_won and v_phase <> 'multiplier_ready' then
      raise exception 'casino_multiplier_required';
    end if;

    if v_won then
      v_balance := v_balance + v_payout;
    else
      if v_balance < v_bet_amount then
        raise exception 'casino_bet_exceeds_balance';
      end if;

      v_balance := v_balance - v_bet_amount;
    end if;

    v_updated_player := public.apply_player_balance_state(v_updated_player, v_balance);
    v_balance := coalesce((v_updated_player->>'balance')::integer, v_balance);
    v_ring := coalesce(nullif(v_updated_player->>'ring', ''), v_ring);
    v_cell_id := coalesce(nullif(v_updated_player->>'cellId', ''), v_cell_id);
    v_debt_locked := coalesce((v_updated_player->>'debtLocked')::boolean, v_debt_locked);
  end if;

  v_next_player_id := public.get_next_turn_player_id(v_game.id, v_player.id);

  if v_next_player_id is null then
    raise exception 'next_turn_player_not_found';
  end if;

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
      when v_decision = 'decline' then 'casino_declined'
      when v_won then 'casino_won'
      else 'casino_lost'
    end,
    case
      when v_decision = 'decline' then 'Casino declined'
      when v_won then 'Casino won'
      else 'Casino lost'
    end,
    jsonb_build_object(
      'actionId', v_pending_action->>'id',
      'decision', v_decision,
      'betAmount', case when v_decision = 'decline' then null else v_bet_amount end,
      'parity', case when v_decision = 'decline' then null else v_parity end,
      'dice', case when v_decision = 'decline' then '[]'::jsonb else jsonb_build_array(v_die_one, v_die_two) end,
      'total', v_total,
      'multiplier', v_multiplier,
      'won', case when v_decision = 'decline' then null else v_won end,
      'payout', v_payout,
      'balance', v_balance,
      'nextPlayerId', v_next_player_id,
      'debtLocked', v_debt_locked
    )
  );

  return jsonb_build_object(
    'game_id', v_game.id,
    'player_id', v_player.id,
    'decision', v_decision,
    'next_player_id', v_next_player_id,
    'state', v_state
  );
end;
$$;

grant execute on function public.resolve_casino_bet(uuid, text, integer, text) to authenticated;
