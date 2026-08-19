create or replace function public.is_tax_cell(p_cell_id text)
returns boolean
language sql
immutable
security definer
set search_path = public
as $$
  select coalesce(public.get_board_cell_config(p_cell_id)->>'type', '') = 'tax';
$$;

grant execute on function public.is_tax_cell(text) to authenticated;

create or replace function public.create_tax_pending_action(
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
  v_pending_action jsonb;
  v_pending_action_id uuid := gen_random_uuid();
  v_player_index integer;
  v_turn_number integer;
  v_cell_id text;
  v_player_name text;
  v_balance integer;
  v_tax_base integer;
  v_pdfo_due integer;
  v_military_due integer;
  v_esv_due integer;
  v_pdfo_penalty integer;
  v_military_penalty integer;
  v_esv_penalty integer;
  v_total_due integer;
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

  if not public.is_tax_cell(v_cell_id) then
    raise exception 'not_tax_cell';
  end if;

  if coalesce((v_player_json->>'eliminated')::boolean, false) then
    raise exception 'player_eliminated';
  end if;

  v_player_name := coalesce(nullif(v_player_json->>'name', ''), 'Гравець');
  v_balance := coalesce((v_player_json->>'balance')::integer, 0);
  v_tax_base := greatest(v_balance, 0);
  v_pdfo_due := floor(v_tax_base * 0.18)::integer;
  v_military_due := floor(v_tax_base * 0.05)::integer;
  v_esv_due := floor(v_tax_base * 0.22)::integer;
  v_pdfo_penalty := floor(v_pdfo_due * 0.05)::integer;
  v_military_penalty := floor(v_military_due * 0.05)::integer;
  v_esv_penalty := floor(v_esv_due * 0.05)::integer;
  v_total_due := v_pdfo_due + v_pdfo_penalty
    + v_military_due + v_military_penalty
    + v_esv_due + v_esv_penalty;
  v_turn_number := coalesce((v_game.state#>>'{turn,number}')::integer, 0);

  v_pending_action := jsonb_build_object(
    'id', v_pending_action_id,
    'type', 'tax_payment',
    'playerId', v_player.id,
    'cellId', v_cell_id,
    'payload', jsonb_build_object(
      'playerName', v_player_name,
      'balanceBefore', v_balance,
      'taxBase', v_tax_base,
      'penaltyRatePercent', 5,
      'totalDue', v_total_due,
      'balanceAfter', v_balance - v_total_due,
      'rows', jsonb_build_array(
        jsonb_build_object(
          'number', 1,
          'name', 'ПДФО',
          'description', 'ПДФО — 18%',
          'ratePercent', 18,
          'due', v_pdfo_due,
          'penalty', v_pdfo_penalty,
          'total', v_pdfo_due + v_pdfo_penalty
        ),
        jsonb_build_object(
          'number', 2,
          'name', 'Військовий збір',
          'description', 'Військовий збір — 5%',
          'ratePercent', 5,
          'due', v_military_due,
          'penalty', v_military_penalty,
          'total', v_military_due + v_military_penalty
        ),
        jsonb_build_object(
          'number', 3,
          'name', 'ЄСВ',
          'description', 'ЄСВ — 22%',
          'ratePercent', 22,
          'due', v_esv_due,
          'penalty', v_esv_penalty,
          'total', v_esv_due + v_esv_penalty
        )
      ),
      'decisions', jsonb_build_array('pay')
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
    'cell_tax_pending',
    'Податкова очікує сплату',
    v_pending_action->'payload'
  );

  return jsonb_build_object(
    'game_id', v_game.id,
    'player_id', v_player.id,
    'cell_id', v_cell_id,
    'cell_type', 'tax',
    'handled', true,
    'has_pending_action', true,
    'event_type', 'cell_tax_pending',
    'payload', v_pending_action->'payload',
    'state', v_state
  );
end;
$$;

grant execute on function public.create_tax_pending_action(uuid, uuid) to authenticated;

create or replace function public.resolve_tax_payment(p_game_id uuid)
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
  v_balance_before integer;
  v_total_due integer;
  v_balance_after integer;
  v_next_player_id uuid;
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

  v_pending_action := v_game.state->'pendingAction';

  if v_pending_action is null
    or v_pending_action = 'null'::jsonb
    or v_pending_action->>'type' <> 'tax_payment' then
    raise exception 'tax_payment_pending_action_required';
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

  if coalesce((v_player_json->>'eliminated')::boolean, false) then
    raise exception 'player_eliminated';
  end if;

  v_balance_before := coalesce((v_player_json->>'balance')::integer, 0);
  v_total_due := greatest(coalesce((v_payload->>'totalDue')::integer, 0), 0);
  v_balance_after := v_balance_before - v_total_due;
  v_turn_number := coalesce((v_game.state#>>'{turn,number}')::integer, 0);
  v_next_player_id := public.get_next_turn_player_id(v_game.id, v_player.id);

  if v_next_player_id is null then
    raise exception 'next_turn_player_not_found';
  end if;

  v_updated_player := public.apply_player_balance_state(v_player_json, v_balance_after);
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
    'tax_paid',
    'Податковий штраф сплачено',
    jsonb_build_object(
      'actionId', v_pending_action->>'id',
      'balanceBefore', v_balance_before,
      'totalDue', v_total_due,
      'balanceAfter', v_balance_after,
      'rows', v_payload->'rows',
      'nextPlayerId', v_next_player_id
    )
  );

  return jsonb_build_object(
    'game_id', v_game.id,
    'player_id', v_player.id,
    'balance_before', v_balance_before,
    'total_due', v_total_due,
    'balance_after', v_balance_after,
    'next_player_id', v_next_player_id,
    'state', v_state
  );
end;
$$;

grant execute on function public.resolve_tax_payment(uuid) to authenticated;

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
  v_balance integer;
  v_start_bonus integer := 0;
  v_passed_start boolean := false;
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

  if coalesce((v_player_json->>'eliminated')::boolean, false) then
    raise exception 'player_eliminated';
  end if;

  v_balance := coalesce((v_player_json->>'balance')::integer, 0);
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
    v_passed_start := v_ring = 'inner'
      and (v_from_index - 1 + v_die) >= v_cell_count;
    v_start_bonus := case when v_passed_start then 1000 else 0 end;
    v_updated_player := jsonb_set(
      v_player_json,
      '{cellId}',
      to_jsonb(v_to_cell_id),
      true
    );

    if v_start_bonus > 0 then
      v_updated_player := public.apply_player_balance_state(
        v_updated_player,
        v_balance + v_start_bonus
      );
    end if;
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
      'finishedAt', case when v_skipped then v_now else null end,
      'passedStart', v_passed_start,
      'startBonus', v_start_bonus,
      'startBonusApplied', v_start_bonus > 0
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
      'skipped', v_skipped,
      'passedStart', v_passed_start,
      'startBonus', v_start_bonus,
      'balanceBefore', v_balance,
      'balanceAfter', v_balance + v_start_bonus
    )
  );

  if not v_skipped then
    if public.is_deal_cell(v_to_cell_id) then
      v_resolve_result := public.create_deal_pending_action(v_game.id, v_player.id);
    elsif public.is_client_cell(v_to_cell_id) then
      v_resolve_result := public.create_client_pending_action(v_game.id, v_player.id);
    elsif public.is_tender_cell(v_to_cell_id) then
      v_resolve_result := public.resolve_tender_landing(v_game.id, v_player.id);
    elsif public.is_company_cell(v_to_cell_id) then
      v_resolve_result := public.resolve_company_landing(v_game.id, v_player.id);
    elsif public.is_director_cell(v_to_cell_id) then
      v_resolve_result := public.resolve_director(v_game.id, v_player.id);
    elsif public.is_negative_reputation_cell(v_to_cell_id) then
      v_resolve_result := public.create_negative_reputation_pending_action(v_game.id, v_player.id);
    elsif public.is_salary_cell(v_to_cell_id) then
      v_resolve_result := public.create_salary_pending_action(v_game.id, v_player.id);
    elsif public.is_tax_cell(v_to_cell_id) then
      v_resolve_result := public.create_tax_pending_action(v_game.id, v_player.id);
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
    'passed_start', v_passed_start,
    'start_bonus', v_start_bonus,
    'cell_result', v_resolve_result,
    'state', v_state
  );
end;
$$;

grant execute on function public.roll_dice(uuid) to authenticated;
