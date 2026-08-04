create or replace function public.get_director_cell_params(p_cell_id text)
returns jsonb
language sql
immutable
security definer
set search_path = public
as $$
  select case
    when p_cell_id in ('outer-director-08', 'outer-director-25') then
      '{"minOwnershipPercent":51,"votingCoefficient":1,"voteDifficulty":7}'::jsonb
    else null
  end;
$$;

create or replace function public.is_director_cell(p_cell_id text)
returns boolean
language sql
immutable
security definer
set search_path = public
as $$
  select public.get_director_cell_params(p_cell_id) is not null;
$$;

create or replace function public.build_game_directors_state(p_game_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    jsonb_object_agg(
      directors.id::text,
      jsonb_build_object(
        'id', directors.id,
        'gameId', directors.game_id,
        'companyId', companies.config_id,
        'playerId', directors.player_id,
        'status', directors.status::text,
        'votingCoefficient', directors.voting_coefficient,
        'voteDifficulty', directors.vote_difficulty,
        'electedAt', directors.elected_at
      )
    ),
    '{}'::jsonb
  )
  from public.directors
  join public.companies
    on companies.id = directors.company_id
  where directors.game_id = p_game_id;
$$;

create or replace function public.resolve_director(
  p_game_id uuid,
  p_player_id uuid default null
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
  v_updated_player jsonb;
  v_state jsonb;
  v_params jsonb;
  v_companies_state jsonb;
  v_directors_state jsonb;
  v_director_ids jsonb;
  v_created_directors jsonb := '[]'::jsonb;
  v_eligible_companies jsonb := '[]'::jsonb;
  v_player_index integer;
  v_turn_number integer;
  v_created_count integer := 0;
  v_min_ownership integer;
  v_vote_difficulty integer;
  v_cell_id text;
  v_voting_coefficient numeric;
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

  if v_game.state->'pendingAction' is not null
    and v_game.state->'pendingAction' <> 'null'::jsonb then
    raise exception 'pending_action_must_be_resolved';
  end if;

  if p_player_id is null then
    select *
    into v_player
    from public.players
    where game_id = v_game.id
      and user_id = v_user_id;
  else
    select *
    into v_player
    from public.players
    where game_id = v_game.id
      and id = p_player_id;
  end if;

  if not found then
    raise exception 'player_not_in_game';
  end if;

  if v_player.user_id is distinct from v_user_id then
    raise exception 'player_not_owned_by_user';
  end if;

  if v_game.current_turn_player_id is distinct from v_player.id then
    raise exception 'not_your_turn';
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
  v_updated_player := v_player_json;
  v_cell_id := coalesce(nullif(v_player_json->>'cellId', ''), '');
  v_params := public.get_director_cell_params(v_cell_id);

  if v_params is null then
    raise exception 'not_director_cell';
  end if;

  v_min_ownership := coalesce((v_params->>'minOwnershipPercent')::integer, 51);
  v_voting_coefficient := coalesce((v_params->>'votingCoefficient')::numeric, 1);
  v_vote_difficulty := coalesce((v_params->>'voteDifficulty')::integer, 7);
  v_turn_number := coalesce((v_game.state#>>'{turn,number}')::integer, 0);

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'companyId', companies.config_id,
        'name', companies.name,
        'ownershipPercent',
        round((shares.share_count::numeric / greatest(companies.total_shares, 1)::numeric) * 100, 2),
        'hasActiveDirector', active_directors.id is not null,
        'activeDirectorId', active_directors.id
      )
      order by companies.config_id
    ),
    '[]'::jsonb
  )
  into v_eligible_companies
  from public.companies
  join public.shares
    on shares.company_id = companies.id
   and shares.player_id = v_player.id
  left join public.directors active_directors
    on active_directors.company_id = companies.id
   and active_directors.status = 'active'
  where companies.game_id = v_game.id
    and (shares.share_count::numeric / greatest(companies.total_shares, 1)::numeric) * 100 >= v_min_ownership;

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
    returning
      id,
      company_id,
      player_id,
      status,
      voting_coefficient,
      vote_difficulty,
      elected_at
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
    select
      directors.id::text as id,
      directors.elected_at
    from public.directors
    where directors.game_id = v_game.id
      and directors.player_id = v_player.id
      and directors.status = 'active'
  ) director_ids;

  v_companies_state := public.build_game_companies_state(v_game.id);
  v_directors_state := public.build_game_directors_state(v_game.id);
  v_updated_player := jsonb_set(v_updated_player, '{directorIds}', v_director_ids, true);
  v_updated_player := jsonb_set(v_updated_player, '{updatedAt}', to_jsonb(v_now), true);

  v_state := v_game.state;
  v_state := jsonb_set(
    v_state,
    array['players', (v_player_index - 1)::text],
    v_updated_player,
    false
  );
  v_state := jsonb_set(v_state, '{companies}', v_companies_state, true);
  v_state := jsonb_set(v_state, '{directors}', v_directors_state, true);
  v_state := jsonb_set(v_state, '{pendingAction}', 'null'::jsonb, true);
  v_state := jsonb_set(v_state, '{turn,phase}', to_jsonb('finished'::text), true);
  v_state := jsonb_set(v_state, '{turn,pendingActionId}', 'null'::jsonb, true);
  v_state := jsonb_set(v_state, '{turn,finishedAt}', to_jsonb(v_now), true);
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
    case when v_created_count > 0 then 'directors_elected' else 'director_no_change' end,
    case when v_created_count > 0 then 'Directors elected' else 'Director cell resolved without changes' end,
    jsonb_build_object(
      'cellId', v_cell_id,
      'minOwnershipPercent', v_min_ownership,
      'eligibleCompanies', v_eligible_companies,
      'createdDirectors', v_created_directors,
      'createdCount', v_created_count
    )
  );

  return jsonb_build_object(
    'game_id', v_game.id,
    'player_id', v_player.id,
    'cell_id', v_cell_id,
    'cell_type', 'director',
    'handled', true,
    'has_pending_action', false,
    'created_directors', v_created_directors,
    'created_count', v_created_count,
    'state', v_state
  );
