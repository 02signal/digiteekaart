# Lead Quality Engine

Internal foundation for finding useful B2B sales signals for Digiteekaart.ee, digitaliseerimine.ee and related 02Signal sales pages.

This is not a public website feature. It is the first warehouse and CRM layer for Toomas so he can see which companies are worth calling first.

## What Toomas Should See

The first useful view is simple:

- company name and registry code;
- whether the company is active;
- company age;
- main activity;
- latest known revenue and employee signal;
- VTA check state: not checked, high left, some left, low left, used up;
- priority score from 0 to 100;
- why the lead is interesting;
- suggested first sentence for the call;
- CRM status: new, call next, called, meeting booked, proposal sent, won, lost, do not contact.

The owner/contact-person layer is separate and restricted. It must not appear in public pages, `llms.txt`, static JSON files or client-side API responses.

## Why This Is Valuable

For Toomas the strongest first signal is:

1. company is old enough to have established habits and legacy work;
2. company still operates and has enough revenue to act;
3. VTA is unused or has a large remaining balance;
4. the likely offer is practical: digiteekaart, RTE/software support, automation or a small paid assessment;
5. the next action is obvious: call, ask 2-3 simple questions, offer a small safe step.

This avoids random cold calling. The call starts from a concrete business reason.

## Data Flow

1. RIK bulk/open data loads public company facts into `public_registry`.
2. Support and VTA snapshots are stored in `support_assessment`.
3. Candidate companies are copied or projected into `sales_crm.prospect_companies`.
4. `sales_crm.vta_check_queue` schedules 20-30 VTA checks per day while official RAR/X-tee integration is pending.
5. `sales_crm.toomas_priority_board` gives the working view.
6. `sales_crm.prospect_activities` stores calls, notes and follow-ups.
7. `sales_crm.prospect_contacts_restricted` stores people/contact data only for authenticated internal use.

## MVP Interface Options

Fastest safe path:

1. Run SQL migrations in Supabase.
2. Show `sales_crm.toomas_priority_board` in Supabase table editor or export it to a Google Sheet for Toomas.
3. Use n8n once per day to:
   - pick 20-30 queued companies;
   - run the VTA check;
   - store a dated snapshot;
   - send a short Telegram summary to Toomas.

Better next step:

Build a small authenticated internal CRM page:

- Supabase Auth magic link for Toomas;
- table with search, filters and sorting;
- one company detail view;
- buttons: call next, called, meeting booked, not relevant, do not contact;
- no public access and no indexing.

Do not build this inside the public static landing page.

## CRM Subdomain

The repository includes a first internal CRM page at:

```text
/crm/
```

Vercel rewrites `https://crm.digiteekaart.ee/` to that page through `vercel.json`.

The page uses Supabase magic-link login and public RPC wrappers:

- `public.crm_get_toomas_priority_board()`
- `public.crm_get_company_lead_universe(...)`
- `public.crm_get_lead_scoring_criteria()`
- `public.crm_get_warehouse_stats()`
- `public.crm_promote_company_to_prospect(...)`
- `public.crm_update_prospect_status(...)`
- `public.crm_get_current_user()`
- `public.crm_list_users()`
- `public.crm_upsert_user(...)`
- `public.crm_set_user_active(...)`

It does not query restricted contact tables and it has `noindex,nofollow`.

Admins can add and deactivate CRM users from the interface. Sales users can work with the lead board but cannot manage users.

## Lead Score Shown in CRM

The CRM shows the scoring model directly so Toomas can see why a company is a strong signal.

| Criterion | Points | Plain rule |
| --- | ---: | --- |
| Active company | 15 | Company is active in the register. |
| Company age | 25 | 10+ years gives full points; 5-9 years gives partial points. |
| Revenue scale | 35 | 200,000+ EUR revenue gives full points; 50,000+ EUR gives partial points. |
| VTA left | 20 | 50,000+ EUR remaining VTA gives full points; 10,000+ gives partial points. |
| Activity known | 5 | Known activity makes the sales conversation more concrete. |

