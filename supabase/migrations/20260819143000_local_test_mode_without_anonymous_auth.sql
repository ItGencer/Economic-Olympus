alter table public.games
  drop constraint if exists games_created_by_user_id_fkey;

alter table public.players
  drop constraint if exists players_user_id_fkey;

grant usage on schema public to anon;
grant select on
  public.games,
  public.players,
  public.game_log,
  public.companies,
  public.shares,
  public.tenders,
  public.directors
to anon;

drop policy if exists "Anon users can read games" on public.games;
create policy "Anon users can read games"
on public.games for select
to anon
using (true);

drop policy if exists "Anon users can read players" on public.players;
create policy "Anon users can read players"
on public.players for select
to anon
using (true);

drop policy if exists "Anon users can read game log" on public.game_log;
create policy "Anon users can read game log"
on public.game_log for select
to anon
using (true);

drop policy if exists "Anon users can read companies" on public.companies;
create policy "Anon users can read companies"
on public.companies for select
to anon
using (true);

drop policy if exists "Anon users can read shares" on public.shares;
create policy "Anon users can read shares"
on public.shares for select
to anon
using (true);

drop policy if exists "Anon users can read tenders" on public.tenders;
create policy "Anon users can read tenders"
on public.tenders for select
to anon
using (true);

drop policy if exists "Anon users can read directors" on public.directors;
create policy "Anon users can read directors"
on public.directors for select
to anon
using (true);

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
