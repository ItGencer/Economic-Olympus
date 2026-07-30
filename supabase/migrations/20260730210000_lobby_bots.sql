create or replace function public.add_bot(p_game_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_game public.games%rowtype;
  v_player_id uuid;
  v_player_count integer;
  v_seat_number integer;
  v_bot_number integer := 1;
  v_display_name text;
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

  if v_game.created_by_user_id is distinct from v_user_id then
    raise exception 'only_owner_can_add_bot';
  end if;

  if v_game.status <> 'lobby' then
    raise exception 'game_is_not_in_lobby';
  end if;

  select count(*)::integer
  into v_player_count
  from public.players
  where game_id = v_game.id;

  if v_player_count >= v_game.max_players then
    raise exception 'game_is_full';
  end if;

  select seats.seat_number
  into v_seat_number
  from generate_series(1, v_game.max_players) as seats(seat_number)
  where not exists (
    select 1
    from public.players p
    where p.game_id = v_game.id
      and p.seat_number = seats.seat_number
  )
  order by seats.seat_number
  limit 1;

  if v_seat_number is null then
    raise exception 'no_free_seat';
  end if;

  loop
    v_display_name := 'Бот ' || v_bot_number;
    exit when not exists (
      select 1
      from public.players p
      where p.game_id = v_game.id
        and p.is_bot
        and p.display_name = v_display_name
    );

    v_bot_number := v_bot_number + 1;
  end loop;

  insert into public.players (
    game_id,
    user_id,
    seat_number,
    display_name,
    is_bot
  )
  values (
    v_game.id,
    null,
    v_seat_number,
    v_display_name,
    true
  )
  returning id into v_player_id;

  update public.games
  set state = public.build_lobby_state(v_game.id)
  where id = v_game.id
  returning state into v_state;

  return jsonb_build_object(
    'game_id', v_game.id,
    'player_id', v_player_id,
    'seat_number', v_seat_number,
    'display_name', v_display_name,
    'state', v_state
  );
end;
$$;

create or replace function public.remove_bot(p_player_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_game public.games%rowtype;
  v_player public.players%rowtype;
  v_state jsonb;
begin
  if v_user_id is null then
    raise exception 'auth_required' using errcode = '28000';
  end if;

  select *
  into v_player
  from public.players
  where id = p_player_id
  for update;

  if not found then
    raise exception 'player_not_found';
  end if;

  if not v_player.is_bot then
    raise exception 'player_is_not_bot';
  end if;

  select *
  into v_game
  from public.games
  where id = v_player.game_id
  for update;

  if not found then
    raise exception 'game_not_found';
  end if;

  if v_game.created_by_user_id is distinct from v_user_id then
    raise exception 'only_owner_can_remove_bot';
  end if;

  if v_game.status <> 'lobby' then
    raise exception 'game_is_not_in_lobby';
  end if;

  delete from public.players
  where id = v_player.id;

  update public.games
  set state = public.build_lobby_state(v_game.id)
  where id = v_game.id
  returning state into v_state;

  return jsonb_build_object(
    'game_id', v_game.id,
    'player_id', v_player.id,
    'state', v_state
  );
end;
$$;

grant execute on function public.add_bot(uuid) to authenticated;
grant execute on function public.remove_bot(uuid) to authenticated;
