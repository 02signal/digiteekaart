-- Digiteekaart.ee / 02Signal lead quality engine foundation
-- PostgreSQL / Supabase compatible schema.
-- Purpose: internal operating memory for Toomas' B2B sales prioritisation.
--
-- Privacy rule:
-- - company facts and scores may be used in owner/operator views;
-- - personal contact data is stored only in the restricted table;
-- - do not expose restricted contacts through public views or static pages.

create schema if not exists sales_crm;

create table if not exists sales_crm.prospect_lists (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  description text,
  source text not null default 'rik_warehouse'
    check (source in ('rik_warehouse', 'manual', 'campaign', 'partner', 'other')),
  created_by text,
  created_at timestamptz not null default now()
);

create table if not exists sales_crm.crm_users (
  email text primary key,
  role text not null default 'sales'
    check (role in ('sales', 'admin')),
  active boolean not null default true,
  created_at timestamptz not null default now()
);

comment on table sales_crm.crm_users is
  'Allowed users for the internal CRM. Insert Toomas and admins here before exposing CRM data.';

insert into sales_crm.crm_users (email, role, active)
values ('ak@ettevotluskeskus.ee', 'admin', true)
on conflict (email) do update
set
  role = 'admin',
  active = true;

create table if not exists sales_crm.prospect_companies (
  id uuid primary key default gen_random_uuid(),
  list_id uuid references sales_crm.prospect_lists(id) on delete set null,
  registry_code text not null check (registry_code ~ '^[0-9]{8}$'),
  company_name text not null,
  legal_form text,
  status text,
  registered_at date,
  company_age_years integer check (company_age_years is null or company_age_years >= 0),
  primary_activity_code text,
  primary_activity_name text,
  address_summary text,
  average_revenue_last_two numeric(14, 2),
  latest_employee_count integer,
  latest_fiscal_year integer,
  de_minimis_left numeric(14, 2),
  de_minimis_checked_at timestamptz,
  vta_signal text not null default 'not_checked'
    check (vta_signal in ('not_checked', 'high_left', 'some_left', 'low_left', 'used_up', 'manual_review', 'source_unavailable')),
  sales_signal text not null default 'needs_review'
    check (sales_signal in ('good_first_call', 'needs_review', 'weak_fit', 'do_not_contact')),
  priority_score integer not null default 0 check (priority_score between 0 and 100),
  score_reason text[] not null default array[]::text[],
  recommended_pitch text,
  next_action text,
  owner_name text not null default 'Toomas',
  crm_status text not null default 'new'
    check (crm_status in (
      'new',
      'to_review',
      'call_next',
      'called',
      'not_relevant',
      'meeting_booked',
      'proposal_sent',
      'won',
      'lost',
      'do_not_contact'
    )),
  last_contacted_at timestamptz,
  next_follow_up_at timestamptz,
  source_system text not null default 'rik_warehouse',
  source_observed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (list_id, registry_code)
);

create index if not exists prospect_companies_registry_idx
  on sales_crm.prospect_companies (registry_code);

create index if not exists prospect_companies_status_score_idx
  on sales_crm.prospect_companies (crm_status, priority_score desc);

create index if not exists prospect_companies_name_idx
  on sales_crm.prospect_companies using gin (to_tsvector('simple', coalesce(company_name, '')));

