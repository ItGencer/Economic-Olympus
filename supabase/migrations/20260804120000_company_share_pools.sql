alter table public.companies
  drop constraint if exists companies_total_shares_check;

alter table public.shares
  drop constraint if exists shares_share_count_check;

update public.companies
set
  name = case config_id
    when 'company-logistics' then 'Логістика'
    when 'company-retail' then 'Ритейл'
    when 'company-tech' then 'Технології'
    when 'company-finance' then 'Фінанси'
    when 'company-energy' then 'Енергетика'
    when 'company-media' then 'Медіа'
    else name
  end,
  total_shares = 2000,
  share_price = case config_id
    when 'company-logistics' then 1500
    when 'company-retail' then 500
    when 'company-tech' then 8000
    when 'company-finance' then 5000
    when 'company-energy' then 10000
    when 'company-media' then 2500
    else share_price
  end
where config_id in (
  'company-logistics',
  'company-retail',
  'company-tech',
  'company-finance',
  'company-energy',
  'company-media'
);

alter table public.companies
  alter column total_shares set default 2000,
  add constraint companies_total_shares_check check (total_shares = 2000);

alter table public.shares
  add constraint shares_share_count_check check (share_count between 0 and 2000);

create or replace function public.get_company_cell_params(p_cell_id text)
returns jsonb
language sql
immutable
security definer
set search_path = public
as $$
  with companies(cell_id, company_id, company_name, share_price, inventory_per_share) as (
    values
      ('outer-company-logistics-04', 'company-logistics', 'Логістика', 1500, 1),
      ('outer-company-retail-11', 'company-retail', 'Ритейл', 500, 1),
      ('outer-company-tech-14', 'company-tech', 'Технології', 8000, 1),
      ('outer-company-finance-18', 'company-finance', 'Фінанси', 5000, 1),
      ('outer-company-energy-22', 'company-energy', 'Енергетика', 10000, 1),
      ('outer-company-media-27', 'company-media', 'Медіа', 2500, 1)
  )
  select jsonb_build_object(
    'companyId', companies.company_id,
    'name', companies.company_name,
    'totalShares', 2000,
    'sharePrice', companies.share_price,
    'inventoryPerShare', companies.inventory_per_share
  )
  from companies
  where companies.cell_id = p_cell_id;
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
    (p_game_id, 'company-logistics', 'Логістика', 2000, 1500, 1),
    (p_game_id, 'company-retail', 'Ритейл', 2000, 500, 1),
    (p_game_id, 'company-tech', 'Технології', 2000, 8000, 1),
    (p_game_id, 'company-finance', 'Фінанси', 2000, 5000, 1),
    (p_game_id, 'company-energy', 'Енергетика', 2000, 10000, 1),
    (p_game_id, 'company-media', 'Медіа', 2000, 2500, 1)
  on conflict (game_id, config_id) do update
  set
    name = excluded.name,
    total_shares = excluded.total_shares,
    share_price = excluded.share_price,
    inventory_per_share = excluded.inventory_per_share;

  return public.build_game_companies_state(p_game_id);
end;
$$;
