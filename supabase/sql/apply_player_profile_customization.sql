create or replace function public.update_player_profile(
  p_game_id uuid,
  p_display_name text,
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
  v_display_name text := regexp_replace(btrim(coalesce(p_display_name, '')), '[[:space:]]+', ' ', 'g');
  v_avatar_style text := lower(nullif(btrim(p_avatar_style), ''));
  v_avatar_color text := lower(nullif(btrim(p_avatar_color), ''));
  v_now timestamptz := now();
begin
  if v_user_id is null then
    raise exception 'auth_required' using errcode = '28000';
  end if;

  if length(v_display_name) < 2 or length(v_display_name) > 32 then
    raise exception 'invalid_display_name';
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
    display_name = v_display_name,
    avatar_style = v_avatar_style,
    avatar_color = v_avatar_color,
    updated_at = v_now
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
      v_player_json := jsonb_set(v_player_json, '{name}', to_jsonb(v_display_name), true);
      v_player_json := jsonb_set(v_player_json, '{avatarStyle}', to_jsonb(v_avatar_style), true);
      v_player_json := jsonb_set(v_player_json, '{avatarColor}', to_jsonb(v_avatar_color), true);
      v_player_json := jsonb_set(v_player_json, '{updatedAt}', to_jsonb(v_now), true);
      v_state := jsonb_set(
        v_state,
        array['players', (v_player_index - 1)::text],
        v_player_json,
        false
      );
    end if;
  end if;

  v_state := jsonb_set(v_state, '{updatedAt}', to_jsonb(v_now), true);

  update public.games
  set
    state = v_state,
    updated_at = v_now
  where id = v_game.id
  returning state into v_state;

  return v_state;
end;
$$;

revoke execute on function public.update_player_profile(uuid, text, text, text) from public;
grant execute on function public.update_player_profile(uuid, text, text, text) to authenticated;

notify pgrst, 'reload schema';
