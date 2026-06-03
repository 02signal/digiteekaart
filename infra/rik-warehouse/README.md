# RIK Warehouse Foundation

This folder defines the first reusable data foundation for Digiteekaart.ee and future 02Signal sales tools.

## Goal

Build one shared operating memory for Estonian company pre-assessments:

1. load bounded RIK / e-Business Register source data into our own PostgreSQL database;
2. normalize company facts that are useful across projects;
3. combine them with support-program rules;
4. expose simple views for owner-facing tools;
5. keep raw public source data separate from owner-facing product views.

## Source Strategy

Use two RIK data paths for different jobs:

- **Bulk dataset path:** daily public/open data files are the right source for loading the whole company dataset into our database.
- **Autocomplete path:** RIK public autocomplete helps an owner find the right company by name before they know or type the registry code.
- **API path:** after the RIK contract is active, use API calls for exact company lookup and refreshing a specific registry code before a lead result is shown.

Do not use the API as a full-dataset crawler. RIK documents the XML API as real-time access with a contract, a 50,000-request daily limit, and one concurrent request per contract partner. Large initial loads should use downloadable open-data files.

## Source Archive Strategy

We can store public/API-available source data, but it must live in a separate archive layer:

- **Source archive:** stores the public source record, source system, record key, checksum and observation time. This is useful for later analytics, reconciliation and faster internal review.
- **Normalized product layer:** stores only the business facts the site and reports need: company status, revenue facts, likely support path, VTA snapshot and missing checks.
- **Restricted personal-data layer:** if public source data contains people-related fields, for example board members or beneficial owners, keep them out of owner-facing views unless there is a written purpose and access control.

This lets us build a useful company database without turning raw registry payloads into public-facing truth.

## VTA / RAR Strategy

VTA ehk vähese tähtsusega abi is a time-sensitive support eligibility check. Store it as a dated snapshot:

- registry code;
- checked company name;
- used amount;
- limit and remaining amount;
- source system and check timestamp;
- optional raw source archive reference.

Do not treat an old VTA snapshot as final truth. Before sending a paid recommendation, proposal or application-preparation decision, refresh the company snapshot.

## Layers

| Layer | Purpose |
| --- | --- |
| `source_archive.public_source_records` | Raw public/API source records with checksum, source and observation metadata. |
| `rik_import_batches` | What file/API batch was loaded, when, and with what checksum. |
| `rik_companies` | Current company profile: registry code, name, status, legal form, activity code. |
| `rik_annual_reports` | Revenue and reporting facts by year. |
| `rar_de_minimis_snapshots` | Latest known VTA/RAR check by company, stored with timestamp. |
| `mta_tax_debt_snapshots` | Latest known public tax-debt check by company, stored with timestamp. |
| `support_program_rules` | Bounded funding rules used for pre-assessment. |
| `company_support_snapshots` | Queryable owner-facing pre-assessment view. |
| `support_preassessment_events` | Lead-time assessment events for funnel analysis and follow-up. |

## Sales / Lead Quality Layer

The next internal layer lives in `../lead-quality-engine/`.

It is for the sales workflow, not for the public landing page:

- `sales_crm.prospect_companies` stores candidate companies and their priority score;
- `sales_crm.vta_check_queue` schedules low-volume VTA checks before sales calls, starting from older companies with more employees;
- `sales_crm.toomas_priority_board` shows the public-safe call-priority board;
- `sales_crm.prospect_contacts_restricted` stores owner/board/contact data only behind access control.

Keep the public funding pre-assessment and the internal sales CRM separate. A company can be visible in the internal priority board without exposing personal contact data in the public site.

## First Public-Data Sales Import

The first bounded import for `crm.digiteekaart.ee` is generated from RIK downloadable public CSV ZIP files:

```bash
node infra/rik-warehouse/scripts/build-initial-sales-prospect-sql.mjs --limit 75 --warehouse-limit 250
```

Default source files are expected under `/private/tmp/digiteekaart-rik/`:

- `lihtandmed.csv.zip`
- `aruanded-yld.zip`
- `aruanded2024.zip`

The generated SQL is written to:

```text
/private/tmp/digiteekaart-rik/initial-sales-prospects.sql
```

Default filters:

- warehouse sample: active OÜ/AS, 5+ years old, 2024 revenue 50,000-10,000,000 EUR, max 500 employees when employee count is known;
- sales prospect list: active OÜ/AS, 10+ years old, 2024 revenue 200,000-5,000,000 EUR, max 250 employees when employee count is known;
- older companies and companies with more employees are sorted ahead because they are more likely to have manual work, old software and real time-loss pain;
- no personal contacts, board members, e-mails or phone numbers are imported;
- VTA is marked `not_checked` until a separate RAR/VTA check is stored.

Apply the generated SQL only after the registry foundation and lead quality SQL have been applied:

```bash
supabase db query --workdir supabase --linked --file /private/tmp/digiteekaart-rik/initial-sales-prospects.sql
```

## Privacy Rule

For the MVP we do **not** expose board-member names, beneficial owners, personal codes, raw reports, raw API payloads, or signed/source URLs in product tables or owner-facing views.

Raw public source records may be stored in the source archive for internal analytics and reconciliation. If a source record contains people-related data, it must be classified and kept out of public/product views unless there is a written purpose, retention rule, and access control.

## MVP Flow

1. Import RIK companies and latest annual-report revenue facts.
2. Upsert support rules from `public/funding-programs.json`.
3. Store VTA/RAR and public tax-debt checks as dated snapshots when queried.
4. Refresh `company_support_snapshots`.
5. The `rik-company-lookup` Supabase Edge Function can refresh one registry code through the RIK simple-data API without exposing credentials or raw payloads.
6. The same Edge Function also proxies bounded company-name autocomplete so the browser does not depend on raw RIK payload shape.
7. The web tool can query by registry code:
   - company found / not found;
   - active / risky status;
   - average revenue;
   - latest VTA snapshot and check date;
   - latest tax-debt snapshot and check date;
   - likely support programs;
   - missing checks.
8. User confirms e-mail and consent before detailed report is generated or saved as a lead.

## Next Implementation Steps

1. Add Supabase migration from `sql/001_business_registry_foundation.sql`.
2. Set RIK API credentials as environment secrets:
   - `RIK_API_USERNAME`
   - `RIK_API_PASSWORD`
   - optional `RIK_API_ENDPOINT` for test/prod switching.
   - `ALLOWED_ORIGINS` with public site origins such as `https://digiteekaart.ee,https://www.digiteekaart.ee`.
     Without this, the Edge Function can answer server-side smoke tests but the browser form may fail CORS.
3. Build a batch loader for the RIK bulk files once the exact file format is selected.
4. Extend `rik-company-lookup` to store a source archive record and normalized company snapshot.
5. Add a public-safe server endpoint:
   - input: registry code;
   - output: bounded company support snapshot;
   - no raw RIK payload.
6. Add e-mail verification before showing a detailed report.
7. Store confirmed leads and assessment results in `support_preassessment_events`.

## Smoke Test

Run:

```bash
node infra/rik-warehouse/scripts/score-fixture.mjs
```

Expected outcome: the fixture company is classified against the support-program rules and prints the most likely first route.

After RIK credentials are available locally, run:

```bash
RIK_API_USERNAME=... RIK_API_PASSWORD=... RIK_REGISTRY_CODE=14127891 node infra/rik-warehouse/scripts/rik-lihtandmed-smoke.mjs
```

The script prints a small redacted JSON summary. It must not print the password or store source payloads.
