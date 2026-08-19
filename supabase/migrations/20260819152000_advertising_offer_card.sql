create or replace function public.resolve_advertising_offer(
  p_game_id uuid,
  p_decision text,
  p_image_gain integer default null
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
  v_image integer;
  v_price integer := 0;
  v_image_gain integer := 0;
  v_ring text;
  v_cell_id text;
  v_debt_locked boolean;
  v_next_player_id uuid;
  v_turn_number integer;
  v_decision text := lower(btrim(coalesce(p_decision, '')));
  v_now timestamptz := now();
begin
  if v_user_id is null then
    raise exception 'auth_required' using errcode = '28000';
  end if;

  if v_decision not in ('accept', 'decline') then
    raise exception 'invalid_advertising_decision';
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
    or v_pending_action->>'type' <> 'advertising_offer' then
    raise exception 'advertising_pending_action_required';
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
  v_image := coalesce((v_player_json->>'image')::integer, 0);
  v_ring := coalesce(nullif(v_player_json->>'ring', ''), 'inner');
  v_cell_id := coalesce(nullif(v_player_json->>'cellId', ''), v_pending_action->>'cellId');
  v_debt_locked := coalesce((v_player_json->>'debtLocked')::boolean, false);
  v_turn_number := coalesce((v_game.state#>>'{turn,number}')::integer, 0);

  if v_decision = 'accept' then
    v_image_gain := greatest(1, least(coalesce(p_image_gain, 1), 9));
    v_price := v_image_gain * 1500;

    if v_balance < v_price then
      raise exception 'insufficient_balance_for_advertising';
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
    case when v_decision = 'accept' then 'advertising_purchased' else 'advertising_declined' end,
    case when v_decision = 'accept' then 'Advertising purchased' else 'Advertising declined' end,
    jsonb_build_object(
      'actionId', v_pending_action->>'id',
      'decision', v_decision,
      'price', v_price,
      'unitPrice', 1500,
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
    'unit_price', 1500,
    'image_gain', v_image_gain,
    'next_player_id', v_next_player_id,
    'state', v_state
  );
end;
$$;

revoke execute on function public.resolve_advertising_offer(uuid, text, integer) from public;
grant execute on function public.resolve_advertising_offer(uuid, text, integer) to authenticated;

create or replace function public.run_test_rpc(
  p_test_user_id uuid,
  p_rpc_name text,
  p_args jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_test_user_id is null then
    raise exception 'test_user_required' using errcode = '28000';
  end if;

  if p_rpc_name is null or btrim(p_rpc_name) = '' then
    raise exception 'rpc_name_required';
  end if;

  p_args := coalesce(p_args, '{}'::jsonb);

  perform set_config('request.jwt.claim.sub', p_test_user_id::text, true);
  perform set_config(
    'request.jwt.claims',
    jsonb_build_object(
      'role', 'authenticated',
      'sub', p_test_user_id::text
    )::text,
    true
  );

  case p_rpc_name
    when 'create_game' then
      return public.create_game(
        coalesce(nullif(p_args->>'p_max_players', '')::integer, 6),
        coalesce(nullif(p_args->>'p_display_name', ''), 'Тестовий гравець')
      );
    when 'join_game' then
      return public.join_game(
        coalesce(nullif(p_args->>'p_join_code', ''), ''),
        coalesce(nullif(p_args->>'p_display_name', ''), 'Тестовий гравець')
      );
    when 'start_game' then
      return public.start_game((p_args->>'p_game_id')::uuid);
    when 'add_bot' then
      return public.add_bot((p_args->>'p_game_id')::uuid);
    when 'remove_bot' then
      return public.remove_bot((p_args->>'p_player_id')::uuid);
    when 'end_game' then
      return public.end_game((p_args->>'p_game_id')::uuid);
    when 'leave_game' then
      return public.leave_game((p_args->>'p_game_id')::uuid);
    when 'roll_dice' then
      return public.roll_dice((p_args->>'p_game_id')::uuid);
    when 'resolve_deal' then
      return public.resolve_deal(
        (p_args->>'p_game_id')::uuid,
        p_args->>'p_decision'
      );
    when 'ring_transition' then
      return public.ring_transition(
        (p_args->>'p_game_id')::uuid,
        p_args->>'p_decision'
      );
    when 'resolve_casino_bet' then
      return public.resolve_casino_bet(
        (p_args->>'p_game_id')::uuid,
        p_args->>'p_decision',
        nullif(p_args->>'p_bet_amount', '')::integer,
        nullif(p_args->>'p_parity', '')
      );
    when 'resolve_image_offer' then
      return public.resolve_image_offer(
        (p_args->>'p_game_id')::uuid,
        p_args->>'p_decision'
      );
    when 'resolve_advertising_offer' then
      return public.resolve_advertising_offer(
        (p_args->>'p_game_id')::uuid,
        p_args->>'p_decision',
        nullif(p_args->>'p_image_gain', '')::integer
      );
    when 'resolve_random_event' then
      return public.resolve_random_event(
        (p_args->>'p_game_id')::uuid,
        p_args->>'p_decision'
      );
    when 'resolve_negative_reputation' then
      return public.resolve_negative_reputation(
        (p_args->>'p_game_id')::uuid,
        p_args->>'p_decision'
      );
    when 'resolve_salary' then
      return public.resolve_salary(
        (p_args->>'p_game_id')::uuid,
        p_args->>'p_decision'
      );
    when 'resolve_tax_payment' then
      return public.resolve_tax_payment((p_args->>'p_game_id')::uuid);
    when 'resolve_client' then
      return public.resolve_client(
        (p_args->>'p_game_id')::uuid,
        nullif(p_args->>'p_decision', ''),
        nullif(p_args->>'p_stock_to_sell', '')::integer
      );
    when 'resolve_tender' then
      return public.resolve_tender(
        (p_args->>'p_game_id')::uuid,
        p_args->>'p_decision'
      );
    when 'resolve_company' then
      return public.resolve_company(
        (p_args->>'p_game_id')::uuid,
        coalesce(nullif(p_args->>'p_share_count', '')::integer, 0)
      );
    when 'elect_ceo' then
      return public.elect_ceo((p_args->>'p_game_id')::uuid);
    when 'resolve_bot_turn' then
      return public.resolve_bot_turn((p_args->>'p_game_id')::uuid);
    when 'update_player_profile' then
      return public.update_player_profile(
        (p_args->>'p_game_id')::uuid,
        coalesce(nullif(p_args->>'p_display_name', ''), 'Тестовий гравець'),
        coalesce(nullif(p_args->>'p_avatar_style', ''), 'adventurer'),
        coalesce(nullif(p_args->>'p_avatar_color', ''), '#7c3aed')
      );
    else
      raise exception 'test_rpc_not_allowed: %', p_rpc_name;
  end case;
end;
$$;

revoke execute on function public.run_test_rpc(uuid, text, jsonb) from public;
grant execute on function public.run_test_rpc(uuid, text, jsonb) to anon;
grant execute on function public.run_test_rpc(uuid, text, jsonb) to authenticated;

notify pgrst, 'reload schema';