end;
$$;

grant execute on function public.resolve_director(uuid, uuid) to authenticated;

create or replace function public.elect_ceo(p_game_id uuid)
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
  v_state jsonb;
  v_votes jsonb := '[]'::jsonb;
  v_directors_state jsonb;
  v_director_vote record;
  v_active_director_count integer;
  v_candidate_director_count integer;
  v_turn_number integer;
  v_candidate_image integer;
  v_die_one integer;
  v_die_two integer;
  v_dice_sum integer;
  v_candidate_result integer;
  v_supports_candidate boolean;
  v_vote_power numeric;
  v_total_votes numeric := 0;
  v_support_votes numeric := 0;
  v_support_percent numeric := 0;
  v_successful boolean := false;
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

  if v_game.current_turn_player_id is distinct from v_player.id then
    raise exception 'not_your_turn';
  end if;

  perform public.ensure_game_companies(v_game.id);

  v_players := coalesce(v_game.state->'players', '[]'::jsonb);

  select player_data
  into v_player_json
  from jsonb_array_elements(v_players) as players(player_data)
  where player_data->>'id' = v_player.id::text
  limit 1;

  if v_player_json is null then
    raise exception 'player_missing_from_state';
  end if;

  v_candidate_image := coalesce((v_player_json->>'image')::integer, 0);
  v_cell_id := coalesce(nullif(v_player_json->>'cellId', ''), 'inner-start-01');

  select count(*)::integer
  into v_active_director_count
  from public.directors
  where game_id = v_game.id
    and status = 'active';

  if v_active_director_count = 0 then
    raise exception 'active_director_required';
  end if;

  select count(*)::integer
  into v_candidate_director_count
  from public.directors
  where game_id = v_game.id
    and player_id = v_player.id
    and status = 'active';

  if v_candidate_director_count = 0 then
    raise exception 'candidate_active_director_required';
  end if;

  for v_director_vote in
    select
      directors.id as director_id,
      directors.player_id as director_player_id,
      directors.vote_difficulty,
      directors.voting_coefficient,
      companies.config_id as company_id,
      companies.name as company_name,
      round(
        (coalesce(shares.share_count, 0)::numeric / greatest(companies.total_shares, 1)::numeric) * 100,
        2
      ) as ownership_percent
    from public.directors
    join public.companies
      on companies.id = directors.company_id
    left join public.shares
      on shares.company_id = directors.company_id
     and shares.player_id = directors.player_id
    where directors.game_id = v_game.id
      and directors.status = 'active'
    order by directors.elected_at, directors.id
  loop
    v_die_one := public.random_int_between(1, 6);
    v_die_two := public.random_int_between(1, 6);
    v_dice_sum := v_die_one + v_die_two;
    v_candidate_result := v_dice_sum + v_candidate_image;
    v_vote_power := v_director_vote.ownership_percent * v_director_vote.voting_coefficient;
    v_supports_candidate := v_candidate_result >= v_director_vote.vote_difficulty;
    v_total_votes := v_total_votes + v_vote_power;

    if v_supports_candidate then
      v_support_votes := v_support_votes + v_vote_power;
    end if;

    v_votes := v_votes || jsonb_build_array(
      jsonb_build_object(
        'directorId', v_director_vote.director_id,
        'directorPlayerId', v_director_vote.director_player_id,
        'companyId', v_director_vote.company_id,
        'companyName', v_director_vote.company_name,
        'ownershipPercent', v_director_vote.ownership_percent,
        'votingCoefficient', v_director_vote.voting_coefficient,
        'votePower', v_vote_power,
        'voteDifficulty', v_director_vote.vote_difficulty,
        'dice', jsonb_build_array(v_die_one, v_die_two),
        'diceSum', v_dice_sum,
        'candidateImage', v_candidate_image,
        'candidateResult', v_candidate_result,
        'supportsCandidate', v_supports_candidate
      )
    );
  end loop;

  if v_total_votes <= 0 then
    raise exception 'active_director_votes_required';
  end if;

  v_support_percent := round((v_support_votes / v_total_votes) * 100, 2);
  v_successful := v_support_percent >= 51;
  v_turn_number := coalesce((v_game.state#>>'{turn,number}')::integer, 0) + 1;
  v_directors_state := public.build_game_directors_state(v_game.id);

  v_state := v_game.state;
  v_state := jsonb_set(v_state, '{directors}', v_directors_state, true);
  v_state := jsonb_set(v_state, '{pendingAction}', 'null'::jsonb, true);
  v_state := jsonb_set(
    v_state,
    '{turn}',
    jsonb_build_object(
      'id', gen_random_uuid(),
      'gameId', v_game.id,
      'number', v_turn_number,
      'playerId', v_player.id,
      'phase', 'finished',
      'dice', '[]'::jsonb,
      'fromCellId', v_cell_id,
      'toCellId', v_cell_id,
      'startedAt', v_now,
      'finishedAt', v_now
    ),
    true
  );
  v_state := jsonb_set(v_state, '{updatedAt}', to_jsonb(v_now), true);

  if v_successful then
    v_state := jsonb_set(v_state, '{status}', to_jsonb('finished'::text), true);
    v_state := jsonb_set(v_state, '{winnerPlayerId}', to_jsonb(v_player.id::text), true);
    v_state := jsonb_set(v_state, '{currentTurnPlayerId}', 'null'::jsonb, true);

    update public.games
    set
      status = 'finished',
      winner_player_id = v_player.id,
      current_turn_player_id = null,
      finished_at = v_now,
      state = v_state
    where id = v_game.id
    returning state into v_state;
  else
    v_next_player_id := public.get_next_turn_player_id(v_game.id, v_player.id);

    if v_next_player_id is null then
      raise exception 'next_turn_player_not_found';
    end if;

    v_state := jsonb_set(v_state, '{status}', to_jsonb('in_progress'::text), true);
    v_state := jsonb_set(v_state, '{winnerPlayerId}', 'null'::jsonb, true);
    v_state := jsonb_set(v_state, '{currentTurnPlayerId}', to_jsonb(v_next_player_id::text), true);

    update public.games
    set
      current_turn_player_id = v_next_player_id,
      state = v_state
    where id = v_game.id
    returning state into v_state;
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
    case when v_successful then 'ceo_election_won' else 'ceo_election_failed' end,
    case when v_successful then 'CEO election won' else 'CEO election failed' end,
    jsonb_build_object(
      'candidatePlayerId', v_player.id,
      'candidateImage', v_candidate_image,
      'votes', v_votes,
      'supportVotes', v_support_votes,
      'totalVotes', v_total_votes,
      'supportPercent', v_support_percent,
      'successful', v_successful,
      'winnerPlayerId', case when v_successful then v_player.id else null end,
      'nextPlayerId', case when v_successful then null else v_next_player_id end
    )
  );

  return jsonb_build_object(
    'game_id', v_game.id,
    'candidate_player_id', v_player.id,
    'votes', v_votes,
    'support_votes', v_support_votes,
    'total_votes', v_total_votes,
    'support_percent', v_support_percent,
    'successful', v_successful,
    'winner_player_id', case when v_successful then v_player.id else null end,
    'next_player_id', case when v_successful then null else v_next_player_id end,
    'state', v_state
  );
end;
$$;

grant execute on function public.elect_ceo(uuid) to authenticated;

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
    elsif public.is_director_cell(v_to_cell_id) then
      v_resolve_result := public.resolve_director(v_game.id, v_player.id);
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
