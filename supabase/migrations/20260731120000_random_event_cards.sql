create or replace function public.resolve_random_event(
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
  v_pending_action jsonb;
  v_payload jsonb;
  v_players jsonb;
  v_player_json jsonb;
  v_updated_player jsonb;
  v_state jsonb;
  v_player_index integer;
  v_turn_number integer;
  v_decision text := lower(trim(coalesce(p_decision, '')));
  v_amount integer;
  v_balance_before integer;
  v_balance_after integer;
  v_debt_locked boolean;
  v_next_player_id uuid;
  v_now timestamptz := now();
begin
  if v_user_id is null then
    raise exception 'auth_required' using errcode = '28000';
  end if;

  if v_decision not in ('confirm', 'next') then
    raise exception 'invalid_random_event_decision';
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
    or v_pending_action->>'type' <> 'random_event' then
    raise exception 'random_event_pending_action_required';
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
  v_amount := coalesce(nullif(v_payload->>'amount', '')::integer, 0);
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
  v_balance_before := coalesce((v_player_json->>'balance')::integer, 0);
  v_balance_after := v_balance_before + v_amount;
  v_updated_player := public.apply_player_balance_state(v_updated_player, v_balance_after);
  v_balance_after := coalesce((v_updated_player->>'balance')::integer, v_balance_after);
  v_debt_locked := coalesce((v_updated_player->>'debtLocked')::boolean, false);
  v_turn_number := coalesce((v_game.state#>>'{turn,number}')::integer, 0);
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
    'random_event_applied',
    case
      when v_amount >= 0 then 'Позитивний випадок застосовано'
      else 'Негативний випадок застосовано'
    end,
    jsonb_build_object(
      'actionId', v_pending_action->>'id',
      'variantKey', v_payload->>'variantKey',
      'sign', v_payload->>'sign',
      'amount', v_amount,
      'balanceBefore', v_balance_before,
      'balance', v_balance_after,
      'debtLocked', v_debt_locked,
      'nextPlayerId', v_next_player_id
    )
  );

  return jsonb_build_object(
    'game_id', v_game.id,
    'player_id', v_player.id,
    'decision', v_decision,
    'amount', v_amount,
    'balance_before', v_balance_before,
    'balance_after', v_balance_after,
    'debt_locked', v_debt_locked,
    'next_player_id', v_next_player_id,
    'state', v_state
  );
end;
$$;

grant execute on function public.resolve_random_event(uuid, text) to authenticated;

create or replace function public.resolve_cell_basic(
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
  v_cell jsonb;
  v_params jsonb;
  v_pending_action jsonb := 'null'::jsonb;
  v_payload jsonb := '{}'::jsonb;
  v_player_index integer;
  v_turn_number integer;
  v_balance integer;
  v_image integer;
  v_inventory integer;
  v_skip_turns integer;
  v_amount integer;
  v_tax_amount integer;
  v_price integer;
  v_image_gain integer;
  v_cell_id text;
  v_cell_type text;
  v_event_type text := 'cell_unhandled';
  v_message text := 'Cell has no basic resolver';
  v_ring text;
  v_sign text;
  v_variant_key text;
  v_variant_keys text[] := array[
    'Investigation',
    'Law',
    'New_Style',
    'Phone',
    'New_movement',
    'Photo',
    'Press',
    'Building_School',
    'ADS',
    'Consultation',
    'Suit',
    'Help_OS',
    'Helper'
  ];
  v_has_pending_action boolean := false;
  v_handled boolean := false;
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

  if v_game.current_turn_player_id is null then
    raise exception 'current_turn_player_required';
  end if;

  if v_game.state->'pendingAction' is not null
    and v_game.state->'pendingAction' <> 'null'::jsonb then
    raise exception 'pending_action_must_be_resolved';
  end if;

  if p_player_id is not null then
    select *
    into v_player
    from public.players
    where game_id = v_game.id
      and id = p_player_id;
  else
    select *
    into v_player
    from public.players
    where game_id = v_game.id
      and id = v_game.current_turn_player_id;
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
  v_cell_id := coalesce(nullif(v_player_json->>'cellId', ''), 'inner-start-01');
  v_cell := public.get_board_cell_config(v_cell_id);
  v_cell_type := v_cell->>'type';
  v_params := coalesce(v_cell->'params', '{}'::jsonb);
  v_ring := coalesce(nullif(v_player_json->>'ring', ''), v_cell->>'ring', 'inner');
  v_balance := coalesce((v_player_json->>'balance')::integer, 0);
  v_image := coalesce((v_player_json->>'image')::integer, 0);
  v_inventory := coalesce((v_player_json->>'inventory')::integer, 0);
  v_skip_turns := coalesce((v_player_json->>'skipTurns')::integer, 0);
  v_turn_number := coalesce((v_game.state#>>'{turn,number}')::integer, 0);

  if v_cell is null then
    v_cell_type := 'unknown';
  elsif v_cell_type = 'start' then
    v_handled := true;
    v_event_type := 'cell_start';
    v_message := 'Start resolved';
    v_payload := jsonb_build_object('cellId', v_cell_id);
  elsif v_cell_type = 'salary' then
    v_handled := true;
    v_amount := case
      when v_image > 0 then v_image * coalesce((v_params->>'imageMultiplier')::integer, 500)
      else 0
    end;
    v_balance := v_balance + v_amount;
    v_event_type := 'cell_salary';
    v_message := 'Salary resolved';
    v_payload := jsonb_build_object(
      'cellId', v_cell_id,
      'amount', v_amount,
      'image', v_image
    );
  elsif v_cell_type = 'tax' then
    v_handled := true;
    v_tax_amount := floor(
      greatest(v_balance, 0) * coalesce((v_params->>'rate')::numeric, 0.2)
    )::integer;
    v_balance := v_balance - v_tax_amount;
    v_event_type := 'cell_tax';
    v_message := 'Tax resolved';
    v_payload := jsonb_build_object(
      'cellId', v_cell_id,
      'amount', v_tax_amount,
      'rate', coalesce((v_params->>'rate')::numeric, 0.2)
    );
  elsif v_cell_type = 'negative_reputation' or v_cell_type = 'positive_reputation' then
    v_handled := true;
    v_amount := coalesce((v_params->>'imageDelta')::integer, 0);
    v_image := v_image + v_amount;
    v_event_type := 'cell_reputation';
    v_message := 'Reputation resolved';
    v_payload := jsonb_build_object(
      'cellId', v_cell_id,
      'imageDelta', v_amount,
      'image', v_image
    );
  elsif v_cell_type = 'vacation' then
    v_handled := true;
    v_amount := coalesce((v_params->>'skipTurns')::integer, 1);
    v_skip_turns := v_skip_turns + v_amount;
    v_event_type := 'cell_vacation';
    v_message := 'Vacation resolved';
    v_payload := jsonb_build_object(
      'cellId', v_cell_id,
      'skipTurnsAdded', v_amount,
      'skipTurns', v_skip_turns
    );
  elsif v_cell_type = 'random' then
    v_handled := true;
    v_has_pending_action := true;
    v_event_type := 'cell_random_pending';
    v_message := 'Random event requested';
    v_sign := case when random() < 0.5 then 'positive' else 'negative' end;
    v_variant_key := v_variant_keys[
      public.random_int_between(1, array_length(v_variant_keys, 1))
    ];

    if v_sign = 'positive' then
      v_amount := public.random_int_between(1, 20) * 100;
    else
      v_amount := 0 - (public.random_int_between(10, 50) * 100);
    end if;

    v_pending_action := jsonb_build_object(
      'id', gen_random_uuid(),
      'type', 'random_event',
      'playerId', v_player.id,
      'cellId', v_cell_id,
      'payload', jsonb_build_object(
        'phase', 'ready',
        'variantKey', v_variant_key,
        'sign', v_sign,
        'amount', v_amount,
        'balanceBefore', v_balance,
        'positiveMin', 100,
        'positiveMax', 2000,
        'negativeMin', -5000,
        'negativeMax', -1000,
        'amountStep', 100,
        'decisions', jsonb_build_array('confirm')
      ),
      'createdAt', v_now
    );
    v_payload := v_pending_action->'payload';
  elsif v_cell_type = 'casino' then
    v_handled := true;
    v_has_pending_action := true;
    v_event_type := 'cell_casino_pending';
    v_message := 'Casino bet requested';
    v_pending_action := jsonb_build_object(
      'id', gen_random_uuid(),
      'type', 'casino_bet',
      'playerId', v_player.id,
      'cellId', v_cell_id,
      'payload', jsonb_build_object(
        'maxStake', greatest(v_balance, 0),
        'choices', jsonb_build_array('even', 'odd')
      ),
      'createdAt', v_now
    );
    v_payload := v_pending_action->'payload';
  elsif v_cell_type = 'image' then
    v_handled := true;
    v_has_pending_action := true;
    v_price := public.random_int_between(
      coalesce((v_params->>'priceMin')::integer, 100),
      coalesce((v_params->>'priceMax')::integer, 3000)
    );
    v_image_gain := public.random_int_between(
      coalesce((v_params->>'imageMin')::integer, 2),
      coalesce((v_params->>'imageMax')::integer, 5)
    );
    v_event_type := 'cell_image_pending';
    v_message := 'Image offer requested';
    v_pending_action := jsonb_build_object(
      'id', gen_random_uuid(),
      'type', 'image_offer',
      'playerId', v_player.id,
      'cellId', v_cell_id,
      'payload', jsonb_build_object(
        'price', v_price,
        'imageGain', v_image_gain,
        'canAfford', v_balance >= v_price
      ),
      'createdAt', v_now
    );
    v_payload := v_pending_action->'payload';
  elsif v_cell_type = 'advertising' then
    v_handled := true;
    v_has_pending_action := true;
    v_price := public.random_int_between(
      coalesce((v_params->>'priceMin')::integer, 100),
      coalesce((v_params->>'priceMax')::integer, 1000)
    );
    v_image_gain := public.random_int_between(
      coalesce((v_params->>'imageMin')::integer, 1),
      coalesce((v_params->>'imageMax')::integer, 10)
    );
    v_event_type := 'cell_advertising_pending';
    v_message := 'Advertising offer requested';
    v_pending_action := jsonb_build_object(
      'id', gen_random_uuid(),
      'type', 'advertising_offer',
      'playerId', v_player.id,
      'cellId', v_cell_id,
      'payload', jsonb_build_object(
        'price', v_price,
        'imageGain', v_image_gain,
        'canAfford', v_balance >= v_price
      ),
      'createdAt', v_now
    );
    v_payload := v_pending_action->'payload';
  end if;

  if not v_has_pending_action then
    if v_balance < 0 and v_ring = 'outer' then
      v_ring := 'inner';
      v_cell_id := 'inner-start-01';
      v_updated_player := jsonb_set(v_updated_player, '{debtLocked}', 'true'::jsonb, true);
      v_payload := v_payload || jsonb_build_object('debtLocked', true);
    elsif v_balance >= 0 then
      v_updated_player := jsonb_set(v_updated_player, '{debtLocked}', 'false'::jsonb, true);
    end if;
  end if;

  v_updated_player := jsonb_set(v_updated_player, '{balance}', to_jsonb(v_balance), true);
  v_updated_player := jsonb_set(v_updated_player, '{image}', to_jsonb(v_image), true);
  v_updated_player := jsonb_set(v_updated_player, '{inventory}', to_jsonb(v_inventory), true);
  v_updated_player := jsonb_set(v_updated_player, '{skipTurns}', to_jsonb(v_skip_turns), true);
  v_updated_player := jsonb_set(v_updated_player, '{ring}', to_jsonb(v_ring), true);
  v_updated_player := jsonb_set(v_updated_player, '{cellId}', to_jsonb(v_cell_id), true);
  v_updated_player := jsonb_set(v_updated_player, '{updatedAt}', to_jsonb(v_now), true);

  v_state := v_game.state;
  v_state := jsonb_set(
    v_state,
    array['players', (v_player_index - 1)::text],
    v_updated_player,
    false
  );
  v_state := jsonb_set(v_state, '{pendingAction}', v_pending_action, true);
  v_state := jsonb_set(
    v_state,
    '{turn,phase}',
    to_jsonb((case when v_has_pending_action then 'awaiting_decision' else 'finished' end)::text),
    true
  );
  v_state := jsonb_set(
    v_state,
    '{turn,finishedAt}',
    case when v_has_pending_action then 'null'::jsonb else to_jsonb(v_now) end,
    true
  );
  v_state := jsonb_set(v_state, '{updatedAt}', to_jsonb(v_now), true);

  update public.games
  set state = v_state
  where id = v_game.id
  returning state into v_state;

  if v_handled then
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
      v_message,
      v_payload
    );
  end if;

  return jsonb_build_object(
    'game_id', v_game.id,
    'player_id', v_player.id,
    'cell_id', v_cell_id,
    'cell_type', v_cell_type,
    'handled', v_handled,
    'has_pending_action', v_has_pending_action,
    'event_type', v_event_type,
    'payload', v_payload,
    'state', v_state
  );
end;
$$;

grant execute on function public.resolve_cell_basic(uuid, uuid) to authenticated;
