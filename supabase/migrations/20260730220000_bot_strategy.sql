create or replace function public.bot_should_accept_deal(
  p_balance integer,
  p_income integer,
  p_importance integer
)
returns boolean
language sql
immutable
security definer
set search_path = public
as $$
  select coalesce(p_income, 0) >= coalesce(p_importance, 12) * 500
    and coalesce(p_balance, 0) - coalesce(p_income, 0) > -5000;
$$;

create or replace function public.bot_should_buy_offer(
  p_balance integer,
  p_price integer
)
returns boolean
language sql
immutable
security definer
set search_path = public
as $$
  select coalesce(p_price, 0) >= 0
    and coalesce(p_balance, 0) >= coalesce(p_price, 0)
    and coalesce(p_price, 0)::numeric <= greatest(coalesce(p_balance, 0), 0)::numeric * 0.2;
$$;

create or replace function public.bot_client_stock_to_sell(
  p_inventory integer,
  p_max_stock_to_sell integer default null
)
returns integer
language sql
immutable
security definer
set search_path = public
as $$
  select greatest(
    least(
      greatest(coalesce(p_inventory, 0), 0),
      greatest(coalesce(p_max_stock_to_sell, p_inventory, 0), 0)
    ),
    0
  );
$$;

create or replace function public.bot_company_share_count(
  p_balance integer,
  p_share_price integer,
  p_max_purchasable integer
)
returns integer
language sql
immutable
security definer
set search_path = public
as $$
  select case
    when coalesce(p_share_price, 0) <= 0 then 0
    else greatest(
      least(
        greatest(coalesce(p_max_purchasable, 0), 0),
        floor((greatest(coalesce(p_balance, 0), 0)::numeric * 0.2) / p_share_price::numeric)::integer
      ),
      0
    )
  end;
