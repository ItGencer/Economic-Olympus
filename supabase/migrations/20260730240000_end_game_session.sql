create or replace function public.end_game(p_game_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_game public.games%rowtype;
  v_actor_player_id uuid;
  v_is_participant boolean := false;
  v_state jsonb;
  v_now timestamptz := now();
  v_turn_number integer;
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

  select players.id
  into v_actor_player_id
  from public.players
  where players.game_id = v_game.id
    and players.user_id = v_user_id
  order by players.seat_number
  limit 1;

  v_is_participant := v_actor_player_id is not null;

  if not v_is_participant
    and v_game.created_by_user_id is distinct from v_user_id then
    raise exception 'only_participants_can_end_game';
  end if;

  if v_game.status = 'finished' then
    return jsonb_build_object(
      'game_id', v_game.id,
      'join_code', v_game.join_code,
      'already_finished', true,
      'state', v_game.state
    );
  end if;

  v_state := coalesce(v_game.state, '{}'::jsonb);

  if jsonb_typeof(v_state) <> 'object' then
    v_state := '{}'::jsonb;
  end if;

  v_turn_number := coalesce((v_state#>>'{turn,number}')::integer, null);

  v_state := v_state || jsonb_build_object(
    'gameId', v_game.id,
    'status', 'finished',
    'joinCode', v_game.join_code,
    'maxPlayers', v_game.max_players,
    'currentTurnPlayerId', null,
    'winnerPlayerId', null,
    'pendingAction', null,
    'updatedAt', v_now
  );

  if v_state->'turn' is not null
    and v_state->'turn' <> 'null'::jsonb
    and jsonb_typeof(v_state->'turn') = 'object' then
    v_state := jsonb_set(v_state, '{turn,phase}', to_jsonb('finished'::text), true);
    v_state := jsonb_set(v_state, '{turn,pendingActionId}', 'null'::jsonb, true);
    v_state := jsonb_set(v_state, '{turn,finishedAt}', to_jsonb(v_now), true);
  end if;

  update public.games
  set
    status = 'finished',
    current_turn_player_id = null,
    winner_player_id = null,
    finished_at = v_now,
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
    v_turn_number,
    v_actor_player_id,
    'game_ended_manually',
    'Game ended manually',
    jsonb_build_object(
      'endedByUserId', v_user_id,
      'endedByPlayerId', v_actor_player_id,
      'winnerPlayerId', null
    )
  );

  return jsonb_build_object(
    'game_id', v_game.id,
    'join_code', v_game.join_code,
    'already_finished', false,
    'state', v_state
  );
end;
$$;

grant execute on function public.end_game(uuid) to authenticated;
