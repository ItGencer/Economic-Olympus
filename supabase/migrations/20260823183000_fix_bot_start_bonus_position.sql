create or replace function public.bot_outer_transition_probability(
  p_balance integer,
  p_image integer
)
returns integer
language plpgsql
immutable
set search_path = public
as $$
declare
  v_balance integer := coalesce(p_balance, 0);
  v_image integer := coalesce(p_image, 0);
  v_balance_score numeric;
  v_image_score numeric;
  v_readiness numeric;
begin
  if v_balance < 5000 and v_image <= 5 then
    v_balance_score := greatest(v_balance, 0)::numeric / 5000;
    v_image_score := greatest(v_image, 0)::numeric / 5;

    return greatest(
      5,
      least(10, floor(5 + ((v_balance_score + v_image_score) / 2) * 5)::integer)
    );
  end if;

  if v_balance >= 20000 and v_image >= 20 then
    v_balance_score :=
      (least(v_balance, 50000) - 20000)::numeric / 30000;
    v_image_score :=
      (least(v_image, 50) - 20)::numeric / 30;

    return greatest(
      60,
      least(80, floor(60 + ((v_balance_score + v_image_score) / 2) * 20)::integer)
    );
  end if;

  v_balance_score :=
    (least(greatest(v_balance, 5000), 20000) - 5000)::numeric / 15000;
  v_image_score :=
    (least(greatest(v_image, 5), 20) - 5)::numeric / 15;
  v_readiness := (v_balance_score + v_image_score) / 2;

  return greatest(10, least(60, floor(10 + v_readiness * 50)::integer));
end;
$$;

grant execute on function public.bot_outer_transition_probability(integer, integer)
to authenticated;

