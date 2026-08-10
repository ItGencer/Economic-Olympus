alter table public.players
  add column if not exists avatar_style text not null default 'adventurer',
  add column if not exists avatar_color text not null default '#7c3aed';

do $$
begin
  alter table public.players
    add constraint players_avatar_style_check
    check (
      avatar_style in (
        'adventurer',
        'bottts',
        'pixel-art',
        'identicon',
        'thumbs',
        'shapes'
      )
    );
exception
  when duplicate_object then null;
end $$;

do $$
begin
  alter table public.players
    add constraint players_avatar_color_check
    check (avatar_color ~ '^#[0-9A-Fa-f]{6}$');
exception
  when duplicate_object then null;
end $$;

create or replace function public.build_lobby_state(p_game_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'gameId', g.id,
    'status', g.status,
    'joinCode', g.join_code,
    'maxPlayers', g.max_players,
    'currentTurnPlayerId', g.current_turn_player_id,
    'winnerPlayerId', g.winner_player_id,
    'players', coalesce(players.players, '[]'::jsonb),
    'turn', null,
    'pendingAction', null,
    'companies', '{}'::jsonb,
    'tenders', '{}'::jsonb,
    'directors', '{}'::jsonb,
    'log', '[]'::jsonb,
    'createdAt', g.created_at,
    'updatedAt', g.updated_at
  )
  from public.games g
  left join lateral (
    select jsonb_agg(
      jsonb_build_object(
        'id', p.id,
        'gameId', p.game_id,
        'userId', p.user_id,
        'seatNumber', p.seat_number,
        'name', p.display_name,
        'isBot', p.is_bot,
        'avatarStyle', p.avatar_style,
        'avatarColor', p.avatar_color,
        'ring', 'inner',
        'cellId', 'inner-start-01',
        'balance', 10000,
        'image', 0,
        'inventory', 0,
        'successfulDeals', 0,
        'failedDeals', 0,
        'debtLocked', false,
        'skipTurns', 0,
        'shares', '{}'::jsonb,
        'tenderIds', '[]'::jsonb,
        'directorIds', '[]'::jsonb,
        'createdAt', p.created_at,
        'updatedAt', p.updated_at
      )
      order by p.seat_number
    ) as players
    from public.players p
    where p.game_id = g.id
  ) players on true
  where g.id = p_game_id;
$$;

create or replace function public.update_player_avatar(
  p_game_id uuid,
  p_avatar_style text,
  p_avatar_color text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_player public.players%rowtype;
  v_game public.games%rowtype;
  v_state jsonb;
  v_players jsonb;
  v_player_index integer;
  v_player_json jsonb;
  v_avatar_style text := lower(nullif(btrim(p_avatar_style), ''));
  v_avatar_color text := lower(nullif(btrim(p_avatar_color), ''));
begin
  if v_user_id is null then
    raise exception 'auth_required' using errcode = '28000';
  end if;

  if v_avatar_style not in (
    'adventurer',
    'bottts',
    'pixel-art',
    'identicon',
    'thumbs',
    'shapes'
  ) then
    raise exception 'invalid_avatar_style';
  end if;

  if v_avatar_color is null or v_avatar_color !~ '^#[0-9a-f]{6}$' then
    raise exception 'invalid_avatar_color';
  end if;

  select *
  into v_player
  from public.players
  where game_id = p_game_id
    and user_id = v_user_id
  for update;

  if not found then
    raise exception 'player_not_found';
  end if;

  update public.players
  set
    avatar_style = v_avatar_style,
    avatar_color = v_avatar_color
  where id = v_player.id
  returning * into v_player;

  select *
  into v_game
  from public.games
  where id = p_game_id
  for update;

  if not found then
    raise exception 'game_not_found';
  end if;

  v_state := coalesce(v_game.state, '{}'::jsonb);
  v_players := coalesce(v_state->'players', '[]'::jsonb);

  if jsonb_typeof(v_players) = 'array' then
    select players.ordinality::integer
    into v_player_index
    from jsonb_array_elements(v_players) with ordinality as players(player_data, ordinality)
    where players.player_data->>'id' = v_player.id::text
    limit 1;

    if v_player_index is not null then
      v_player_json := v_players->(v_player_index - 1);
      v_player_json := jsonb_set(
        v_player_json,
        '{avatarStyle}',
        to_jsonb(v_avatar_style),
        true
      );
      v_player_json := jsonb_set(
        v_player_json,
        '{avatarColor}',
        to_jsonb(v_avatar_color),
        true
      );
      v_player_json := jsonb_set(
        v_player_json,
        '{updatedAt}',
        to_jsonb(v_player.updated_at),
        true
      );
      v_state := jsonb_set(
        v_state,
        array['players', (v_player_index - 1)::text],
        v_player_json,
        false
      );
    end if;
  end if;

  update public.games
  set
    state = v_state,
    updated_at = now()
  where id = v_game.id
  returning state into v_state;

  return v_state;
end;
$$;

revoke execute on function public.update_player_avatar(uuid, text, text) from public;
grant execute on function public.update_player_avatar(uuid, text, text) to authenticated;

notify pgrst, 'reload schema';
