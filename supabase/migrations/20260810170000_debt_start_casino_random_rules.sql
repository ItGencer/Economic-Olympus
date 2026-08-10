create or replace function public.get_next_turn_player_id_from_state(
  p_game_id uuid,
  p_current_player_id uuid,
  p_state jsonb
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
  active_players as (
    select p.id, p.seat_number
    from public.players p
    left join lateral (
      select player_data
      from jsonb_array_elements(coalesce(p_state->'players', '[]'::jsonb)) as state_players(player_data)
      where state_players.player_data->>'id' = p.id::text
      limit 1
    ) state_player on true
    where p.game_id = p_game_id
      and coalesce((state_player.player_data->>'eliminated')::boolean, false) is false
  ),
  next_player as (
    select active_players.id
    from active_players
    cross join current_player
    where active_players.seat_number > current_player.seat_number
    order by active_players.seat_number
    limit 1
  ),
  first_player as (
    select active_players.id
    from active_players
    order by active_players.seat_number
    limit 1
  )
  select coalesce(
    (select id from next_player),
    (select id from first_player)
  );
$$;

grant execute on function public.get_next_turn_player_id_from_state(uuid, uuid, jsonb) to authenticated;

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
  select public.get_next_turn_player_id_from_state(
    p_game_id,
    p_current_player_id,
    coalesce((select games.state from public.games where games.id = p_game_id), '{}'::jsonb)
  );
$$;

grant execute on function public.get_next_turn_player_id(uuid, uuid) to authenticated;

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

create or replace function public.enforce_debt_thresholds_on_game_state()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_players jsonb;
  v_new_players jsonb := '[]'::jsonb;
  v_player jsonb;
  v_old_player jsonb;
  v_current_player_json jsonb;
  v_player_id uuid;
  v_balance integer;
  v_debt integer;
  v_ring text;
  v_cell_id text;
  v_debt_locked boolean;
  v_debt_warning boolean;
  v_eliminated boolean;
  v_was_warning boolean;
  v_was_eliminated boolean;
  v_released_shares integer;
  v_any_share_release boolean := false;
  v_turn_number integer := null;
  v_turn_player_id uuid := null;
  v_turn_from_cell_id text := null;
  v_turn_die integer := 0;
  v_turn_cell_ids text[];
  v_turn_cell_count integer := 0;
  v_turn_from_index integer := null;
  v_trigger_start_bonus_applied boolean := false;
  v_start_bonus_from_turn boolean := false;
  v_next_player_id uuid;
  v_active_player_count integer := 0;
  v_last_active_player_id uuid := null;
  v_last_active_player_name text := null;
  v_now timestamptz := now();
begin
  if new.state is null or jsonb_typeof(new.state->'players') <> 'array' then
    return new;
  end if;

  v_players := coalesce(new.state->'players', '[]'::jsonb);
  v_turn_number := nullif(new.state#>>'{turn,number}', '')::integer;
  v_turn_from_cell_id := nullif(new.state#>>'{turn,fromCellId}', '');
  v_start_bonus_from_turn := coalesce((new.state#>>'{turn,startBonusApplied}')::boolean, false);

  begin
    v_turn_player_id := nullif(new.state#>>'{turn,playerId}', '')::uuid;
  exception when others then
    v_turn_player_id := null;
  end;

  begin
    v_turn_die := coalesce(nullif(new.state#>>'{turn,dice,0}', '')::integer, 0);
  exception when others then
    v_turn_die := 0;
  end;

  for v_player in
    select player_data
    from jsonb_array_elements(v_players) as state_players(player_data)
  loop
    v_old_player := null;
    v_player_id := null;

    begin
      v_player_id := nullif(v_player->>'id', '')::uuid;
    exception when others then
      v_player_id := null;
    end;

    if v_player_id is null then
      v_new_players := v_new_players || jsonb_build_array(v_player);
      continue;
    end if;

    select old_player_data
    into v_old_player
    from jsonb_array_elements(coalesce(old.state->'players', '[]'::jsonb)) as old_players(old_player_data)
    where old_players.old_player_data->>'id' = v_player_id::text
    limit 1;

    v_balance := coalesce(nullif(v_player->>'balance', '')::integer, 0);
    v_debt := greatest(0 - v_balance, 0);
    v_ring := coalesce(nullif(v_player->>'ring', ''), 'inner');
    v_cell_id := coalesce(nullif(v_player->>'cellId', ''), 'inner-start-01');

    if v_player_id = v_turn_player_id
      and not v_start_bonus_from_turn
      and v_turn_die > 0
      and v_ring = 'inner'
      and v_turn_from_cell_id is not null then
      v_turn_cell_ids := public.get_board_cell_ids('inner');
      v_turn_cell_count := array_length(v_turn_cell_ids, 1);
      v_turn_from_index := array_position(v_turn_cell_ids, v_turn_from_cell_id);

      if v_turn_from_index is not null
        and (v_turn_from_index - 1 + v_turn_die) >= v_turn_cell_count then
        v_balance := v_balance + 1000;
        v_trigger_start_bonus_applied := true;
        v_start_bonus_from_turn := true;

        insert into public.game_log (
          game_id,
          turn_number,
          player_id,
          event_type,
          message,
          payload
        )
        values (
          new.id,
          v_turn_number,
          v_player_id,
          'start_bonus',
          'Start bonus applied',
          jsonb_build_object(
            'amount',
            1000,
            'fromCellId',
            v_turn_from_cell_id,
            'toCellId',
            v_cell_id,
            'balance',
            v_balance,
            'passedStart',
            true
          )
        );
      end if;
    end if;

    v_debt := greatest(0 - v_balance, 0);
    v_was_warning := coalesce((v_old_player->>'debtWarning')::boolean, false);
    v_was_eliminated := coalesce((v_old_player->>'eliminated')::boolean, false);
    v_eliminated := v_was_eliminated
      or coalesce((v_player->>'eliminated')::boolean, false)
      or v_balance <= -100000;
    v_debt_warning := v_eliminated or v_balance < -50000;

    if v_balance < 0 then
      v_debt_locked := true;

      if v_ring = 'outer' then
        v_ring := 'inner';
        v_cell_id := 'inner-start-01';
      end if;
    else
      v_debt_locked := false;
    end if;

    if v_eliminated then
      with released as (
        delete from public.shares
        where game_id = new.id
          and player_id = v_player_id
        returning share_count
      )
      select coalesce(sum(share_count), 0)::integer
      into v_released_shares
      from released;

      if v_released_shares > 0 then
        v_any_share_release := true;
      end if;

      v_player := jsonb_set(v_player, '{shares}', '{}'::jsonb, true);
      v_player := jsonb_set(v_player, '{skipTurns}', '0'::jsonb, true);

      if not v_was_eliminated then
        insert into public.game_log (
          game_id,
          turn_number,
          player_id,
          event_type,
          message,
          payload
        )
        values (
          new.id,
          v_turn_number,
          v_player_id,
          'player_eliminated',
          'Player eliminated by debt limit',
          jsonb_build_object(
            'balance',
            v_balance,
            'debt',
            v_debt,
            'limit',
            100000,
            'releasedShares',
            v_released_shares
          )
        );
      end if;
    elsif v_debt_warning and not v_was_warning then
      insert into public.game_log (
        game_id,
        turn_number,
        player_id,
        event_type,
        message,
        payload
      )
      values (
        new.id,
        v_turn_number,
        v_player_id,
        'debt_warning',
        'Debt warning',
        jsonb_build_object(
          'balance',
          v_balance,
          'debt',
          v_debt,
          'warningLimit',
          50000
        )
      );
    end if;

    v_player := jsonb_set(v_player, '{balance}', to_jsonb(v_balance), true);
    v_player := jsonb_set(v_player, '{ring}', to_jsonb(v_ring), true);
    v_player := jsonb_set(v_player, '{cellId}', to_jsonb(v_cell_id), true);
    v_player := jsonb_set(v_player, '{debtLocked}', to_jsonb(v_debt_locked), true);
    v_player := jsonb_set(v_player, '{debtWarning}', to_jsonb(v_debt_warning), true);
    v_player := jsonb_set(v_player, '{eliminated}', to_jsonb(v_eliminated), true);

    if not v_eliminated then
      v_active_player_count := v_active_player_count + 1;
      v_last_active_player_id := v_player_id;
      v_last_active_player_name := coalesce(nullif(v_player->>'name', ''), 'Переможець');
    end if;

    v_new_players := v_new_players || jsonb_build_array(v_player);
  end loop;

  new.state := jsonb_set(new.state, '{players}', v_new_players, true);

  if v_any_share_release then
    new.state := jsonb_set(
      new.state,
      '{companies}',
      public.build_game_companies_state(new.id),
      true
    );
  end if;

  if v_trigger_start_bonus_applied then
    new.state := jsonb_set(new.state, '{turn,passedStart}', 'true'::jsonb, true);
    new.state := jsonb_set(new.state, '{turn,startBonus}', '1000'::jsonb, true);
    new.state := jsonb_set(new.state, '{turn,startBonusApplied}', 'true'::jsonb, true);
  end if;

  if new.current_turn_player_id is not null then
    select player_data
    into v_current_player_json
    from jsonb_array_elements(coalesce(new.state->'players', '[]'::jsonb)) as state_players(player_data)
    where state_players.player_data->>'id' = new.current_turn_player_id::text
    limit 1;

    if coalesce((v_current_player_json->>'eliminated')::boolean, false) then
      v_next_player_id := public.get_next_turn_player_id_from_state(
        new.id,
        new.current_turn_player_id,
        new.state
      );

      new.current_turn_player_id := v_next_player_id;
    end if;
  end if;

  if new.status = 'in_progress'
    and v_active_player_count = 1
    and v_last_active_player_id is not null then
    new.status := 'finished';
    new.winner_player_id := v_last_active_player_id;
    new.current_turn_player_id := null;
    new.finished_at := v_now;
    new.state := jsonb_set(new.state, '{status}', to_jsonb('finished'::text), true);
    new.state := jsonb_set(new.state, '{winnerPlayerId}', to_jsonb(v_last_active_player_id::text), true);
    new.state := jsonb_set(new.state, '{pendingAction}', 'null'::jsonb, true);
    new.state := jsonb_set(new.state, '{turn,phase}', to_jsonb('finished'::text), true);
    new.state := jsonb_set(new.state, '{turn,finishedAt}', to_jsonb(v_now), true);
    new.state := jsonb_set(new.state, '{updatedAt}', to_jsonb(v_now), true);

    insert into public.game_log (
      game_id,
      turn_number,
      player_id,
      event_type,
      message,
      payload
    )
    values (
      new.id,
      v_turn_number,
      v_last_active_player_id,
      'game_won_by_elimination',
      'Game won because only one player remains',
      jsonb_build_object(
        'winnerName',
        v_last_active_player_name,
        'activePlayers',
        v_active_player_count,
        'finishReason',
        'last_player_active'
      )
    );
  end if;

  new.state := jsonb_set(
    new.state,
    '{currentTurnPlayerId}',
    case
      when new.current_turn_player_id is null then 'null'::jsonb
      else to_jsonb(new.current_turn_player_id::text)
    end,
    true
  );

  return new;
end;
$$;

drop trigger if exists enforce_debt_thresholds_on_game_state on public.games;

create trigger enforce_debt_thresholds_on_game_state
before update of state on public.games
for each row
execute function public.enforce_debt_thresholds_on_game_state();

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
  v_casino_max_stake integer;
  v_debt_positive_random boolean := false;
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

  if coalesce((v_player_json->>'eliminated')::boolean, false) then
    raise exception 'player_eliminated';
  end if;

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
    v_debt_positive_random := v_balance < -10000;
    v_sign := case
      when v_debt_positive_random then 'positive'
      when random() < 0.5 then 'positive'
      else 'negative'
    end;
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
        'debtPositiveOnly', v_debt_positive_random,
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
    v_casino_max_stake := case when v_balance > 0 then v_balance else 1000 end;
    v_pending_action := jsonb_build_object(
      'id', gen_random_uuid(),
      'type', 'casino_bet',
      'playerId', v_player.id,
      'cellId', v_cell_id,
      'payload', jsonb_build_object(
        'maxStake', v_casino_max_stake,
        'creditStake', v_balance <= 0,
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
  v_max_stake integer;
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
  v_max_stake := coalesce(
    nullif(v_payload->>'maxStake', '')::integer,
    case when v_balance > 0 then v_balance else 1000 end
  );

  if coalesce((v_player_json->>'eliminated')::boolean, false) then
    raise exception 'player_eliminated';
  end if;

  if v_decision = 'roll' then
    if v_phase <> 'initial' then
      raise exception 'casino_roll_already_resolved';
    end if;

    if v_bet_amount < 0 then
      raise exception 'casino_bet_must_not_be_negative';
    end if;

    if v_bet_amount > v_max_stake then
      raise exception 'casino_bet_exceeds_limit';
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
      'maxStake', v_max_stake,
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