create or replace function public.resolve_bot_turn(p_game_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_game public.games%rowtype;
  v_player public.players%rowtype;
  v_owner_player public.players%rowtype;
  v_tender public.tenders%rowtype;
  v_company public.companies%rowtype;
  v_players jsonb;
  v_player_json jsonb;
  v_updated_player jsonb;
  v_owner_json jsonb;
  v_updated_owner jsonb;
  v_state jsonb;
  v_pending_action jsonb;
  v_payload jsonb := '{}'::jsonb;
  v_cell jsonb;
  v_params jsonb := '{}'::jsonb;
  v_tenders_state jsonb := null;
  v_companies_state jsonb := null;
  v_directors_state jsonb := null;
  v_created_directors jsonb := '[]'::jsonb;
  v_tender_ids jsonb;
  v_share_map jsonb;
  v_director_ids jsonb;
  v_player_index integer;
  v_owner_index integer := null;
  v_turn_number integer := 0;
  v_move_die integer := null;
  v_roll_die integer := null;
  v_die_one integer := null;
  v_die_two integer := null;
  v_dice_sum integer := null;
  v_multiplier integer := null;
  v_player_die integer := null;
  v_bank_die integer := null;
  v_player_score integer := null;
  v_bank_score integer := null;
  v_difference integer := null;
  v_percent integer := null;
  v_skip_turns integer := 0;
  v_balance integer := 0;
  v_balance_before integer := 0;
  v_owner_balance integer := 0;
  v_image integer := 0;
  v_inventory integer := 0;
  v_successful_deals integer := 0;
  v_failed_deals integer := 0;
  v_amount integer := 0;
  v_tax_base integer := 0;
  v_tax_amount integer := 0;
  v_price integer := 0;
  v_image_gain integer := 0;
  v_bet_amount integer := 0;
  v_payout integer := 0;
  v_coefficient integer := 0;
  v_unit_value integer := 1000;
  v_score integer := null;
  v_buyout integer := 0;
  v_fee integer := 0;
  v_relationship integer := 0;
  v_percent_step integer := 10;
  v_stock_to_sell integer := null;
  v_sold_stock integer := null;
  v_revenue integer := null;
  v_share_price integer := 0;
  v_inventory_per_share integer := 0;
  v_inventory_gain integer := 0;
  v_cost integer := 0;
  v_available_shares integer := 0;
  v_sold_shares integer := 0;
  v_player_shares integer := 0;
  v_max_affordable_shares integer := 0;
  v_max_purchasable_shares integer := 0;
  v_share_count integer := 0;
  v_min_ownership integer := 51;
  v_vote_difficulty integer := 7;
  v_voting_coefficient numeric := 1;
  v_created_count integer := 0;
  v_transition_chance integer := null;
  v_transition_roll integer := null;
  v_cell_ids text[];
  v_cell_count integer := 0;
  v_from_cell_id text;
  v_to_cell_id text;
  v_from_index integer;
  v_to_index integer;
  v_ring text := 'inner';
  v_cell_id text := 'inner-start-01';
  v_cell_type text := 'unknown';
  v_action_type text := null;
  v_decision text := null;
  v_parity text := null;
  v_sign text := null;
  v_event_type text := 'bot_turn_resolved';
  v_message text := 'Bot turn resolved';
  v_log_payload jsonb := '{}'::jsonb;
  v_debt_locked boolean := false;
  v_debt_positive_random boolean := false;
  v_successful boolean := null;
  v_won boolean := false;
  v_skipped boolean := false;
  v_passed_start boolean := false;
  v_start_bonus integer := 0;
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

  if v_game.current_turn_player_id is null then
    return jsonb_build_object('game_id', v_game.id, 'state', v_game.state);
  end if;

  select *
  into v_player
  from public.players
  where id = v_game.current_turn_player_id
    and game_id = v_game.id
  for update;

  if not found or not v_player.is_bot then
    return jsonb_build_object('game_id', v_game.id, 'state', v_game.state);
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
    v_next_player_id := public.get_next_turn_player_id(v_game.id, v_player.id);

    update public.games
    set
      current_turn_player_id = v_next_player_id,
      state = jsonb_set(
        jsonb_set(v_game.state, '{currentTurnPlayerId}', to_jsonb(v_next_player_id::text), true),
        '{updatedAt}',
        to_jsonb(v_now),
        true
      )
    where id = v_game.id
    returning state into v_state;

    return jsonb_build_object(
      'game_id', v_game.id,
      'player_id', v_player.id,
      'event_type', 'bot_eliminated_skipped',
      'state', v_state
    );
  end if;

  v_updated_player := v_player_json;
  v_balance := coalesce((v_player_json->>'balance')::integer, 0);
  v_image := coalesce((v_player_json->>'image')::integer, 0);
  v_inventory := coalesce((v_player_json->>'inventory')::integer, 0);
  v_successful_deals := case
    when v_balance < 0 then 0
    else coalesce((v_player_json->>'successfulDeals')::integer, 0)
  end;
  v_failed_deals := coalesce((v_player_json->>'failedDeals')::integer, 0);
  v_debt_locked := coalesce((v_player_json->>'debtLocked')::boolean, false);
  v_ring := coalesce(nullif(v_player_json->>'ring', ''), 'inner');
  v_cell_id := coalesce(nullif(v_player_json->>'cellId', ''), 'inner-start-01');
  v_skip_turns := coalesce((v_player_json->>'skipTurns')::integer, 0);
  v_tender_ids := coalesce(v_player_json->'tenderIds', '[]'::jsonb);
  v_share_map := coalesce(v_player_json->'shares', '{}'::jsonb);
  v_director_ids := coalesce(v_player_json->'directorIds', '[]'::jsonb);
  v_turn_number := coalesce((v_game.state#>>'{turn,number}')::integer, 0);
  v_pending_action := v_game.state->'pendingAction';

  if v_pending_action is not null
    and v_pending_action <> 'null'::jsonb then
    if v_pending_action->>'playerId' is distinct from v_player.id::text then
      return jsonb_build_object('game_id', v_game.id, 'state', v_game.state);
    end if;

    v_action_type := v_pending_action->>'type';
    v_payload := coalesce(v_pending_action->'payload', '{}'::jsonb);
    v_cell_id := coalesce(nullif(v_pending_action->>'cellId', ''), v_cell_id);
    v_from_cell_id := v_cell_id;
    v_to_cell_id := v_cell_id;
  else
    v_turn_number := v_turn_number + 1;

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

    if v_skip_turns > 0 then
      v_skipped := true;
      v_to_cell_id := v_from_cell_id;
      v_skip_turns := v_skip_turns - 1;
      v_cell_type := 'skip';
      v_event_type := 'turn_skipped';
      v_message := 'Bot turn skipped';
      v_log_payload := jsonb_build_object(
        'skipped', true,
        'fromCellId', v_from_cell_id,
        'toCellId', v_to_cell_id,
        'skipTurns', v_skip_turns
      );
    else
      v_move_die := public.random_int_between(1, 6);
      v_to_index := ((v_from_index - 1 + v_move_die) % v_cell_count) + 1;
      v_to_cell_id := v_cell_ids[v_to_index];
      v_cell_id := v_to_cell_id;
      v_passed_start := v_ring = 'inner'
        and (v_from_index - 1 + v_move_die) >= v_cell_count;
      v_start_bonus := case when v_passed_start then 1000 else 0 end;

      if v_start_bonus > 0 then
        v_balance := v_balance + v_start_bonus;
        v_updated_player := jsonb_set(v_updated_player, '{ring}', to_jsonb(v_ring), true);
        v_updated_player := jsonb_set(v_updated_player, '{cellId}', to_jsonb(v_cell_id), true);
        v_updated_player := public.apply_player_balance_state(v_updated_player, v_balance);
        v_balance := coalesce((v_updated_player->>'balance')::integer, v_balance);
        v_ring := coalesce(nullif(v_updated_player->>'ring', ''), v_ring);
        v_cell_id := coalesce(nullif(v_updated_player->>'cellId', ''), v_cell_id);
        v_debt_locked := coalesce((v_updated_player->>'debtLocked')::boolean, v_debt_locked);
      end if;

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
        'dice_rolled',
        'Bot rolled dice',
        jsonb_build_object(
          'die', v_move_die,
          'fromCellId', v_from_cell_id,
          'toCellId', v_to_cell_id,
          'skipped', false,
          'passedStart', v_passed_start,
          'startBonus', v_start_bonus,
          'balance', v_balance
        )
      );
    end if;
  end if;

  if not v_skipped then
    v_updated_player := jsonb_set(v_updated_player, '{ring}', to_jsonb(v_ring), true);
    v_updated_player := jsonb_set(v_updated_player, '{cellId}', to_jsonb(v_cell_id), true);

    v_cell := public.get_board_cell_config(v_cell_id);
    v_cell_type := coalesce(v_cell->>'type', 'unknown');
    v_params := coalesce(v_cell->'params', '{}'::jsonb);

    if public.is_deal_cell(v_cell_id) then
      v_cell_type := 'deal';
      v_params := coalesce(public.get_deal_cell_params(v_cell_id), v_params, '{}'::jsonb);
    elsif public.is_client_cell(v_cell_id) then
      v_cell_type := 'client';
      v_params := coalesce(public.get_client_cell_params(v_cell_id), v_params, '{}'::jsonb);
    elsif public.is_tender_cell(v_cell_id) then
      v_cell_type := 'tender';
      v_params := coalesce(public.get_tender_cell_params(v_cell_id), v_params, '{}'::jsonb);
    elsif public.is_company_cell(v_cell_id) then
      v_cell_type := 'company';
      v_params := coalesce(public.get_company_cell_params(v_cell_id), v_params, '{}'::jsonb);
    elsif public.is_director_cell(v_cell_id) then
      v_cell_type := 'director';
      v_params := coalesce(public.get_director_cell_params(v_cell_id), v_params, '{}'::jsonb);
    elsif public.is_tax_cell(v_cell_id) then
      v_cell_type := 'tax';
    elsif public.is_salary_cell(v_cell_id) then
      v_cell_type := 'salary';
    elsif public.is_negative_reputation_cell(v_cell_id) then
      v_cell_type := 'negative_reputation';
    end if;

    if v_action_type = 'outer_ring_choice' then
      v_transition_chance := public.bot_outer_transition_probability(v_balance, v_image);
      v_transition_roll := public.random_int_between(1, 100);

      if v_ring = 'inner'
        and v_balance >= 0
        and not v_debt_locked
        and v_successful_deals >= 5
        and v_transition_roll <= v_transition_chance then
        v_ring := 'outer';
        v_cell_id := public.get_outer_entry_cell_id();
        v_decision := 'move_to_outer';
      else
        v_successful_deals := 0;
        v_decision := 'stay_inner';
      end if;

      v_event_type := case when v_decision = 'move_to_outer' then 'outer_ring_moved' else 'outer_ring_stayed' end;
      v_message := case when v_decision = 'move_to_outer' then 'Bot moved to outer ring' else 'Bot stayed on inner ring' end;
      v_log_payload := jsonb_build_object(
        'decision', v_decision,
        'chancePercent', v_transition_chance,
        'roll', v_transition_roll,
        'successfulDeals', v_successful_deals,
        'balance', v_balance,
        'image', v_image,
        'ring', v_ring,
        'cellId', v_cell_id
      );

    elsif v_action_type = 'deal_decision' or v_cell_type = 'deal' then
      v_coefficient := coalesce(
        nullif(v_payload->>'coefficient', '')::integer,
        nullif(v_payload->>'importance', '')::integer,
        public.random_int_between(
          coalesce((v_params->>'coefficientMin')::integer, 5),
          coalesce((v_params->>'coefficientMax')::integer, 50)
        )
      );
      v_unit_value := coalesce(nullif(v_payload->>'unitValue', '')::integer, 1000);
      v_decision := case
        when v_image >= v_coefficient + 12 then 'accept'
        when v_image >= v_coefficient and random() < 0.75 then 'accept'
        when v_balance >= 50000 and v_image >= 10 and random() < 0.55 then 'accept'
        when v_balance >= 20000 and v_image >= 5 and random() < 0.35 then 'accept'
        else 'decline'
      end;

      if v_decision = 'accept' then
        v_roll_die := public.random_int_between(1, 20);
        v_score := v_coefficient + v_roll_die;
        v_difference := v_image - v_score;
        v_amount := v_difference * v_unit_value;
        v_successful := v_score <= v_image;
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

        if v_balance < 0 then
          v_successful_deals := 0;
        end if;

        if v_successful
          and v_ring = 'inner'
          and v_balance >= 0
          and not v_debt_locked
          and v_successful_deals >= 5 then
          v_transition_chance := public.bot_outer_transition_probability(v_balance, v_image);
          v_transition_roll := public.random_int_between(1, 100);

          if v_transition_roll <= v_transition_chance then
            v_ring := 'outer';
            v_cell_id := public.get_outer_entry_cell_id();
            v_decision := 'accept_move_to_outer';
          else
            v_successful_deals := 0;
            v_decision := 'accept_stay_inner';
          end if;
        end if;
      end if;

      v_event_type := case
        when v_decision = 'decline' then 'deal_declined'
        when v_successful then 'deal_successful'
        else 'deal_failed'
      end;
      v_message := case
        when v_decision = 'decline' then 'Bot declined business meeting'
        when v_successful then 'Bot completed business meeting'
        else 'Bot failed business meeting'
      end;
      v_log_payload := jsonb_build_object(
        'decision', v_decision,
        'coefficient', v_coefficient,
        'unitValue', v_unit_value,
        'die', v_roll_die,
        'score', v_score,
        'image', v_image,
        'difference', v_difference,
        'amount', case when v_decision = 'decline' then 0 else v_amount end,
        'balance', v_balance,
        'successful', v_successful,
        'successfulDeals', v_successful_deals,
        'successfulDealUser', v_successful_deals,
        'outerTransitionChance', v_transition_chance,
        'outerTransitionRoll', v_transition_roll,
        'ring', v_ring,
        'cellId', v_cell_id
      );

    elsif v_action_type = 'casino_bet' or v_cell_type = 'casino' then
      v_decision := case
        when v_balance < -50000 and random() < 0.4 then 'accept'
        when v_balance < 0 and random() < 0.5 then 'accept'
        when random() < 0.7 then 'accept'
        else 'decline'
      end;

      if v_decision = 'accept' then
        v_bet_amount := case
          when v_balance >= 1000 then
            greatest(
              100,
              floor(((v_balance * public.random_int_between(5, 15))::numeric / 100) / 100)::integer * 100
            )
          when v_balance >= 0 then public.random_int_between(1, 10) * 100
          else public.random_int_between(1, 30) * 100
        end;
        v_parity := case when random() < 0.5 then 'even' else 'odd' end;
        v_die_one := public.random_int_between(1, 6);
        v_die_two := public.random_int_between(1, 6);
        v_dice_sum := v_die_one + v_die_two;
        v_won := (v_dice_sum % 2 = 0 and v_parity = 'even')
          or (v_dice_sum % 2 = 1 and v_parity = 'odd');

        if v_won then
          v_multiplier := public.random_int_between(2, 10);
          v_payout := v_bet_amount * v_multiplier;
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

      v_event_type := case
        when v_decision = 'decline' then 'casino_declined'
        when v_won then 'casino_won'
        else 'casino_lost'
      end;
      v_message := case
        when v_decision = 'decline' then 'Bot declined casino'
        when v_won then 'Bot won casino'
        else 'Bot lost casino'
      end;
      v_log_payload := jsonb_build_object(
        'decision', v_decision,
        'betAmount', case when v_decision = 'accept' then v_bet_amount else null end,
        'parity', v_parity,
        'dice', case when v_decision = 'accept' then jsonb_build_array(v_die_one, v_die_two) else '[]'::jsonb end,
        'total', v_dice_sum,
        'multiplier', v_multiplier,
        'won', case when v_decision = 'accept' then v_won else null end,
        'payout', v_payout,
        'balance', v_balance
      );

    elsif v_action_type = 'image_offer' or v_cell_type = 'image' then
      v_price := coalesce(
        nullif(v_payload->>'price', '')::integer,
        public.random_int_between(
          coalesce((v_params->>'priceMin')::integer, 100),
          coalesce((v_params->>'priceMax')::integer, 3000)
        )
      );
      v_image_gain := coalesce(
        nullif(v_payload->>'imageGain', '')::integer,
        public.random_int_between(
          coalesce((v_params->>'imageMin')::integer, 1),
          coalesce((v_params->>'imageMax')::integer, 10)
        )
      );
      v_decision := case
        when v_balance >= v_price
          and (v_image < 20 or v_price::numeric <= greatest(v_balance, 0)::numeric * 0.25 or random() < 0.35)
          then 'accept'
        else 'decline'
      end;

      if v_decision = 'accept' then
        v_balance := v_balance - v_price;
        v_image := v_image + v_image_gain;
        v_updated_player := public.apply_player_balance_state(v_updated_player, v_balance);
        v_balance := coalesce((v_updated_player->>'balance')::integer, v_balance);
        v_ring := coalesce(nullif(v_updated_player->>'ring', ''), v_ring);
        v_cell_id := coalesce(nullif(v_updated_player->>'cellId', ''), v_cell_id);
        v_debt_locked := coalesce((v_updated_player->>'debtLocked')::boolean, v_debt_locked);
      end if;

      v_event_type := case when v_decision = 'accept' then 'image_purchased' else 'image_declined' end;
      v_message := case when v_decision = 'accept' then 'Bot purchased image' else 'Bot declined image' end;
      v_log_payload := jsonb_build_object(
        'decision', v_decision,
        'price', v_price,
        'imageGain', v_image_gain,
        'balance', v_balance,
        'image', v_image
      );

    elsif v_action_type = 'advertising_offer' or v_cell_type = 'advertising' then
      v_max_affordable_shares := greatest(floor(greatest(v_balance, 0)::numeric / 1500)::integer, 0);
      v_image_gain := case
        when v_max_affordable_shares <= 0 then 0
        else least(public.random_int_between(1, 9), v_max_affordable_shares)
      end;
      v_price := v_image_gain * 1500;
      v_decision := case
        when v_image_gain > 0 and (v_image < 30 or random() < 0.65) then 'accept'
        else 'decline'
      end;

      if v_decision = 'accept' then
        v_balance := v_balance - v_price;
        v_image := v_image + v_image_gain;
        v_updated_player := public.apply_player_balance_state(v_updated_player, v_balance);
        v_balance := coalesce((v_updated_player->>'balance')::integer, v_balance);
        v_ring := coalesce(nullif(v_updated_player->>'ring', ''), v_ring);
        v_cell_id := coalesce(nullif(v_updated_player->>'cellId', ''), v_cell_id);
        v_debt_locked := coalesce((v_updated_player->>'debtLocked')::boolean, v_debt_locked);
      end if;

      v_event_type := case when v_decision = 'accept' then 'advertising_purchased' else 'advertising_declined' end;
      v_message := case when v_decision = 'accept' then 'Bot purchased advertising' else 'Bot declined advertising' end;
      v_log_payload := jsonb_build_object(
        'decision', v_decision,
        'price', v_price,
        'unitPrice', 1500,
        'imageGain', v_image_gain,
        'balance', v_balance,
        'image', v_image
      );

    elsif v_action_type = 'random_event' or v_cell_type = 'random' then
      v_debt_positive_random := v_balance < -10000;
      v_sign := coalesce(nullif(v_payload->>'sign', ''), case
        when v_debt_positive_random then 'positive'
        when random() < 0.5 then 'positive'
        else 'negative'
      end);
      v_amount := coalesce(nullif(v_payload->>'amount', '')::integer, case
        when v_sign = 'positive' then public.random_int_between(1, 20) * 100
        else 0 - (public.random_int_between(10, 50) * 100)
      end);
      v_balance := v_balance + v_amount;
      v_updated_player := public.apply_player_balance_state(v_updated_player, v_balance);
      v_balance := coalesce((v_updated_player->>'balance')::integer, v_balance);
      v_ring := coalesce(nullif(v_updated_player->>'ring', ''), v_ring);
      v_cell_id := coalesce(nullif(v_updated_player->>'cellId', ''), v_cell_id);
      v_debt_locked := coalesce((v_updated_player->>'debtLocked')::boolean, v_debt_locked);
      v_event_type := 'random_event_resolved';
      v_message := 'Bot resolved random event';
      v_log_payload := jsonb_build_object(
        'decision', 'confirm',
        'amount', v_amount,
        'sign', v_sign,
        'debtPositiveOnly', v_debt_positive_random,
        'balance', v_balance
      );

    elsif v_action_type = 'negative_reputation' or v_cell_type = 'negative_reputation' then
      v_roll_die := coalesce(
        nullif(v_payload->>'die', '')::integer,
        public.random_int_between(1, 6)
      );
      v_amount := v_roll_die;
      v_image := v_image - v_amount;
      v_event_type := 'negative_reputation_applied';
      v_message := 'Bot lost image from negative reputation';
      v_log_payload := jsonb_build_object(
        'die', v_roll_die,
        'imageLoss', v_amount,
        'imageAfter', v_image,
        'imageDelta', -v_amount
      );

    elsif v_action_type = 'salary' or v_cell_type = 'salary' then
      v_roll_die := coalesce(
        nullif(v_payload->>'die', '')::integer,
        public.random_int_between(1, 20)
      );
      v_amount := case
        when v_image > 0 then v_roll_die * 1000
        when v_image < 0 then 0 - (v_roll_die * 100)
        else 0
      end;
      v_balance := v_balance + v_amount;
      v_updated_player := public.apply_player_balance_state(v_updated_player, v_balance);
      v_balance := coalesce((v_updated_player->>'balance')::integer, v_balance);
      v_ring := coalesce(nullif(v_updated_player->>'ring', ''), v_ring);
      v_cell_id := coalesce(nullif(v_updated_player->>'cellId', ''), v_cell_id);
      v_debt_locked := coalesce((v_updated_player->>'debtLocked')::boolean, v_debt_locked);
      v_event_type := 'salary_resolved';
      v_message := 'Bot resolved salary';
      v_log_payload := jsonb_build_object(
        'salaryDie', v_roll_die,
        'salaryKind', case
          when v_image > 0 then 'Премія'
          when v_image < 0 then 'Штраф'
          else 'Без змін'
        end,
        'salaryUnit', case
          when v_image > 0 then 1000
          when v_image < 0 then 100
          else 0
        end,
        'die', v_roll_die,
        'image', v_image,
        'amount', abs(v_amount),
        'balanceDelta', v_amount,
        'balance', v_balance
      );

    elsif v_cell_type = 'vacation' then
      v_amount := coalesce((v_params->>'skipTurns')::integer, 1);
      v_skip_turns := v_skip_turns + v_amount;
      v_event_type := 'cell_vacation';
      v_message := 'Bot resolved vacation';
      v_log_payload := jsonb_build_object(
        'cellId', v_cell_id,
        'skipTurnsAdded', v_amount,
        'skipTurns', v_skip_turns
      );

    elsif v_action_type = 'tax_payment' or v_cell_type = 'tax' then
      if v_action_type = 'tax_payment' then
        v_tax_amount := greatest(coalesce(nullif(v_payload->>'totalDue', '')::integer, 0), 0);
      else
        v_tax_base := greatest(v_balance, 0);
        v_tax_amount :=
          floor(v_tax_base * 0.18)::integer + floor(floor(v_tax_base * 0.18)::numeric * 0.05)::integer
          + floor(v_tax_base * 0.05)::integer + floor(floor(v_tax_base * 0.05)::numeric * 0.05)::integer
          + floor(v_tax_base * 0.22)::integer + floor(floor(v_tax_base * 0.22)::numeric * 0.05)::integer;
      end if;

      v_balance := v_balance - v_tax_amount;
      v_updated_player := public.apply_player_balance_state(v_updated_player, v_balance);
      v_balance := coalesce((v_updated_player->>'balance')::integer, v_balance);
      v_ring := coalesce(nullif(v_updated_player->>'ring', ''), v_ring);
      v_cell_id := coalesce(nullif(v_updated_player->>'cellId', ''), v_cell_id);
      v_debt_locked := coalesce((v_updated_player->>'debtLocked')::boolean, v_debt_locked);
      v_event_type := 'tax_paid';
      v_message := 'Bot paid tax';
      v_log_payload := jsonb_build_object(
        'totalDue', v_tax_amount,
        'balance', v_balance
      );

    elsif v_cell_type = 'positive_reputation' then
      v_amount := coalesce((v_params->>'imageDelta')::integer, 1);
      v_image := v_image + v_amount;
      v_event_type := 'cell_reputation';
      v_message := 'Bot resolved positive reputation';
      v_log_payload := jsonb_build_object('cellId', v_cell_id, 'imageDelta', v_amount, 'image', v_image);

    elsif v_action_type = 'client_decision' or v_cell_type = 'client' then
      v_relationship := coalesce(
        nullif(v_payload->>'relationship', '')::integer,
        public.random_int_between(
          coalesce((v_params->>'relationshipMin')::integer, 1),
          coalesce((v_params->>'relationshipMax')::integer, 6)
        )
      );
      v_percent_step := coalesce(nullif(v_payload->>'percentStep', '')::integer, (v_params->>'percentStep')::integer, 10);
      v_player_die := public.random_int_between(1, 6);
      v_bank_die := public.random_int_between(1, 6);
      v_player_score := v_player_die + v_image;
      v_bank_score := v_bank_die + v_relationship;
      v_difference := v_player_score - v_bank_score;
      v_percent := least(greatest(v_difference * v_percent_step, 0), 100);
      v_stock_to_sell := public.bot_client_stock_to_sell(
        v_inventory,
        nullif(v_payload->>'maxStockToSell', '')::integer
      );
      v_sold_stock := least(v_stock_to_sell, greatest(v_inventory, 0));
      v_revenue := floor((v_sold_stock::numeric * v_percent::numeric) / 100)::integer;
      v_inventory := v_inventory - v_sold_stock;
      v_balance := v_balance + v_revenue;
      v_updated_player := public.apply_player_balance_state(v_updated_player, v_balance);
      v_balance := coalesce((v_updated_player->>'balance')::integer, v_balance);
      v_ring := coalesce(nullif(v_updated_player->>'ring', ''), v_ring);
      v_cell_id := coalesce(nullif(v_updated_player->>'cellId', ''), v_cell_id);
      v_debt_locked := coalesce((v_updated_player->>'debtLocked')::boolean, v_debt_locked);
      v_event_type := 'client_stock_sold';
      v_message := 'Bot sold stock to client';
      v_log_payload := jsonb_build_object(
        'relationship', v_relationship,
        'playerDie', v_player_die,
        'bankDie', v_bank_die,
        'playerScore', v_player_score,
        'bankScore', v_bank_score,
        'difference', v_difference,
        'percent', v_percent,
        'stockToSell', v_stock_to_sell,
        'soldStock', v_sold_stock,
        'revenue', v_revenue
      );

    elsif v_action_type = 'client_stock_choice' then
      v_percent := coalesce((v_payload->>'percent')::integer, 0);
      v_stock_to_sell := public.bot_client_stock_to_sell(
        v_inventory,
        nullif(v_payload->>'maxStockToSell', '')::integer
      );
      v_sold_stock := least(v_stock_to_sell, greatest(v_inventory, 0));
      v_revenue := floor((v_sold_stock::numeric * v_percent::numeric) / 100)::integer;
      v_inventory := v_inventory - v_sold_stock;
      v_balance := v_balance + v_revenue;
      v_updated_player := public.apply_player_balance_state(v_updated_player, v_balance);
      v_balance := coalesce((v_updated_player->>'balance')::integer, v_balance);
      v_ring := coalesce(nullif(v_updated_player->>'ring', ''), v_ring);
      v_cell_id := coalesce(nullif(v_updated_player->>'cellId', ''), v_cell_id);
      v_debt_locked := coalesce((v_updated_player->>'debtLocked')::boolean, v_debt_locked);
      v_event_type := 'client_stock_sold';
      v_message := 'Bot sold stock to client';
      v_log_payload := jsonb_build_object(
        'stockToSell', v_stock_to_sell,
        'soldStock', v_sold_stock,
        'percent', v_percent,
        'revenue', v_revenue
      );

    elsif v_action_type = 'tender_purchase' or v_cell_type = 'tender' then
      perform public.ensure_game_tenders(v_game.id);
      v_params := coalesce(public.get_tender_cell_params(v_cell_id), v_params, '{}'::jsonb);

      select *
      into v_tender
      from public.tenders
      where game_id = v_game.id
        and config_id = coalesce(nullif(v_payload->>'tenderId', ''), v_params->>'tenderId')
      for update;

      if found then
        v_buyout := floor(v_tender.buyout_amount)::integer;
        v_fee := floor(v_tender.fee_amount)::integer;

        if v_tender.owner_player_id is null then
          v_decision := case
            when v_balance >= v_buyout
              and v_buyout::numeric <= greatest(v_balance, 0)::numeric * 0.5 then 'accept'
            else 'decline'
          end;

          if v_decision = 'accept' then
            v_balance := v_balance - v_buyout;
            v_updated_player := public.apply_player_balance_state(v_updated_player, v_balance);
            v_balance := coalesce((v_updated_player->>'balance')::integer, v_balance);
            v_ring := coalesce(nullif(v_updated_player->>'ring', ''), v_ring);
            v_cell_id := coalesce(nullif(v_updated_player->>'cellId', ''), v_cell_id);
            v_debt_locked := coalesce((v_updated_player->>'debtLocked')::boolean, v_debt_locked);

            update public.tenders
            set owner_player_id = v_player.id
            where id = v_tender.id
            returning * into v_tender;

            if not (v_tender_ids ? v_tender.config_id) then
              v_tender_ids := v_tender_ids || to_jsonb(v_tender.config_id);
            end if;
          end if;

          v_event_type := case when v_decision = 'accept' then 'tender_purchased' else 'tender_declined' end;
          v_message := case when v_decision = 'accept' then 'Bot purchased tender' else 'Bot declined tender' end;
        elsif v_tender.owner_player_id <> v_player.id then
          select *
          into v_owner_player
          from public.players
          where id = v_tender.owner_player_id
            and game_id = v_game.id;

          if found then
            select ordinality::integer
            into v_owner_index
            from jsonb_array_elements(v_players) with ordinality as players(player_data, ordinality)
            where player_data->>'id' = v_owner_player.id::text
            limit 1;

            if v_owner_index is not null then
              v_owner_json := v_players->(v_owner_index - 1);
              v_updated_owner := v_owner_json;
              v_owner_balance := coalesce((v_owner_json->>'balance')::integer, 0) + v_fee;
              v_updated_owner := jsonb_set(v_updated_owner, '{balance}', to_jsonb(v_owner_balance), true);
              v_updated_owner := jsonb_set(v_updated_owner, '{updatedAt}', to_jsonb(v_now), true);
            end if;
          end if;

          v_balance := v_balance - v_fee;
          v_updated_player := public.apply_player_balance_state(v_updated_player, v_balance);
          v_balance := coalesce((v_updated_player->>'balance')::integer, v_balance);
          v_ring := coalesce(nullif(v_updated_player->>'ring', ''), v_ring);
          v_cell_id := coalesce(nullif(v_updated_player->>'cellId', ''), v_cell_id);
          v_debt_locked := coalesce((v_updated_player->>'debtLocked')::boolean, v_debt_locked);
          v_event_type := 'tender_fee_paid';
          v_message := 'Bot paid tender fee';
        else
          v_event_type := 'tender_owner_landed';
          v_message := 'Bot landed on own tender';
        end if;

        v_tenders_state := public.build_game_tenders_state(v_game.id);
        v_log_payload := jsonb_build_object(
          'decision', v_decision,
          'tenderId', v_tender.config_id,
          'country', v_tender.country,
          'buyout', v_buyout,
          'price', v_fee,
          'ownerPlayerId', v_tender.owner_player_id
        );
      end if;

    elsif v_action_type = 'company_share_purchase' or v_cell_type = 'company' then
      perform public.ensure_game_companies(v_game.id);
      v_params := coalesce(public.get_company_cell_params(v_cell_id), v_params, '{}'::jsonb);

      select *
      into v_company
      from public.companies
      where game_id = v_game.id
        and config_id = coalesce(nullif(v_payload->>'companyId', ''), v_params->>'companyId')
      for update;

      if found then
        select coalesce(sum(share_count), 0)::integer
        into v_sold_shares
        from public.shares
        where company_id = v_company.id;

        select coalesce(max(share_count), 0)::integer
        into v_player_shares
        from public.shares
        where company_id = v_company.id
          and player_id = v_player.id;

        v_share_price := floor(v_company.share_price)::integer;
        v_inventory_per_share := floor(v_company.inventory_per_share)::integer;
        v_available_shares := greatest(v_company.total_shares - v_sold_shares, 0);
        v_max_affordable_shares := case
          when v_share_price > 0 then greatest(floor(v_balance::numeric / v_share_price::numeric)::integer, 0)
          else 0
        end;
        v_max_purchasable_shares := greatest(least(v_available_shares, v_max_affordable_shares), 0);
        v_share_count := public.bot_company_share_count(v_balance, v_share_price, v_max_purchasable_shares);

        if v_share_count > 0 then
          v_cost := v_share_count * v_share_price;
          v_balance := v_balance - v_cost;
          v_inventory_gain := v_share_count * v_inventory_per_share;
          v_inventory := v_inventory + v_inventory_gain;
          v_updated_player := public.apply_player_balance_state(v_updated_player, v_balance);
          v_balance := coalesce((v_updated_player->>'balance')::integer, v_balance);
          v_ring := coalesce(nullif(v_updated_player->>'ring', ''), v_ring);
          v_cell_id := coalesce(nullif(v_updated_player->>'cellId', ''), v_cell_id);
          v_debt_locked := coalesce((v_updated_player->>'debtLocked')::boolean, v_debt_locked);

          insert into public.shares (
            game_id,
            company_id,
            player_id,
            share_count
          )
          values (
            v_game.id,
            v_company.id,
            v_player.id,
            v_share_count
          )
          on conflict (company_id, player_id) do update
          set share_count = public.shares.share_count + excluded.share_count
          returning share_count into v_player_shares;
        end if;

        if v_player_shares > 0 then
          v_share_map := jsonb_set(v_share_map, array[v_company.config_id], to_jsonb(v_player_shares), true);
        end if;

        v_companies_state := public.build_game_companies_state(v_game.id);
        v_event_type := case when v_share_count > 0 then 'company_shares_purchased' else 'company_purchase_skipped' end;
        v_message := case when v_share_count > 0 then 'Bot purchased company shares' else 'Bot skipped company purchase' end;
        v_log_payload := jsonb_build_object(
          'companyId', v_company.config_id,
          'name', v_company.name,
          'shareCount', v_share_count,
          'sharePrice', v_share_price,
          'cost', v_cost,
          'inventoryGain', v_inventory_gain,
          'playerShares', v_player_shares
        );
      end if;

    elsif v_cell_type = 'director' then
      perform public.ensure_game_companies(v_game.id);
      v_params := coalesce(public.get_director_cell_params(v_cell_id), '{}'::jsonb);
      v_min_ownership := coalesce((v_params->>'minOwnershipPercent')::integer, 51);
      v_voting_coefficient := coalesce((v_params->>'votingCoefficient')::numeric, 1);
      v_vote_difficulty := coalesce((v_params->>'voteDifficulty')::integer, 7);

      with controlled_companies as (
        select companies.id as company_id
        from public.companies
        join public.shares
          on shares.company_id = companies.id
         and shares.player_id = v_player.id
        where companies.game_id = v_game.id
          and (shares.share_count::numeric / greatest(companies.total_shares, 1)::numeric) * 100 >= v_min_ownership
          and not exists (
            select 1
            from public.directors active_directors
            where active_directors.company_id = companies.id
              and active_directors.status = 'active'
          )
      ),
      inserted_directors as (
        insert into public.directors (
          game_id,
          company_id,
          player_id,
          status,
          voting_coefficient,
          vote_difficulty,
          elected_at
        )
        select
          v_game.id,
          controlled_companies.company_id,
          v_player.id,
          'active'::public.director_status,
          v_voting_coefficient,
          v_vote_difficulty,
          v_now
        from controlled_companies
        returning id, company_id, player_id, status, voting_coefficient, vote_difficulty, elected_at
      )
      select
        coalesce(
          jsonb_agg(
            jsonb_build_object(
              'directorId', inserted_directors.id,
              'companyId', companies.config_id,
              'playerId', inserted_directors.player_id,
              'status', inserted_directors.status::text,
              'votingCoefficient', inserted_directors.voting_coefficient,
              'voteDifficulty', inserted_directors.vote_difficulty,
              'electedAt', inserted_directors.elected_at
            )
            order by companies.config_id
          ),
          '[]'::jsonb
        ),
        count(*)::integer
      into v_created_directors, v_created_count
      from inserted_directors
      join public.companies
        on companies.id = inserted_directors.company_id;

      select coalesce(jsonb_agg(director_ids.id order by director_ids.elected_at), '[]'::jsonb)
      into v_director_ids
      from (
        select directors.id::text as id, directors.elected_at
        from public.directors
        where directors.game_id = v_game.id
          and directors.player_id = v_player.id
          and directors.status = 'active'
      ) director_ids;

      v_companies_state := public.build_game_companies_state(v_game.id);
      v_directors_state := public.build_game_directors_state(v_game.id);
      v_event_type := case when v_created_count > 0 then 'directors_elected' else 'director_no_change' end;
      v_message := case when v_created_count > 0 then 'Bot elected directors' else 'Bot resolved director cell without changes' end;
      v_log_payload := jsonb_build_object(
        'cellId', v_cell_id,
        'minOwnershipPercent', v_min_ownership,
        'createdDirectors', v_created_directors,
        'createdCount', v_created_count
      );

    elsif v_cell_type = 'start' then
      v_event_type := 'cell_start';
      v_message := 'Bot resolved start';
      v_log_payload := jsonb_build_object('cellId', v_cell_id);

    else
      v_event_type := 'bot_cell_unhandled';
      v_message := 'Bot skipped unhandled cell';
      v_log_payload := jsonb_build_object(
        'cellId', v_cell_id,
        'cellType', v_cell_type,
        'actionType', v_action_type
      );
    end if;
  end if;

  if v_balance < 0 then
    v_successful_deals := 0;
  end if;

  v_updated_player := jsonb_set(v_updated_player, '{ring}', to_jsonb(v_ring), true);
  v_updated_player := jsonb_set(v_updated_player, '{cellId}', to_jsonb(v_cell_id), true);
  v_updated_player := public.apply_player_balance_state(v_updated_player, v_balance);
  v_balance := coalesce((v_updated_player->>'balance')::integer, v_balance);
  v_ring := coalesce(nullif(v_updated_player->>'ring', ''), v_ring);
  v_cell_id := coalesce(nullif(v_updated_player->>'cellId', ''), v_cell_id);
  v_debt_locked := coalesce((v_updated_player->>'debtLocked')::boolean, v_debt_locked);

  if v_balance < 0 then
    v_successful_deals := 0;
  end if;

  v_next_player_id := public.get_next_turn_player_id(v_game.id, v_player.id);

  if v_next_player_id is null then
    raise exception 'next_turn_player_not_found';
  end if;

  v_updated_player := jsonb_set(v_updated_player, '{balance}', to_jsonb(v_balance), true);
  v_updated_player := jsonb_set(v_updated_player, '{image}', to_jsonb(v_image), true);
  v_updated_player := jsonb_set(v_updated_player, '{inventory}', to_jsonb(v_inventory), true);
  v_updated_player := jsonb_set(v_updated_player, '{successfulDeals}', to_jsonb(v_successful_deals), true);
  v_updated_player := jsonb_set(v_updated_player, '{failedDeals}', to_jsonb(v_failed_deals), true);
  v_updated_player := jsonb_set(v_updated_player, '{skipTurns}', to_jsonb(v_skip_turns), true);
  v_updated_player := jsonb_set(v_updated_player, '{ring}', to_jsonb(v_ring), true);
  v_updated_player := jsonb_set(v_updated_player, '{cellId}', to_jsonb(v_cell_id), true);
  v_updated_player := jsonb_set(v_updated_player, '{debtLocked}', to_jsonb(v_debt_locked), true);
  v_updated_player := jsonb_set(v_updated_player, '{tenderIds}', v_tender_ids, true);
  v_updated_player := jsonb_set(v_updated_player, '{shares}', v_share_map, true);
  v_updated_player := jsonb_set(v_updated_player, '{directorIds}', v_director_ids, true);
  v_updated_player := jsonb_set(v_updated_player, '{updatedAt}', to_jsonb(v_now), true);

  v_state := v_game.state;
  v_state := jsonb_set(v_state, array['players', (v_player_index - 1)::text], v_updated_player, false);

  if v_owner_index is not null and v_updated_owner is not null then
    v_state := jsonb_set(v_state, array['players', (v_owner_index - 1)::text], v_updated_owner, false);
  end if;

  if v_tenders_state is not null then
    v_state := jsonb_set(v_state, '{tenders}', v_tenders_state, true);
  end if;

  if v_companies_state is not null then
    v_state := jsonb_set(v_state, '{companies}', v_companies_state, true);
  end if;

  if v_directors_state is not null then
    v_state := jsonb_set(v_state, '{directors}', v_directors_state, true);
  end if;

  v_state := jsonb_set(v_state, '{pendingAction}', 'null'::jsonb, true);
  v_state := jsonb_set(v_state, '{currentTurnPlayerId}', to_jsonb(v_next_player_id::text), true);
  v_state := jsonb_set(
    v_state,
    '{turn}',
    jsonb_build_object(
      'id', case
        when v_action_type is not null then coalesce(v_game.state#>>'{turn,id}', gen_random_uuid()::text)
        else gen_random_uuid()::text
      end,
      'gameId', v_game.id,
      'number', v_turn_number,
      'playerId', v_player.id,
      'phase', 'finished',
      'dice', case when v_move_die is null then '[]'::jsonb else jsonb_build_array(v_move_die) end,
      'fromCellId', coalesce(v_from_cell_id, v_cell_id),
      'toCellId', coalesce(v_to_cell_id, v_cell_id),
      'startedAt', case
        when v_action_type is not null then coalesce(v_game.state#>>'{turn,startedAt}', v_now::text)
        else v_now::text
      end,
      'finishedAt', v_now,
      'passedStart', v_passed_start,
      'startBonus', v_start_bonus,
      'startBonusApplied', v_start_bonus > 0
    ),
    true
  );
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
    v_event_type,
    v_message,
    v_log_payload || jsonb_build_object(
      'nextPlayerId',
      v_next_player_id,
      'bot',
      true,
      'debtLocked',
      v_debt_locked
    )
  );

  return jsonb_build_object(
    'game_id', v_game.id,
    'player_id', v_player.id,
    'next_player_id', v_next_player_id,
    'event_type', v_event_type,
    'state', v_state
  );
end;
$$;

grant execute on function public.resolve_bot_turn(uuid) to authenticated;

notify pgrst, 'reload schema';