$$;

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
  v_next_player_id uuid;
  v_players jsonb;
  v_player_json jsonb;
  v_updated_player jsonb;
  v_owner_player public.players%rowtype;
  v_owner_json jsonb;
  v_updated_owner jsonb;
  v_owner_index integer := null;
  v_state jsonb;
  v_pending_action jsonb;
  v_payload jsonb := '{}'::jsonb;
  v_cell jsonb;
  v_params jsonb;
  v_tender public.tenders%rowtype;
  v_company public.companies%rowtype;
  v_tenders_state jsonb := null;
  v_companies_state jsonb := null;
  v_directors_state jsonb := null;
  v_player_index integer;
  v_turn_number integer;
  v_die integer := null;
  v_die_one integer := null;
  v_die_two integer := null;
  v_player_die integer := null;
  v_bank_die integer := null;
  v_dice_sum integer := null;
  v_modified_result integer := null;
  v_player_score integer := null;
  v_bank_score integer := null;
  v_difference integer := null;
  v_percent integer := null;
  v_skip_turns integer;
  v_balance integer;
  v_owner_balance integer;
  v_image integer;
  v_inventory integer;
  v_successful_deals integer;
  v_failed_deals integer;
  v_income integer;
  v_importance integer;
  v_relationship integer;
  v_percent_step integer;
  v_stock_to_sell integer := null;
  v_sold_stock integer := null;
  v_revenue integer := null;
  v_amount integer := 0;
  v_tax_amount integer := 0;
  v_price integer := 0;
  v_image_gain integer := 0;
  v_buyout integer := 0;
  v_fee integer := 0;
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
  v_created_directors jsonb := '[]'::jsonb;
  v_created_count integer := 0;
  v_tender_ids jsonb;
  v_share_map jsonb;
  v_director_ids jsonb;
  v_cell_ids text[];
  v_cell_count integer;
  v_from_cell_id text;
  v_to_cell_id text;
  v_from_index integer;
  v_to_index integer;
  v_ring text;
  v_cell_id text;
  v_cell_type text;
  v_action_type text := null;
  v_decision text := null;
  v_sign text := null;
  v_event_type text := 'bot_turn_resolved';
  v_message text := 'Bot turn resolved';
  v_log_payload jsonb := '{}'::jsonb;
  v_debt_locked boolean;
  v_successful boolean := null;
  v_skipped boolean := false;
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

  v_next_player_id := public.get_next_turn_player_id(v_game.id, v_player.id);

  if v_next_player_id is null then
    raise exception 'next_turn_player_not_found';
  end if;

  v_player_json := v_players->(v_player_index - 1);
  v_updated_player := v_player_json;
  v_balance := coalesce((v_player_json->>'balance')::integer, 0);
  v_image := coalesce((v_player_json->>'image')::integer, 0);
  v_inventory := coalesce((v_player_json->>'inventory')::integer, 0);
  v_successful_deals := coalesce((v_player_json->>'successfulDeals')::integer, 0);
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
        'toCellId', v_to_cell_id
      );
    else
      v_die := public.random_int_between(1, 6);
      v_to_index := ((v_from_index - 1 + v_die) % v_cell_count) + 1;
      v_to_cell_id := v_cell_ids[v_to_index];
      v_cell_id := v_to_cell_id;
      v_cell := public.get_board_cell_config(v_cell_id);
      v_cell_type := coalesce(v_cell->>'type', 'unknown');
      v_params := coalesce(v_cell->'params', '{}'::jsonb);

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
          'die', v_die,
          'fromCellId', v_from_cell_id,
          'toCellId', v_to_cell_id,
          'skipped', false
        )
      );
    end if;
  end if;

  if not v_skipped then
    if v_action_type = 'casino_bet' or v_cell_type = 'casino' then
      v_decision := 'decline';
      v_event_type := 'bot_casino_skipped';
      v_message := 'Bot skipped casino';
      v_log_payload := jsonb_build_object('decision', v_decision, 'cellId', v_cell_id);

    elsif v_action_type = 'image_offer' or v_cell_type = 'image' then
      v_price := coalesce(
        (v_payload->>'price')::integer,
        public.random_int_between(
          coalesce((v_params->>'priceMin')::integer, 100),
          coalesce((v_params->>'priceMax')::integer, 3000)
        )
      );
      v_image_gain := coalesce(
        (v_payload->>'imageGain')::integer,
        public.random_int_between(
          coalesce((v_params->>'imageMin')::integer, 2),
          coalesce((v_params->>'imageMax')::integer, 5)
        )
      );
      v_decision := case
        when public.bot_should_buy_offer(v_balance, v_price) then 'accept'
        else 'decline'
      end;

      if v_decision = 'accept' then
        v_balance := v_balance - v_price;
        v_image := v_image + v_image_gain;
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
      v_price := coalesce(
        (v_payload->>'price')::integer,
        public.random_int_between(
          coalesce((v_params->>'priceMin')::integer, 100),
          coalesce((v_params->>'priceMax')::integer, 1000)
        )
      );
      v_image_gain := coalesce(
        (v_payload->>'imageGain')::integer,
        public.random_int_between(
          coalesce((v_params->>'imageMin')::integer, 1),
          coalesce((v_params->>'imageMax')::integer, 10)
        )
      );
      v_decision := case
        when public.bot_should_buy_offer(v_balance, v_price) then 'accept'
        else 'decline'
      end;

      if v_decision = 'accept' then
        v_balance := v_balance - v_price;
        v_image := v_image + v_image_gain;
      end if;

      v_event_type := case when v_decision = 'accept' then 'advertising_purchased' else 'advertising_declined' end;
      v_message := case when v_decision = 'accept' then 'Bot purchased advertising' else 'Bot declined advertising' end;
      v_log_payload := jsonb_build_object(
        'decision', v_decision,
        'price', v_price,
        'imageGain', v_image_gain,
        'balance', v_balance,
        'image', v_image
      );

    elsif v_action_type = 'deal_decision' or v_cell_type = 'deal' then
      v_params := coalesce(public.get_deal_cell_params(v_cell_id), v_params, '{}'::jsonb);
      v_income := coalesce(
        (v_payload->>'income')::integer,
        public.random_int_between(
          coalesce((v_params->>'incomeMin')::integer, 1000),
          coalesce((v_params->>'incomeMax')::integer, 10000)
        )
      );
      v_importance := coalesce(
        (v_payload->>'importance')::integer,
        public.random_int_between(
          coalesce((v_params->>'importanceMin')::integer, 2),
          coalesce((v_params->>'importanceMax')::integer, 12)
        )
      );
      v_decision := case
        when public.bot_should_accept_deal(v_balance, v_income, v_importance) then 'accept'
        else 'decline'
      end;

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

      v_event_type := case
        when v_decision = 'decline' then 'deal_declined'
        when v_successful then 'deal_successful'
        else 'deal_failed'
      end;
      v_message := case
        when v_decision = 'decline' then 'Bot declined deal'
        when v_successful then 'Bot completed deal'
        else 'Bot failed deal'
      end;
      v_log_payload := jsonb_build_object(
        'decision', v_decision,
        'income', v_income,
        'importance', v_importance,
        'dice', case when v_decision = 'accept' then jsonb_build_array(v_die_one, v_die_two) else '[]'::jsonb end,
        'diceSum', v_dice_sum,
        'image', v_image,
        'modifiedResult', v_modified_result,
        'successful', v_successful,
        'successfulDeals', v_successful_deals
      );

      if v_successful is true
        and v_ring = 'inner'
        and v_balance > 0
        and not v_debt_locked
        and v_successful_deals >= 7 then
        v_ring := 'outer';
        v_cell_id := public.get_outer_entry_cell_id();
        v_log_payload := v_log_payload || jsonb_build_object(
          'outerRingDecision',
          'move_to_outer',
          'targetCellId',
          v_cell_id
        );
      end if;

    elsif v_action_type = 'client_decision' or v_cell_type = 'client' then
      v_params := coalesce(public.get_client_cell_params(v_cell_id), v_params, '{}'::jsonb);
      v_relationship := coalesce(
        (v_payload->>'relationship')::integer,
        public.random_int_between(
          coalesce((v_params->>'relationshipMin')::integer, 1),
          coalesce((v_params->>'relationshipMax')::integer, 6)
        )
      );
      v_percent_step := coalesce((v_payload->>'percentStep')::integer, (v_params->>'percentStep')::integer, 10);
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
      v_decision := 'accept';
      v_event_type := 'client_stock_sold';
      v_message := 'Bot sold stock to client';
      v_log_payload := jsonb_build_object(
        'decision', v_decision,
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

    elsif v_action_type = 'outer_ring_choice' then
      if v_ring = 'inner' and v_balance > 0 and not v_debt_locked then
        v_ring := 'outer';
        v_cell_id := public.get_outer_entry_cell_id();
        v_decision := 'move_to_outer';
      else
        v_decision := 'stay_inner';
      end if;

      v_event_type := case when v_decision = 'move_to_outer' then 'outer_ring_moved' else 'outer_ring_stayed' end;
      v_message := case when v_decision = 'move_to_outer' then 'Bot moved to outer ring' else 'Bot stayed on inner ring' end;
      v_log_payload := jsonb_build_object(
        'decision', v_decision,
        'ring', v_ring,
        'cellId', v_cell_id
      );

    elsif v_cell_type = 'start' then
      v_event_type := 'cell_start';
      v_message := 'Bot resolved start';
      v_log_payload := jsonb_build_object('cellId', v_cell_id);

    elsif v_cell_type = 'salary' then
      v_amount := case
        when v_image > 0 then v_image * coalesce((v_params->>'imageMultiplier')::integer, 500)
        else 0
      end;
      v_balance := v_balance + v_amount;
      v_event_type := 'cell_salary';
      v_message := 'Bot resolved salary';
      v_log_payload := jsonb_build_object('cellId', v_cell_id, 'amount', v_amount, 'image', v_image);

    elsif v_cell_type = 'tax' then
      v_tax_amount := floor(greatest(v_balance, 0) * coalesce((v_params->>'rate')::numeric, 0.2))::integer;
      v_balance := v_balance - v_tax_amount;
      v_event_type := 'cell_tax';
      v_message := 'Bot resolved tax';
      v_log_payload := jsonb_build_object('cellId', v_cell_id, 'amount', v_tax_amount);

    elsif v_cell_type = 'negative_reputation' or v_cell_type = 'positive_reputation' then
      v_amount := coalesce((v_params->>'imageDelta')::integer, 0);
      v_image := v_image + v_amount;
      v_event_type := 'cell_reputation';
      v_message := 'Bot resolved reputation';
      v_log_payload := jsonb_build_object('cellId', v_cell_id, 'imageDelta', v_amount, 'image', v_image);

    elsif v_cell_type = 'vacation' then
      v_amount := coalesce((v_params->>'skipTurns')::integer, 1);
      v_skip_turns := v_skip_turns + v_amount;
      v_event_type := 'cell_vacation';
      v_message := 'Bot resolved vacation';
      v_log_payload := jsonb_build_object('cellId', v_cell_id, 'skipTurnsAdded', v_amount, 'skipTurns', v_skip_turns);

    elsif v_cell_type = 'random' then
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
      v_message := 'Bot resolved random';
      v_log_payload := jsonb_build_object('cellId', v_cell_id, 'amount', v_amount, 'sign', v_sign);

    else
      v_event_type := 'bot_cell_unhandled';
      v_message := 'Bot skipped unhandled cell';
      v_log_payload := jsonb_build_object('cellId', v_cell_id, 'cellType', v_cell_type, 'actionType', v_action_type);
    end if;
  end if;

  if v_balance < 0 and v_ring = 'outer' then
    v_ring := 'inner';
    v_cell_id := 'inner-start-01';
    v_debt_locked := true;
  elsif v_balance >= 0 then
    v_debt_locked := false;
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
      'dice', case when v_die is null then '[]'::jsonb else jsonb_build_array(v_die) end,
      'fromCellId', coalesce(v_from_cell_id, v_cell_id),
      'toCellId', coalesce(v_to_cell_id, v_cell_id),
      'startedAt', case
        when v_action_type is not null then coalesce(v_game.state#>>'{turn,startedAt}', v_now::text)
        else v_now::text
      end,
      'finishedAt', v_now
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
