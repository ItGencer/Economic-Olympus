create or replace function public.random_int_between(
  p_min integer,
  p_max integer
)
returns integer
language sql
volatile
security definer
set search_path = public
as $$
  select floor(
    random() * (greatest(p_min, p_max) - least(p_min, p_max) + 1)
  )::integer + least(p_min, p_max);
$$;

create or replace function public.get_board_cell_config(p_cell_id text)
returns jsonb
language sql
immutable
security definer
set search_path = public
as $$
  with cells(id, ring, cell_type, params) as (
    values
      ('inner-start-01', 'inner', 'start', '{"label":"Start"}'::jsonb),
      ('inner-casino-02', 'inner', 'casino', '{"label":"Casino"}'::jsonb),
      ('inner-random-03', 'inner', 'random', '{"label":"Random","minAmount":100,"maxAmount":2000}'::jsonb),
      ('inner-vacation-04', 'inner', 'vacation', '{"label":"Vacation","skipTurns":1}'::jsonb),
      ('inner-image-06', 'inner', 'image', '{"label":"Image","priceMin":100,"priceMax":3000,"imageMin":2,"imageMax":5}'::jsonb),
      ('inner-negative-reputation-07', 'inner', 'negative_reputation', '{"label":"Negative reputation","imageDelta":-1}'::jsonb),
      ('inner-salary-08', 'inner', 'salary', '{"label":"Salary","imageMultiplier":500}'::jsonb),
      ('inner-random-10', 'inner', 'random', '{"label":"Random","minAmount":100,"maxAmount":2500}'::jsonb),
      ('inner-casino-11', 'inner', 'casino', '{"label":"Casino"}'::jsonb),
      ('inner-image-12', 'inner', 'image', '{"label":"Image","priceMin":100,"priceMax":3000,"imageMin":2,"imageMax":5}'::jsonb),
      ('inner-vacation-13', 'inner', 'vacation', '{"label":"Vacation","skipTurns":1}'::jsonb),
      ('inner-negative-reputation-15', 'inner', 'negative_reputation', '{"label":"Negative reputation","imageDelta":-1}'::jsonb),
      ('inner-salary-16', 'inner', 'salary', '{"label":"Salary","imageMultiplier":500}'::jsonb),
      ('outer-image-01', 'outer', 'image', '{"label":"Image","entry":true,"priceMin":100,"priceMax":3000,"imageMin":2,"imageMax":5}'::jsonb),
      ('outer-tax-03', 'outer', 'tax', '{"label":"Tax","rate":0.2}'::jsonb),
      ('outer-advertising-05', 'outer', 'advertising', '{"label":"Advertising","priceMin":100,"priceMax":1000,"imageMin":1,"imageMax":10}'::jsonb),
      ('outer-casino-06', 'outer', 'casino', '{"label":"Casino"}'::jsonb),
      ('outer-negative-reputation-09', 'outer', 'negative_reputation', '{"label":"Negative reputation","imageDelta":-1}'::jsonb),
      ('outer-salary-12', 'outer', 'salary', '{"label":"Salary","imageMultiplier":500}'::jsonb),
      ('outer-random-13', 'outer', 'random', '{"label":"Random","minAmount":500,"maxAmount":5000}'::jsonb),
      ('outer-positive-reputation-15', 'outer', 'positive_reputation', '{"label":"Positive reputation","imageDelta":1}'::jsonb),
      ('outer-vacation-17', 'outer', 'vacation', '{"label":"Vacation","skipTurns":1}'::jsonb),
      ('outer-tax-20', 'outer', 'tax', '{"label":"Tax","rate":0.2}'::jsonb),
      ('outer-advertising-23', 'outer', 'advertising', '{"label":"Advertising","priceMin":100,"priceMax":1000,"imageMin":1,"imageMax":10}'::jsonb),
      ('outer-casino-24', 'outer', 'casino', '{"label":"Casino"}'::jsonb),
      ('outer-image-28', 'outer', 'image', '{"label":"Image","priceMin":100,"priceMax":3000,"imageMin":2,"imageMax":5}'::jsonb),
      ('outer-random-29', 'outer', 'random', '{"label":"Random","minAmount":500,"maxAmount":5000}'::jsonb),
      ('outer-positive-reputation-31', 'outer', 'positive_reputation', '{"label":"Positive reputation","imageDelta":1}'::jsonb),
      ('outer-salary-32', 'outer', 'salary', '{"label":"Salary","imageMultiplier":500}'::jsonb)
  )
  select jsonb_build_object(
    'id', cells.id,
    'ring', cells.ring,
    'type', cells.cell_type,
    'params', cells.params
  )
  from cells
  where cells.id = p_cell_id;
$$;

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
    v_amount := public.random_int_between(
      coalesce((v_params->>'minAmount')::integer, 100),
      coalesce((v_params->>'maxAmount')::integer, 100)
    );
    v_sign := nullif(v_params->>'sign', '');

    if v_sign is null then
      v_sign := case when random() < 0.5 then 'positive' else 'negative' end;
    end if;

    if v_sign = 'positive' then
      v_balance := v_balance + v_amount;
    else
      v_balance := v_balance - v_amount;
    end if;

    v_event_type := 'cell_random';
    v_message := 'Random resolved';
    v_payload := jsonb_build_object(
      'cellId', v_cell_id,
      'amount', v_amount,
      'sign', v_sign
    );
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
    v_resolve_result := public.resolve_cell_basic(v_game.id, v_player.id);
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
