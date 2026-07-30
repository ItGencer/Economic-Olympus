create or replace function public.leave_game(p_game_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_game public.games%rowtype;
  v_player public.players%rowtype;
  v_next_owner_user_id uuid;
  v_remaining_count integer;
  v_state jsonb;
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

  select *
  into v_player
  from public.players
  where game_id = v_game.id
    and user_id = v_user_id
  for update;

  if not found then
    raise exception 'player_not_in_game';
  end if;

  if v_game.status <> 'lobby' then
    raise exception 'leave_game_allowed_only_in_lobby';
  end if;

  delete from public.players
  where id = v_player.id;

  select count(*)
  into v_remaining_count
  from public.players
  where game_id = v_game.id;

  if v_remaining_count = 0 then
    delete from public.games
    where id = v_game.id;

    return jsonb_build_object(
      'game_id', v_game.id,
      'join_code', v_game.join_code,
      'deleted', true
    );
  end if;

  select user_id
  into v_next_owner_user_id
  from public.players
  where game_id = v_game.id
    and user_id is not null
  order by seat_number
  limit 1;

  update public.games
  set
    created_by_user_id = case
      when v_game.created_by_user_id = v_user_id then v_next_owner_user_id
      else v_game.created_by_user_id
    end,
    state = public.build_lobby_state(v_game.id)
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
    null,
    null,
    'player_left_lobby',
    'Player left lobby',
    jsonb_build_object(
      'player_id', v_player.id,
      'player_name', v_player.display_name,
      'seat_number', v_player.seat_number,
      'remaining_players', v_remaining_count
    )
  );

  return jsonb_build_object(
    'game_id', v_game.id,
    'join_code', v_game.join_code,
    'deleted', false,
    'state', v_state
  );
end;
$$;

grant execute on function public.leave_game(uuid) to authenticated;