create table if not exists sales_crm.prospect_contacts_restricted (
  id uuid primary key default gen_random_uuid(),
  prospect_company_id uuid references sales_crm.prospect_companies(id) on delete cascade,
  registry_code text not null check (registry_code ~ '^[0-9]{8}$'),
  person_name text,
  role text,
  email text,
  phone text,
  source_system text not null default 'rik_open_data',
  lawful_basis_note text not null default 'Legitimate interest for B2B contact about company support/digitalisation; review before outreach.',
  contact_allowed boolean not null default true,
  do_not_contact boolean not null default false,
  observed_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

comment on table sales_crm.prospect_contacts_restricted is
  'Restricted personal-data layer. Do not expose in public views, static pages, llms files or client-side API responses.';

create index if not exists prospect_contacts_restricted_company_idx
  on sales_crm.prospect_contacts_restricted (registry_code, observed_at desc);

create table if not exists sales_crm.prospect_activities (
  id uuid primary key default gen_random_uuid(),
  prospect_company_id uuid not null references sales_crm.prospect_companies(id) on delete cascade,
  activity_type text not null
    check (activity_type in (
      'note',
      'call_attempt',
      'call_connected',
      'email_sent',
      'meeting_booked',
      'qualification',
      'do_not_contact'
    )),
  activity_note text,
  activity_at timestamptz not null default now(),
  created_by text,
  created_at timestamptz not null default now()
);

create index if not exists prospect_activities_company_idx
  on sales_crm.prospect_activities (prospect_company_id, activity_at desc);

create table if not exists sales_crm.vta_check_queue (
  id uuid primary key default gen_random_uuid(),
  prospect_company_id uuid references sales_crm.prospect_companies(id) on delete cascade,
  registry_code text not null check (registry_code ~ '^[0-9]{8}$'),
  company_name text not null,
  priority_score integer not null default 0 check (priority_score between 0 and 100),
  check_method text not null default 'rar_public_manual'
    check (check_method in ('rar_public_manual', 'xtee_rar_api', 'manual')),
  queue_status text not null default 'queued'
    check (queue_status in ('queued', 'checking', 'checked', 'manual_review', 'failed', 'skipped')),
  scheduled_for date not null default current_date,
  checked_at timestamptz,
  rar_snapshot_id uuid references support_assessment.rar_de_minimis_snapshots(id),
  error_summary text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (registry_code, scheduled_for, check_method)
);

create index if not exists vta_check_queue_work_idx
  on sales_crm.vta_check_queue (queue_status, scheduled_for, priority_score desc);

create table if not exists sales_crm.lead_scoring_criteria (
  criterion_id text primary key,
  label text not null,
  max_points integer not null check (max_points > 0),
  plain_rule text not null,
  strong_signal_note text,
  sort_order integer not null default 100,
  active boolean not null default true,
  updated_at timestamptz not null default now()
);

comment on table sales_crm.lead_scoring_criteria is
  'Owner/operator-visible lead scoring model. Keep wording plain and match the SQL scoring rules.';

insert into sales_crm.lead_scoring_criteria (
  criterion_id,
  label,
  max_points,
  plain_rule,
  strong_signal_note,
  sort_order
) values
  (
    'active_status',
    'Ettevõte on tegutsev',
    15,
    'Registris peab ettevõte olema aktiivne. Kui staatus vajab kontrolli, ei ole see esimene kõne.',
    'Aktiivne ettevõte saab 15 punkti.',
    10
  ),
  (
    'company_age',
    'Ettevõttel on ajalugu',
    25,
    'Vähemalt 10 aastat tegutsenud ettevõte on tavaliselt stabiilsem ja tal on päris protsessid.',
    '10+ aastat annab 25 punkti, 5-9 aastat annab 15 punkti.',
    20
  ),
  (
    'revenue_scale',
    'Müügitulu lubab praktilist projekti',
    35,
    'Kui müügitulu on piisav, on omanikul tõenäolisemalt päris valud ja eelarve.',
    '200 000+ eurot annab 35 punkti, 50 000+ eurot annab 25 punkti.',
    30
  ),
  (
    'vta_left',
    'VTA jääk võib toetust lubada',
    20,
    'Kui vähese tähtsusega abi jääk on suur, on toetusega arutelu lihtsam. Kui jääk puudub või on kontrollimata, vajab see eraldi sammu.',
    '50 000+ eurot jääki annab 20 punkti, 10 000+ eurot annab 12 punkti.',
    40
  ),
  (
    'activity_known',
    'Tegevusala on arusaadav',
    5,
    'Kui tegevusala on nähtav, saab müügikõne konkreetsemaks teha.',
    'Tuvastatud tegevusala annab 5 punkti.',
    50
  )
on conflict (criterion_id) do update
set
  label = excluded.label,
  max_points = excluded.max_points,
  plain_rule = excluded.plain_rule,
  strong_signal_note = excluded.strong_signal_note,
  sort_order = excluded.sort_order,
  active = true,
  updated_at = now();

create or replace view sales_crm.company_lead_universe as
with base as (
  select
    c.registry_code,
    c.name as company_name,
    c.legal_form,
    c.status as company_status,
    c.registered_at,
    case
      when c.registered_at is null then null
      else greatest(0, extract(year from age(current_date, c.registered_at))::integer)
    end as company_age_years,
    c.primary_activity_code,
    c.primary_activity_name,
    c.address_summary,
    r.latest_fiscal_year,
    r.average_revenue_last_two,
    r.latest_employee_count,
    v.de_minimis_left,
    v.checked_at as de_minimis_checked_at,
    p.id as prospect_id,
    p.crm_status,
    p.last_contacted_at,
    p.next_follow_up_at,
    p.owner_name
  from public_registry.rik_companies c
  left join support_assessment.company_revenue_summary r on r.registry_code = c.registry_code
  left join lateral (
    select
      de_minimis_left,
      checked_at
    from support_assessment.rar_de_minimis_snapshots v
    where v.registry_code = c.registry_code
    order by checked_at desc
    limit 1
  ) v on true
  left join lateral (
    select
      id,
      crm_status,
      last_contacted_at,
      next_follow_up_at,
      owner_name
    from sales_crm.prospect_companies p
    where p.registry_code = c.registry_code
    order by created_at desc
    limit 1
  ) p on true
),
scored as (
  select
    b.*,
    case
      when lower(coalesce(b.company_status, '')) in ('registrisse kantud', 'active', 'aktiivne', 'r') then 15
      else 0
    end as active_points,
    case
      when b.company_age_years >= 10 then 25
      when b.company_age_years >= 5 then 15
      else 0
    end as age_points,
    case
      when b.average_revenue_last_two >= 200000 then 35
      when b.average_revenue_last_two >= 50000 then 25
      else 0
    end as revenue_points,
    case
      when b.de_minimis_left >= 50000 then 20
      when b.de_minimis_left >= 10000 then 12
      else 0
    end as vta_points,
    case
      when nullif(b.primary_activity_name, '') is not null then 5
      else 0
    end as activity_points
  from base b
)
select
  s.prospect_id,
  s.registry_code,
  s.company_name,
  s.company_status,
  s.legal_form,
  s.registered_at,
  s.company_age_years,
  s.primary_activity_code,
  s.primary_activity_name,
  s.address_summary,
  s.latest_fiscal_year,
  s.average_revenue_last_two,
  s.latest_employee_count,
  s.de_minimis_left,
  s.de_minimis_checked_at,
  case
    when s.de_minimis_left is null then 'not_checked'
    when s.de_minimis_left >= 50000 then 'high_left'
    when s.de_minimis_left >= 10000 then 'some_left'
    when s.de_minimis_left > 0 then 'low_left'
    else 'used_up'
  end as vta_signal,
  least(100, s.active_points + s.age_points + s.revenue_points + s.vta_points + s.activity_points) as priority_score,
  case
    when least(100, s.active_points + s.age_points + s.revenue_points + s.vta_points + s.activity_points) >= 75 then 'good_first_call'
    when least(100, s.active_points + s.age_points + s.revenue_points + s.vta_points + s.activity_points) >= 50 then 'needs_review'
    else 'weak_fit'
  end as sales_signal,
  array_remove(array[
    case when s.active_points > 0 then 'ettevõte on registris aktiivne' end,
    case when s.age_points = 25 then 'ettevõte on tegutsenud vähemalt 10 aastat' end,
    case when s.age_points = 15 then 'ettevõte on tegutsenud üle 5 aasta' end,
    case when s.revenue_points = 35 then 'müügitulu on tugev' end,
    case when s.revenue_points = 25 then 'müügitulu paistab piisav' end,
    case when s.vta_points > 0 then 'VTA jääk paistab kasutatav' end,
    case when s.de_minimis_left is null then 'VTA vajab kontrolli' end,
    case when s.activity_points > 0 then 'tegevusala on tuvastatav' end
  ], null) as score_reason,
  jsonb_build_array(
    jsonb_build_object('criterion_id', 'active_status', 'label', 'Ettevõte on tegutsev', 'max_points', 15, 'points', s.active_points),
    jsonb_build_object('criterion_id', 'company_age', 'label', 'Ettevõttel on ajalugu', 'max_points', 25, 'points', s.age_points),
    jsonb_build_object('criterion_id', 'revenue_scale', 'label', 'Müügitulu lubab projekti', 'max_points', 35, 'points', s.revenue_points),
    jsonb_build_object('criterion_id', 'vta_left', 'label', 'VTA jääk', 'max_points', 20, 'points', s.vta_points),
    jsonb_build_object('criterion_id', 'activity_known', 'label', 'Tegevusala teada', 'max_points', 5, 'points', s.activity_points)
  ) as score_breakdown,
  case
    when least(100, s.active_points + s.age_points + s.revenue_points + s.vta_points + s.activity_points) >= 75 then
      'Kontrolli VTA jääk ja võta ühendust: ettevõte paistab piisavalt vana ning müügitulu lubab praktilist projekti arutada.'
    when least(100, s.active_points + s.age_points + s.revenue_points + s.vta_points + s.activity_points) >= 50 then
      'Kontrolli puuduvad andmed enne kõnet.'
    else
      'Jäta madalamasse prioriteeti.'
  end as next_action,
  case
    when least(100, s.active_points + s.age_points + s.revenue_points + s.vta_points + s.activity_points) >= 75 then
      'Tere, vaatasin avalike andmete põhjal, et ettevõte on tegutsenud pikalt ja müügitulu järgi võiks olla mõistlik arutada tarkvara, andmete või tööde korrastamise plaani. Kas teil on sel aastal mõni selline mõte?'
    else
      'Tere, kontrollime ettevõtte digitoetuse ja tööde korrastamise võimalust. Kas teil on mõni tarkvara või korduv töö, mille kohta soovite kiiret eelhinnangut?'
  end as recommended_pitch,
  coalesce(s.owner_name, 'Toomas') as owner_name,
  coalesce(s.crm_status, 'not_in_sales') as crm_status,
  s.last_contacted_at,
  s.next_follow_up_at,
  s.prospect_id is not null as is_prospect
from scored s
where coalesce(s.crm_status, 'not_in_sales') not in ('do_not_contact', 'won', 'lost');

comment on view sales_crm.company_lead_universe is
  'All imported public-company facts scored for sales prioritisation. Excludes restricted personal contact fields.';

create or replace view sales_crm.toomas_priority_board as
select
  p.id as prospect_id,
  p.registry_code,
  coalesce(s.name, p.company_name) as company_name,
  coalesce(s.status, p.status) as company_status,
  p.company_age_years,
  coalesce(s.primary_activity_code, p.primary_activity_code) as primary_activity_code,
  coalesce(s.primary_activity_name, p.primary_activity_name) as primary_activity_name,
  coalesce(s.latest_fiscal_year, p.latest_fiscal_year) as latest_fiscal_year,
  coalesce(s.average_revenue_last_two, p.average_revenue_last_two) as average_revenue_last_two,
  coalesce(s.latest_employee_count, p.latest_employee_count) as latest_employee_count,
  coalesce(s.de_minimis_left, p.de_minimis_left) as de_minimis_left,
  coalesce(s.de_minimis_checked_at, p.de_minimis_checked_at) as de_minimis_checked_at,
  case
    when coalesce(s.de_minimis_left, p.de_minimis_left) is null then p.vta_signal
    when coalesce(s.de_minimis_left, p.de_minimis_left) >= 50000 then 'high_left'
    when coalesce(s.de_minimis_left, p.de_minimis_left) >= 10000 then 'some_left'
    when coalesce(s.de_minimis_left, p.de_minimis_left) > 0 then 'low_left'
    else 'used_up'
  end as vta_signal,
  p.priority_score,
  p.sales_signal,
  p.score_reason,
  p.recommended_pitch,
  p.next_action,
  p.owner_name,
  p.crm_status,
  p.last_contacted_at,
  p.next_follow_up_at,
  q.queue_status as vta_queue_status,
  q.scheduled_for as vta_scheduled_for,
  array_remove(array[
    case when p.company_age_years >= 10 then 'vanem toimiv ettevõte' end,
    case when coalesce(s.average_revenue_last_two, p.average_revenue_last_two) >= 50000 then 'müügitulu paistab piisav' end,
    case when coalesce(s.de_minimis_left, p.de_minimis_left) >= 10000 then 'VTA jääk paistab kasutatav' end,
    case when coalesce(s.de_minimis_checked_at, p.de_minimis_checked_at) is null then 'VTA vajab kontrolli' end
  ], null) as why_now
from sales_crm.prospect_companies p
left join lateral (
  select
    name,
    status,
    primary_activity_code,
    primary_activity_name,
    latest_fiscal_year,
    average_revenue_last_two,
    latest_employee_count,
    de_minimis_left,
    de_minimis_checked_at
  from support_assessment.company_support_snapshots s
  where s.registry_code = p.registry_code
  order by
    case when s.preliminary_status = 'can_check_further' then 0 else 1 end,
    s.source_checked_at desc
  limit 1
) s on true
left join lateral (
  select
    queue_status,
    scheduled_for
  from sales_crm.vta_check_queue q
  where q.registry_code = p.registry_code
  order by scheduled_for desc, created_at desc
  limit 1
) q on true
where p.crm_status not in ('do_not_contact', 'won', 'lost');

comment on view sales_crm.toomas_priority_board is
  'Public-company-fact CRM board for Toomas. Excludes restricted personal contact fields.';

create or replace view sales_crm.toomas_call_sheet_export as
select
  prospect_id,
  registry_code,
  company_name,
  company_status,
  company_age_years,
  primary_activity_name,
  average_revenue_last_two,
  latest_employee_count,
  de_minimis_left,
  de_minimis_checked_at,
  vta_signal,
  priority_score,
  sales_signal,
  recommended_pitch,
  next_action,
  owner_name,
  crm_status,
  next_follow_up_at
from sales_crm.toomas_priority_board;

comment on view sales_crm.toomas_call_sheet_export is
  'CSV/export-safe call sheet. Contact people and personal e-mails must be joined only in an authenticated restricted tool.';

create or replace function sales_crm.current_crm_user_allowed()
returns boolean
language sql
stable
security definer
set search_path = sales_crm, public
as $$
  select exists (
    select 1
    from sales_crm.crm_users u
    where lower(u.email) = lower(coalesce(auth.jwt() ->> 'email', ''))
      and u.active is true
  );
$$;

create or replace function sales_crm.current_crm_user_is_admin()
returns boolean
language sql
stable
security definer
set search_path = sales_crm, public
as $$
  select exists (
    select 1
    from sales_crm.crm_users u
    where lower(u.email) = lower(coalesce(auth.jwt() ->> 'email', ''))
      and u.role = 'admin'
      and u.active is true
  );
$$;

create or replace function public.crm_get_current_user()
returns table (
  email text,
  role text,
  active boolean
)
language sql
stable
security definer
set search_path = sales_crm, public
as $$
  select
    u.email,
    u.role,
    u.active
  from sales_crm.crm_users u
  where lower(u.email) = lower(coalesce(auth.jwt() ->> 'email', ''))
    and u.active is true;
$$;

create or replace function public.crm_list_users()
returns table (
  email text,
  role text,
  active boolean,
  created_at timestamptz
)
language sql
stable
security definer
set search_path = sales_crm, public
as $$
  select
    u.email,
    u.role,
    u.active,
    u.created_at
  from sales_crm.crm_users u
  where sales_crm.current_crm_user_is_admin()
  order by u.active desc, u.role asc, u.email asc;
$$;

create or replace function public.crm_get_lead_scoring_criteria()
returns table (
  criterion_id text,
  label text,
  max_points integer,
  plain_rule text,
  strong_signal_note text,
  sort_order integer
)
language sql
stable
security definer
set search_path = sales_crm, public
as $$
  select
    c.criterion_id,
    c.label,
    c.max_points,
    c.plain_rule,
    c.strong_signal_note,
    c.sort_order
  from sales_crm.lead_scoring_criteria c
  where c.active is true
    and sales_crm.current_crm_user_allowed()
  order by c.sort_order asc;
$$;

create or replace function public.crm_get_warehouse_stats()
returns table (
  imported_companies bigint,
  scored_companies bigint,
  strong_leads bigint,
  prospects bigint,
  unchecked_vta bigint
)
language sql
stable
security definer
set search_path = sales_crm, public_registry, support_assessment, public
as $$
  select
    (select count(*) from public_registry.rik_companies) as imported_companies,
    (select count(*) from sales_crm.company_lead_universe) as scored_companies,
    (select count(*) from sales_crm.company_lead_universe where priority_score >= 75) as strong_leads,
    (select count(*) from sales_crm.prospect_companies where crm_status not in ('do_not_contact', 'won', 'lost')) as prospects,
    (select count(*) from sales_crm.company_lead_universe where vta_signal = 'not_checked') as unchecked_vta
  where sales_crm.current_crm_user_allowed();
$$;

create or replace function public.crm_get_company_lead_universe(
  p_limit integer default 500,
  p_min_score integer default 0
)
returns table (
  prospect_id uuid,
  registry_code text,
  company_name text,
  company_status text,
  legal_form text,
  registered_at date,
  company_age_years integer,
  primary_activity_code text,
  primary_activity_name text,
  address_summary text,
  latest_fiscal_year integer,
  average_revenue_last_two numeric,
  latest_employee_count integer,
  de_minimis_left numeric,
  de_minimis_checked_at timestamptz,
  vta_signal text,
  priority_score integer,
  sales_signal text,
  score_reason text[],
  score_breakdown jsonb,
  recommended_pitch text,
  next_action text,
  owner_name text,
  crm_status text,
  last_contacted_at timestamptz,
  next_follow_up_at timestamptz,
  is_prospect boolean
)
language sql
stable
security definer
set search_path = sales_crm, public_registry, support_assessment, public
as $$
  select
    u.prospect_id,
    u.registry_code,
    u.company_name,
    u.company_status,
    u.legal_form,
    u.registered_at,
    u.company_age_years,
    u.primary_activity_code,
    u.primary_activity_name,
    u.address_summary,
    u.latest_fiscal_year,
    u.average_revenue_last_two,
    u.latest_employee_count,
    u.de_minimis_left,
    u.de_minimis_checked_at,
    u.vta_signal,
    u.priority_score,
    u.sales_signal,
    u.score_reason,
    u.score_breakdown,
    u.recommended_pitch,
    u.next_action,
    u.owner_name,
    u.crm_status,
    u.last_contacted_at,
    u.next_follow_up_at,
    u.is_prospect
  from sales_crm.company_lead_universe u
  where sales_crm.current_crm_user_allowed()
    and u.priority_score >= greatest(0, least(100, coalesce(p_min_score, 0)))
  order by
    u.is_prospect desc,
    u.priority_score desc,
    u.company_age_years desc nulls last,
    u.average_revenue_last_two desc nulls last,
    u.company_name asc
  limit greatest(1, least(1000, coalesce(p_limit, 500)));
$$;

create or replace function public.crm_get_toomas_priority_board()
returns table (
  prospect_id uuid,
  registry_code text,
  company_name text,
  company_status text,
  company_age_years integer,
  primary_activity_code text,
  primary_activity_name text,
  latest_fiscal_year integer,
  average_revenue_last_two numeric,
  latest_employee_count integer,
  de_minimis_left numeric,
  de_minimis_checked_at timestamptz,
  vta_signal text,
  priority_score integer,
  sales_signal text,
  score_reason text[],
  recommended_pitch text,
  next_action text,
  owner_name text,
  crm_status text,
  last_contacted_at timestamptz,
  next_follow_up_at timestamptz,
  vta_queue_status text,
  vta_scheduled_for date,
  why_now text[]
)
language sql
stable
security definer
set search_path = sales_crm, support_assessment, public
as $$
  select
    b.prospect_id,
    b.registry_code,
    b.company_name,
    b.company_status,
    b.company_age_years,
    b.primary_activity_code,
    b.primary_activity_name,
    b.latest_fiscal_year,
    b.average_revenue_last_two,
    b.latest_employee_count,
    b.de_minimis_left,
    b.de_minimis_checked_at,
    b.vta_signal,
    b.priority_score,
    b.sales_signal,
    b.score_reason,
    b.recommended_pitch,
    b.next_action,
    b.owner_name,
    b.crm_status,
    b.last_contacted_at,
    b.next_follow_up_at,
    b.vta_queue_status,
    b.vta_scheduled_for,
    b.why_now
  from sales_crm.toomas_priority_board b
  where sales_crm.current_crm_user_allowed()
  order by
    case b.crm_status
      when 'call_next' then 0
      when 'new' then 1
      when 'to_review' then 2
      else 3
    end,
    b.priority_score desc,
    b.company_age_years desc nulls last,
    b.company_name asc;
$$;

create or replace function public.crm_promote_company_to_prospect(p_registry_code text)
returns uuid
language plpgsql
security definer
set search_path = sales_crm, public_registry, support_assessment, public
as $$
declare
  v_registry_code text;
  v_company sales_crm.company_lead_universe%rowtype;
  v_prospect_id uuid;
begin
  if not sales_crm.current_crm_user_allowed() then
    raise exception 'CRM access denied';
  end if;

  v_registry_code = regexp_replace(coalesce(p_registry_code, ''), '\D', '', 'g');

  if v_registry_code !~ '^[0-9]{8}$' then
    raise exception 'Invalid registry code';
  end if;

  select *
  into v_company
  from sales_crm.company_lead_universe
  where registry_code = v_registry_code
  limit 1;

  if not found then
    raise exception 'Company not found in warehouse';
  end if;

  select id
  into v_prospect_id
  from sales_crm.prospect_companies
  where registry_code = v_registry_code
    and crm_status not in ('do_not_contact', 'won', 'lost')
  order by created_at desc
  limit 1;

  if v_prospect_id is not null then
    return v_prospect_id;
  end if;

  insert into sales_crm.prospect_companies (
    registry_code,
    company_name,
    legal_form,
    status,
    registered_at,
    company_age_years,
    primary_activity_code,
    primary_activity_name,
    address_summary,
    average_revenue_last_two,
    latest_employee_count,
    latest_fiscal_year,
    de_minimis_left,
    de_minimis_checked_at,
    vta_signal,
    sales_signal,
    priority_score,
    score_reason,
    recommended_pitch,
    next_action,
    crm_status,
    source_system,
    source_observed_at
  ) values (
    v_company.registry_code,
    v_company.company_name,
    v_company.legal_form,
    v_company.company_status,
    v_company.registered_at,
    v_company.company_age_years,
    v_company.primary_activity_code,
    v_company.primary_activity_name,
    v_company.address_summary,
    v_company.average_revenue_last_two,
    v_company.latest_employee_count,
    v_company.latest_fiscal_year,
    v_company.de_minimis_left,
    v_company.de_minimis_checked_at,
    v_company.vta_signal,
    v_company.sales_signal,
    v_company.priority_score,
    v_company.score_reason,
    v_company.recommended_pitch,
    v_company.next_action,
    case when v_company.priority_score >= 75 then 'call_next' else 'to_review' end,
    'rik_warehouse',
    now()
  )
  returning id into v_prospect_id;

  insert into sales_crm.prospect_activities (
    prospect_company_id,
    activity_type,
    activity_note,
    created_by
  ) values (
    v_prospect_id,
    'qualification',
    'Lisatud CRM-i andmebaasi skoori põhjal.',
    lower(coalesce(auth.jwt() ->> 'email', 'unknown'))
  );

  return v_prospect_id;
end;
$$;

create or replace function public.crm_upsert_user(
  p_email text,
  p_role text default 'sales',
  p_active boolean default true
)
returns table (
  email text,
  role text,
  active boolean,
  created_at timestamptz
)
language plpgsql
security definer
set search_path = sales_crm, public
as $$
declare
  v_email text;
begin
  if not sales_crm.current_crm_user_is_admin() then
    raise exception 'CRM admin access denied';
  end if;

  v_email = coalesce(lower(trim(p_email)), '');

  if v_email = '' or v_email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' then
    raise exception 'Invalid e-mail';
  end if;

  if p_role not in ('sales', 'admin') then
    raise exception 'Invalid CRM role: %', p_role;
  end if;

  insert into sales_crm.crm_users (email, role, active)
  values (v_email, p_role, coalesce(p_active, true))
  on conflict (email) do update
  set
    role = excluded.role,
    active = excluded.active
  returning crm_users.email, crm_users.role, crm_users.active, crm_users.created_at
  into email, role, active, created_at;

  return next;
end;
$$;

create or replace function public.crm_set_user_active(
  p_email text,
  p_active boolean
)
returns boolean
language plpgsql
security definer
set search_path = sales_crm, public
as $$
declare
  v_email text;
begin
  if not sales_crm.current_crm_user_is_admin() then
    raise exception 'CRM admin access denied';
  end if;

  v_email = coalesce(lower(trim(p_email)), '');

  if v_email = lower(coalesce(auth.jwt() ->> 'email', '')) and p_active is false then
    raise exception 'You cannot deactivate your own CRM user';
  end if;

  update sales_crm.crm_users
  set active = p_active
  where lower(email) = v_email;

  if not found then
    raise exception 'CRM user not found';
  end if;

  return true;
end;
$$;

create or replace function public.crm_update_prospect_status(
  p_prospect_id uuid,
  p_crm_status text,
  p_note text default null,
  p_next_follow_up_at timestamptz default null
)
returns boolean
language plpgsql
security definer
set search_path = sales_crm, public
as $$
declare
  v_activity_type text;
begin
  if not sales_crm.current_crm_user_allowed() then
    raise exception 'CRM access denied';
  end if;

  if p_crm_status not in (
    'new',
    'to_review',
    'call_next',
    'called',
    'not_relevant',
    'meeting_booked',
    'proposal_sent',
    'won',
    'lost',
    'do_not_contact'
  ) then
    raise exception 'Invalid CRM status: %', p_crm_status;
  end if;

  update sales_crm.prospect_companies
  set
    crm_status = p_crm_status,
    next_follow_up_at = p_next_follow_up_at,
    last_contacted_at = case
      when p_crm_status in ('called', 'meeting_booked', 'proposal_sent', 'won', 'lost', 'do_not_contact') then now()
      else last_contacted_at
    end,
    updated_at = now()
  where id = p_prospect_id;

  if not found then
    raise exception 'Prospect not found';
  end if;

  v_activity_type = case
    when p_crm_status = 'called' then 'call_connected'
    when p_crm_status = 'meeting_booked' then 'meeting_booked'
    when p_crm_status = 'do_not_contact' then 'do_not_contact'
    else 'note'
  end;

  insert into sales_crm.prospect_activities (
    prospect_company_id,
    activity_type,
    activity_note,
    created_by
  ) values (
    p_prospect_id,
    v_activity_type,
    nullif(p_note, ''),
    lower(coalesce(auth.jwt() ->> 'email', 'unknown'))
  );

  return true;
end;
$$;

grant execute on function public.crm_get_toomas_priority_board() to authenticated;
grant execute on function public.crm_update_prospect_status(uuid, text, text, timestamptz) to authenticated;
grant execute on function public.crm_get_current_user() to authenticated;
grant execute on function public.crm_list_users() to authenticated;
grant execute on function public.crm_upsert_user(text, text, boolean) to authenticated;
grant execute on function public.crm_set_user_active(text, boolean) to authenticated;
grant execute on function public.crm_get_lead_scoring_criteria() to authenticated;
grant execute on function public.crm_get_warehouse_stats() to authenticated;
grant execute on function public.crm_get_company_lead_universe(integer, integer) to authenticated;
grant execute on function public.crm_promote_company_to_prospect(text) to authenticated;

alter table sales_crm.prospect_lists enable row level security;
alter table sales_crm.lead_scoring_criteria enable row level security;
alter table sales_crm.crm_users enable row level security;
alter table sales_crm.prospect_companies enable row level security;
alter table sales_crm.prospect_contacts_restricted enable row level security;
alter table sales_crm.prospect_activities enable row level security;
alter table sales_crm.vta_check_queue enable row level security;
