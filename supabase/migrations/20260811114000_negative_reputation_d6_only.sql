create or replace function public.create_negative_reputation_pending_action(
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

  if not public.is_negative_reputation_cell(v_cell_id) then
    raise exception 'not_negative_reputation_cell';
  end if;

  v_turn_number := coalesce((v_game.state#>>'{turn,number}')::integer, 0);
  v_pending_action := jsonb_build_object(
    'id', v_pending_action_id,
    'type', 'negative_reputation',
    'playerId', v_player.id,
    'cellId', v_cell_id,
    'payload', jsonb_build_object(
      'phase', 'initial',
      'dieMin', 1,
      'dieMax', 6,
      'imageBefore', coalesce((v_player_json->>'image')::integer, 0),
      'decisions', jsonb_build_array('roll')
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
    'cell_negative_reputation_pending',
    'Негативна репутація очікує кидок',
    v_pending_action->'payload'
  );

  return jsonb_build_object(
    'game_id', v_game.id,
    'player_id', v_player.id,
    'cell_id', v_cell_id,
    'cell_type', 'negative_reputation',
    'handled', true,
    'has_pending_action', true,
    'event_type', 'cell_negative_reputation_pending',
    'payload', v_pending_action->'payload',
    'state', v_state
  );
end;
$$;

create or replace function public.resolve_negative_reputation(
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
  v_phase text;
  v_die integer := null;
  v_image_before integer := null;
  v_image_after integer := null;
  v_image_loss integer := null;
  v_next_player_id uuid;
  v_now timestamptz := now();
begin
  if v_user_id is null then
    raise exception 'auth_required' using errcode = '28000';
  end if;

  if v_decision not in ('roll', 'confirm') then
    raise exception 'invalid_negative_reputation_decision';
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
    or v_pending_action->>'type' <> 'negative_reputation' then
    raise exception 'negative_reputation_pending_action_required';
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
  v_turn_number := coalesce((v_game.state#>>'{turn,number}')::integer, 0);
  v_image_before := coalesce((v_player_json->>'image')::integer, 0);

  if v_decision = 'roll' then
    if v_phase <> 'initial' then
      raise exception 'negative_reputation_roll_already_resolved';
    end if;

    v_die := public.random_int_between(1, 6);
    v_image_loss := v_die;
    v_image_after := v_image_before - v_image_loss;
    v_payload := v_payload || jsonb_build_object(
      'phase', 'roll_ready',
      'die', v_die,
      'imageBefore', v_image_before,
      'imageLoss', v_image_loss,
      'imageAfter', v_image_after,
      'decisions', jsonb_build_array('confirm')
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
      'die', v_die,
      'image_loss', v_image_loss,
      'image_after', v_image_after,
      'state', v_state
    );
  end if;

  if v_phase not in ('roll_ready', 'dice_rolled', 'multiplier_ready') then
    raise exception 'negative_reputation_dice_roll_required';
  end if;

  v_die := coalesce(nullif(v_payload->>'die', '')::integer, 1);
  v_image_loss := v_die;
  v_image_after := v_image_before - v_image_loss;
  v_next_player_id := public.get_next_turn_player_id(v_game.id, v_player.id);

  if v_next_player_id is null then
    raise exception 'next_turn_player_not_found';
  end if;

  v_updated_player := jsonb_set(v_updated_player, '{image}', to_jsonb(v_image_after), true);
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
    'negative_reputation_applied',
    'Негативна репутація зменшила імідж',
    jsonb_build_object(
      'actionId', v_pending_action->>'id',
      'die', v_die,
      'imageBefore', v_image_before,
      'imageLoss', v_image_loss,
      'imageAfter', v_image_after,
      'imageDelta', -v_image_loss,
      'nextPlayerId', v_next_player_id
    )
  );

  return jsonb_build_object(
    'game_id', v_game.id,
    'player_id', v_player.id,
    'decision', v_decision,
    'die', v_die,
    'image_loss', v_image_loss,
    'image_before', v_image_before,
    'image_after', v_image_after,
    'next_player_id', v_next_player_id,
    'state', v_state
  );
end;
$$;

grant execute on function public.resolve_negative_reputation(uuid, text) to authenticated;