For the first RIK public-data import, VTA is not checked yet. A company can still reach 75 points from active status, age and revenue. The CRM marks this as `VTA kontrollimata`, which means: check VTA before promising a support route.

The current CRM views are:

- **Tugev signaal**: score 75+.
- **Kõik andmebaasis**: every imported public-company row.
- **Müüki lisatud**: companies already promoted into Toomas' working list.

Use `Lisa müüki` to promote a database-only company into the sales workflow.

## Required Setup for crm.digiteekaart.ee

1. Apply the SQL:

```bash
supabase db push
```

or paste `sql/001_sales_quality_engine.sql` into Supabase SQL Editor.

2. Add the CRM user:

```sql
insert into sales_crm.crm_users (email, role, active)
values ('toomas@example.ee', 'sales', true)
on conflict (email) do update
set active = excluded.active,
    role = excluded.role;
```

Use Toomas' real work e-mail.

`ak@ettevotluskeskus.ee` is seeded by the SQL as the first `admin` user. After that, new users can be added from the CRM interface.

3. Check Vercel environment variables:

```text
PUBLIC_SUPABASE_URL=https://miwpctshbcmkpwvdokne.supabase.co
PUBLIC_SUPABASE_ANON_KEY=...
```

`PUBLIC_SUPABASE_ANON_KEY` is public by design, but it must still come from Supabase Project Settings. Do not use the service-role key in Vercel.

4. In Supabase Auth URL settings, allow:

```text
https://crm.digiteekaart.ee
https://crm.digiteekaart.ee/
```

5. In Vercel, add domain:

```text
crm.digiteekaart.ee
```

6. In Cloudflare DNS, add:

```text
Type: CNAME
Name: crm
Target: cname.vercel-dns.com
Proxy: DNS only
```

7. Open `https://crm.digiteekaart.ee/`, enter the allowed e-mail and use the magic link.

If login works but the table is empty, either the user is not in `sales_crm.crm_users` or no prospects have been loaded yet.

## VTA Check Rules

VTA is a dated signal, not a permanent company fact.

Use the check result like this:

| Signal | Meaning for sales |
| --- | --- |
| `high_left` | Strong reason to contact: support capacity appears available. |
| `some_left` | Still worth contacting if the company has a clear project. |
| `low_left` | Be careful: support may still be possible but needs review. |
| `used_up` | Do not sell support-first; discuss non-support paid work. |
| `not_checked` | Put in queue before Toomas spends time on it. |

Before a paid recommendation or application-preparation proposal, refresh VTA again.

## Privacy and Legal Guardrails

- Keep company facts and lead score separate from personal contact data.
- Store board members, beneficial owners, e-mails and phone numbers only in `sales_crm.prospect_contacts_restricted`.
- Add a written purpose, retention rule and access control before using the restricted contact table in a live tool.
- Keep opt-out and `do_not_contact` handling.
- Do not upload personal e-mails from registry data into advertising platforms.
- Public pages may mention that we use public registry/support data for pre-assessment, but must not expose raw person data.

## SQL Objects

`sql/001_sales_quality_engine.sql` adds:

- `sales_crm.prospect_lists`
- `sales_crm.prospect_companies`
- `sales_crm.prospect_contacts_restricted`
- `sales_crm.prospect_activities`
- `sales_crm.vta_check_queue`
- `sales_crm.toomas_priority_board`
- `sales_crm.toomas_call_sheet_export`

The two Toomas views exclude restricted contact fields.

## Smoke Test

Run:

```bash
node infra/lead-quality-engine/scripts/build-toomas-prospect-fixture.mjs
```

Expected outcome: a public-safe prospect score and call signal are printed for the fixture company.

## Next Build Slice

1. Create an n8n daily VTA queue workflow with a hard limit of 20-30 checks per day.
2. Send Toomas a daily Telegram summary:
   - new high-priority companies;
   - VTA checked and high left;
   - calls due today;
   - companies to avoid.

## Official Source Notes

- RIK/e-Business Register open data is the preferred source for bulk public company facts.
- RIK contract/API is better for refreshing one company before a live assessment.
- RAR/VTA checks should be stored as timestamped snapshots and refreshed before paid advice.
