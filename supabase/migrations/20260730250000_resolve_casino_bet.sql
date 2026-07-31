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

  if v_decision not in ('accept', 'decline') then
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

  if v_decision = 'accept' then
    if v_bet_amount < 1 then
      raise exception 'casino_bet_must_be_positive';
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
    v_multiplier := public.random_int_between(2, 10);
    v_won := (v_total % 2 = 0 and v_parity = 'even')
      or (v_total % 2 = 1 and v_parity = 'odd');

    if v_won then
      v_payout := v_bet_amount * v_multiplier;
      v_balance := v_balance + v_payout;
    else
      v_balance := v_balance - v_bet_amount;
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
      'betAmount', case when v_decision = 'accept' then v_bet_amount else null end,
      'parity', case when v_decision = 'accept' then v_parity else null end,
      'dice', case when v_decision = 'accept' then jsonb_build_array(v_die_one, v_die_two) else '[]'::jsonb end,
      'total', v_total,
      'multiplier', v_multiplier,
      'won', case when v_decision = 'accept' then v_won else null end,
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
    'bet_amount', case when v_decision = 'accept' then v_bet_amount else null end,
    'parity', case when v_decision = 'accept' then v_parity else null end,
    'dice', case when v_decision = 'accept' then jsonb_build_array(v_die_one, v_die_two) else '[]'::jsonb end,
    'total', v_total,
    'multiplier', v_multiplier,
    'won', case when v_decision = 'accept' then v_won else null end,
    'payout', v_payout,
    'next_player_id', v_next_player_id,
    'state', v_state
  );
end;
$$;

grant execute on function public.resolve_casino_bet(uuid, text, integer, text) to authenticated;
