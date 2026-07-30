create or replace function public.get_company_cell_params(p_cell_id text)
returns jsonb
language sql
immutable
security definer
set search_path = public
as $$
  with companies(cell_id, company_id, company_name, share_price, inventory_per_share) as (
    values
      ('outer-company-logistics-04', 'company-logistics', 'Логістика', 120, 1),
      ('outer-company-retail-11', 'company-retail', 'Ритейл', 100, 1),
      ('outer-company-tech-14', 'company-tech', 'Технології', 180, 1),
      ('outer-company-finance-18', 'company-finance', 'Фінанси', 200, 1),
      ('outer-company-energy-22', 'company-energy', 'Енергетика', 220, 1),
      ('outer-company-media-27', 'company-media', 'Медіа', 160, 1)
  )
  select jsonb_build_object(
    'companyId', companies.company_id,
    'name', companies.company_name,
    'totalShares', 100,
    'sharePrice', companies.share_price,
    'inventoryPerShare', companies.inventory_per_share
  )
  from companies
  where companies.cell_id = p_cell_id;
$$;

create or replace function public.is_company_cell(p_cell_id text)
returns boolean
language sql
immutable
security definer
set search_path = public
as $$
  select public.get_company_cell_params(p_cell_id) is not null;
$$;

create or replace function public.ensure_game_companies(p_game_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.companies (
    game_id,
    config_id,
    name,
    total_shares,
    share_price,
    inventory_per_share
  )
  values
    (p_game_id, 'company-logistics', 'Логістика', 100, 120, 1),
    (p_game_id, 'company-retail', 'Ритейл', 100, 100, 1),
    (p_game_id, 'company-tech', 'Технології', 100, 180, 1),
    (p_game_id, 'company-finance', 'Фінанси', 100, 200, 1),
    (p_game_id, 'company-energy', 'Енергетика', 100, 220, 1),
    (p_game_id, 'company-media', 'Медіа', 100, 160, 1)
  on conflict (game_id, config_id) do update
  set
    name = excluded.name,
    total_shares = excluded.total_shares,
    share_price = excluded.share_price,
    inventory_per_share = excluded.inventory_per_share;

  return public.build_game_companies_state(p_game_id);
end;
$$;

create or replace function public.build_game_companies_state(p_game_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    jsonb_object_agg(
      companies.config_id,
      jsonb_build_object(
        'id', companies.config_id,
        'gameId', companies.game_id,
        'name', companies.name,
        'totalShares', companies.total_shares,
        'sharePrice', floor(companies.share_price)::integer,
        'inventoryPerShare', floor(companies.inventory_per_share)::integer,
        'shareholders', coalesce(shareholders.shareholders, '{}'::jsonb)
      )
    ),
    '{}'::jsonb
  )
  from public.companies
  left join lateral (
    select coalesce(
      jsonb_object_agg(shares.player_id::text, shares.share_count),
      '{}'::jsonb
    ) as shareholders
    from public.shares
    where shares.company_id = companies.id
      and shares.share_count > 0
  ) shareholders on true
  where companies.game_id = p_game_id;
$$;

create or replace function public.resolve_company_landing(
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
  v_company public.companies%rowtype;
  v_companies_state jsonb;
  v_pending_action jsonb := 'null'::jsonb;
  v_pending_action_id uuid := gen_random_uuid();
  v_player_index integer;
  v_turn_number integer;
  v_balance integer;
  v_player_shares integer;
  v_sold_shares integer;
  v_available_shares integer;
  v_share_price integer;
  v_max_affordable_shares integer;
  v_max_purchasable_shares integer;
  v_cell_id text;
  v_event_type text;
  v_message text;
  v_payload jsonb;
  v_has_pending_action boolean := false;
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

  perform public.ensure_game_companies(v_game.id);

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
  v_params := public.get_company_cell_params(v_cell_id);

  if v_params is null then
    raise exception 'not_company_cell';
  end if;

  select *
  into v_company
  from public.companies
  where game_id = v_game.id
    and config_id = v_params->>'companyId'
  for update;

  if not found then
    raise exception 'company_not_found';
  end if;

  select coalesce(sum(share_count), 0)::integer
  into v_sold_shares
  from public.shares
  where company_id = v_company.id;

  select coalesce(max(share_count), 0)::integer
  into v_player_shares
  from public.shares
  where company_id = v_company.id
    and player_id = v_player.id;

  v_balance := coalesce((v_player_json->>'balance')::integer, 0);
  v_share_price := floor(v_company.share_price)::integer;
  v_available_shares := greatest(v_company.total_shares - v_sold_shares, 0);
  v_max_affordable_shares := case
    when v_share_price > 0 then greatest(floor(v_balance::numeric / v_share_price::numeric)::integer, 0)
    else 0
  end;
  v_max_purchasable_shares := greatest(least(v_available_shares, v_max_affordable_shares), 0);
  v_turn_number := coalesce((v_game.state#>>'{turn,number}')::integer, 0);

  if v_available_shares > 0 then
    v_has_pending_action := true;
    v_event_type := 'cell_company_pending';
    v_message := 'Company share purchase requested';
    v_pending_action := jsonb_build_object(
      'id', v_pending_action_id,
      'type', 'company_share_purchase',
      'playerId', v_player.id,
      'cellId', v_cell_id,
      'payload', jsonb_build_object(
        'companyId', v_company.config_id,
        'name', v_company.name,
        'totalShares', v_company.total_shares,
        'soldShares', v_sold_shares,
        'availableShares', v_available_shares,
        'playerShares', v_player_shares,
        'sharePrice', v_share_price,
        'inventoryPerShare', floor(v_company.inventory_per_share)::integer,
        'maxAffordableShares', v_max_affordable_shares,
        'maxPurchasableShares', v_max_purchasable_shares,
        'canBuy', v_max_purchasable_shares > 0
      ),
      'createdAt', v_now
    );
    v_payload := v_pending_action->'payload';
  else
    v_event_type := 'company_sold_out';
    v_message := 'Company shares sold out';
    v_payload := jsonb_build_object(
      'companyId', v_company.config_id,
      'name', v_company.name,
      'totalShares', v_company.total_shares,
      'soldShares', v_sold_shares,
      'availableShares', v_available_shares
    );
  end if;

  v_companies_state := public.build_game_companies_state(v_game.id);
  v_state := v_game.state;
  v_state := jsonb_set(v_state, '{companies}', v_companies_state, true);
  v_state := jsonb_set(v_state, '{pendingAction}', v_pending_action, true);
  v_state := jsonb_set(
    v_state,
    '{turn,phase}',
    to_jsonb((case when v_has_pending_action then 'awaiting_decision' else 'finished' end)::text),
    true
  );
  v_state := jsonb_set(
    v_state,
    '{turn,pendingActionId}',
    case when v_has_pending_action then to_jsonb(v_pending_action_id::text) else 'null'::jsonb end,
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

  return jsonb_build_object(
    'game_id', v_game.id,
    'player_id', v_player.id,
    'cell_id', v_cell_id,
    'cell_type', 'company',
    'handled', true,
    'has_pending_action', v_has_pending_action,
    'event_type', v_event_type,
    'payload', v_payload,
    'state', v_state
  );
end;
$$;

create or replace function public.resolve_company(
  p_game_id uuid,
  p_share_count integer
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
  v_company public.companies%rowtype;
  v_companies_state jsonb;
  v_share_map jsonb;
  v_player_index integer;
  v_turn_number integer;
  v_balance integer;
  v_inventory integer;
  v_sold_shares integer;
  v_available_shares integer;
  v_player_shares integer;
  v_share_count integer := coalesce(p_share_count, -1);
  v_share_price integer;
  v_inventory_per_share integer;
  v_inventory_gain integer := 0;
  v_cost integer := 0;
  v_company_id text;
  v_ring text;
  v_cell_id text;
  v_debt_locked boolean;
  v_now timestamptz := now();
begin
  if v_user_id is null then
    raise exception 'auth_required' using errcode = '28000';
  end if;

  if v_share_count < 0 then
    raise exception 'share_count_must_be_non_negative';
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
    or v_pending_action->>'type' <> 'company_share_purchase' then
    raise exception 'company_pending_action_required';
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

  perform public.ensure_game_companies(v_game.id);

  v_payload := coalesce(v_pending_action->'payload', '{}'::jsonb);
  v_company_id := nullif(v_payload->>'companyId', '');

  if v_company_id is null then
    raise exception 'company_id_required';
  end if;

  select *
  into v_company
  from public.companies
  where game_id = v_game.id
    and config_id = v_company_id
  for update;

  if not found then
    raise exception 'company_not_found';
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
  v_inventory := coalesce((v_player_json->>'inventory')::integer, 0);
  v_share_map := coalesce(v_player_json->'shares', '{}'::jsonb);
  v_share_price := floor(v_company.share_price)::integer;
  v_inventory_per_share := floor(v_company.inventory_per_share)::integer;
  v_ring := coalesce(nullif(v_player_json->>'ring', ''), 'outer');
  v_cell_id := coalesce(nullif(v_player_json->>'cellId', ''), v_pending_action->>'cellId');
  v_debt_locked := coalesce((v_player_json->>'debtLocked')::boolean, false);
  v_turn_number := coalesce((v_game.state#>>'{turn,number}')::integer, 0);

  select coalesce(sum(share_count), 0)::integer
  into v_sold_shares
  from public.shares
  where company_id = v_company.id;

  select coalesce(max(share_count), 0)::integer
  into v_player_shares
  from public.shares
  where company_id = v_company.id
    and player_id = v_player.id;

  v_available_shares := greatest(v_company.total_shares - v_sold_shares, 0);

  if v_share_count > 0 then
    if v_share_count > v_available_shares then
      raise exception 'share_count_exceeds_available_shares';
    end if;

    v_cost := v_share_count * v_share_price;

    if v_balance < v_cost then
      raise exception 'insufficient_balance_for_shares';
    end if;

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
    v_share_map := jsonb_set(
      v_share_map,
      array[v_company.config_id],
      to_jsonb(v_player_shares),
      true
    );
  else
    v_share_map := v_share_map - v_company.config_id;
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
  v_updated_player := jsonb_set(v_updated_player, '{inventory}', to_jsonb(v_inventory), true);
  v_updated_player := jsonb_set(v_updated_player, '{shares}', v_share_map, true);
  v_updated_player := jsonb_set(v_updated_player, '{ring}', to_jsonb(v_ring), true);
  v_updated_player := jsonb_set(v_updated_player, '{cellId}', to_jsonb(v_cell_id), true);
  v_updated_player := jsonb_set(v_updated_player, '{debtLocked}', to_jsonb(v_debt_locked), true);
  v_updated_player := jsonb_set(v_updated_player, '{updatedAt}', to_jsonb(v_now), true);

  v_companies_state := public.build_game_companies_state(v_game.id);
  v_state := v_game.state;
  v_state := jsonb_set(
    v_state,
    array['players', (v_player_index - 1)::text],
    v_updated_player,
    false
  );
  v_state := jsonb_set(v_state, '{companies}', v_companies_state, true);
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
    case when v_share_count > 0 then 'company_shares_purchased' else 'company_purchase_skipped' end,
    case when v_share_count > 0 then 'Company shares purchased' else 'Company purchase skipped' end,
    jsonb_build_object(
      'companyId', v_company.config_id,
      'name', v_company.name,
      'shareCount', v_share_count,
      'sharePrice', v_share_price,
      'cost', v_cost,
      'inventoryGain', v_inventory_gain,
      'playerShares', v_player_shares,
      'ownershipPercent', v_player_shares,
      'nextPlayerId', v_next_player_id,
      'debtLocked', v_debt_locked
    )
  );

  return jsonb_build_object(
    'game_id', v_game.id,
    'player_id', v_player.id,
    'company_id', v_company.config_id,
    'share_count', v_share_count,
    'cost', v_cost,
    'inventory_gain', v_inventory_gain,
    'player_shares', v_player_shares,
    'ownership_percent', v_player_shares,
    'next_player_id', v_next_player_id,
    'state', v_state
  );
end;
$$;

grant execute on function public.resolve_company(uuid, integer) to authenticated;

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
    if public.is_deal_cell(v_to_cell_id) then
      v_resolve_result := public.create_deal_pending_action(v_game.id, v_player.id);
    elsif public.is_client_cell(v_to_cell_id) then
      v_resolve_result := public.create_client_pending_action(v_game.id, v_player.id);
    elsif public.is_tender_cell(v_to_cell_id) then
      v_resolve_result := public.resolve_tender_landing(v_game.id, v_player.id);
    elsif public.is_company_cell(v_to_cell_id) then
      v_resolve_result := public.resolve_company_landing(v_game.id, v_player.id);
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
    'cell_result', v_resolve_result,
    'state', v_state
  );
end;
$$;
