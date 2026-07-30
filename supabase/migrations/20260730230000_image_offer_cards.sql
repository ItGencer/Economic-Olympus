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
      ('inner-image-06', 'inner', 'image', '{"label":"Image","priceMin":100,"priceMax":3000,"imageMin":1,"imageMax":10}'::jsonb),
      ('inner-negative-reputation-07', 'inner', 'negative_reputation', '{"label":"Negative reputation","imageDelta":-1}'::jsonb),
      ('inner-salary-08', 'inner', 'salary', '{"label":"Salary","imageMultiplier":500}'::jsonb),
      ('inner-random-10', 'inner', 'random', '{"label":"Random","minAmount":100,"maxAmount":2500}'::jsonb),
      ('inner-casino-11', 'inner', 'casino', '{"label":"Casino"}'::jsonb),
      ('inner-image-12', 'inner', 'image', '{"label":"Image","priceMin":100,"priceMax":3000,"imageMin":1,"imageMax":10}'::jsonb),
      ('inner-vacation-13', 'inner', 'vacation', '{"label":"Vacation","skipTurns":1}'::jsonb),
      ('inner-negative-reputation-15', 'inner', 'negative_reputation', '{"label":"Negative reputation","imageDelta":-1}'::jsonb),
      ('inner-salary-16', 'inner', 'salary', '{"label":"Salary","imageMultiplier":500}'::jsonb),
      ('outer-image-01', 'outer', 'image', '{"label":"Image","entry":true,"priceMin":100,"priceMax":3000,"imageMin":1,"imageMax":10}'::jsonb),
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
      ('outer-image-28', 'outer', 'image', '{"label":"Image","priceMin":100,"priceMax":3000,"imageMin":1,"imageMax":10}'::jsonb),
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

grant execute on function public.get_board_cell_config(text) to authenticated;

create or replace function public.resolve_image_offer(
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
  v_balance integer;
  v_image integer;
  v_price integer;
  v_image_gain integer;
  v_ring text;
  v_cell_id text;
  v_debt_locked boolean;
  v_next_player_id uuid;
  v_turn_number integer;
  v_decision text := lower(trim(coalesce(p_decision, '')));
  v_now timestamptz := now();
begin
  if v_user_id is null then
    raise exception 'auth_required' using errcode = '28000';
  end if;

  if v_decision not in ('accept', 'decline') then
    raise exception 'invalid_image_decision';
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
    or v_pending_action->>'type' <> 'image_offer' then
    raise exception 'image_pending_action_required';
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
  v_price := greatest(coalesce((v_payload->>'price')::integer, 0), 0);
  v_image_gain := greatest(coalesce((v_payload->>'imageGain')::integer, 0), 0);
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
  v_ring := coalesce(nullif(v_player_json->>'ring', ''), 'inner');
  v_cell_id := coalesce(nullif(v_player_json->>'cellId', ''), v_pending_action->>'cellId');
  v_debt_locked := coalesce((v_player_json->>'debtLocked')::boolean, false);
  v_turn_number := coalesce((v_game.state#>>'{turn,number}')::integer, 0);

  if v_decision = 'accept' then
    if v_balance < v_price then
      raise exception 'insufficient_balance_for_image';
    end if;

    v_balance := v_balance - v_price;
    v_image := v_image + v_image_gain;
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
  v_updated_player := jsonb_set(v_updated_player, '{image}', to_jsonb(v_image), true);
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
    case when v_decision = 'accept' then 'image_purchased' else 'image_declined' end,
    case when v_decision = 'accept' then 'Image purchased' else 'Image declined' end,
    jsonb_build_object(
      'actionId', v_pending_action->>'id',
      'decision', v_decision,
      'price', v_price,
      'imageGain', v_image_gain,
      'balance', v_balance,
      'image', v_image,
      'nextPlayerId', v_next_player_id,
      'debtLocked', v_debt_locked
    )
  );

  return jsonb_build_object(
    'game_id', v_game.id,
    'player_id', v_player.id,
    'decision', v_decision,
    'price', v_price,
    'image_gain', v_image_gain,
    'next_player_id', v_next_player_id,
    'state', v_state
  );
end;
$$;

grant execute on function public.resolve_image_offer(uuid, text) to authenticated;
