# Sales-Site Backlog

## Current Priority

- Keep all public wording simple enough for a 65+ pragmatic owner.
- Show money, time saved, and payback wherever it helps the decision.
- Route funding and support questions to `digiteekaart.ee`.
- Keep every conversion path measurable in GA4.

## Automatiseerimine.ee

- Improve the repeated-work calculator with clearer examples by business type.
- Add one small case example: "Excelist teavituseni" with rough before/after numbers.
- Add a local lead form later if the current 02Signal quick-check route loses intent.

## Digitaliseerimine.ee

- Add more examples where old software does not need to be replaced immediately.
- Expand the manual-work cost calculator with an optional "errors per month" field.
- Add a short "tasuvuse näide" section near pricing.

## Digiteekaart.ee

- Done: first on-page funding filter shows likely route, possible support, own contribution logic and missing checks before consultant contact.
- Done: `funding-programs.json` exposes the bounded support-rule register for agents and future integrations.
- Done: RIK warehouse foundation added under `infra/rik-warehouse/` with PostgreSQL schema, fixture and smoke test.
- Done: privacy wording now covers public registry/RAR/MTA data use for support pre-assessment.
- Done: warehouse foundation now separates raw public source archive from owner-facing product views and stores dated VTA/tax-debt snapshots.
- Done: Supabase Edge Function `rik-company-lookup` deployed and smoke-tested against RIK simple data API for Ettevõtluskeskus OÜ.
- Done: homepage registry-code field now runs live RIK lookup, shows company status on-page and sends bounded RIK facts with the lead.
- Done: homepage company-name autocomplete lets owners start by typing the company name, select the right company and auto-fill the registry code before the RIK check.
- Done: sample digitalisation roadmap page added to show owners what a practical roadmap should contain and why it can be useful.
- Done: internal lead quality engine foundation added for the sales team: prospect scoring, public-safe priority board, VTA check queue and restricted contact layer.
- Done: first internal CRM page added for `crm.digiteekaart.ee` with Supabase magic-link login, public-safe priority board, status update actions and admin-managed CRM users.
- Done: CRM now shows the full imported company universe, strong-signal leads, scoring criteria/weights, warehouse counts and a `Lisa müüki` action for database-only companies.
- Done: first bounded RIK public CSV import loaded 250 company rows and 75 strong-signal sales prospects into Supabase; no personal contacts were imported.
- Done: CRM sales view uses a 3-pane Master-Detail layout, natural language activity notes, star-bookmarking, and an on-demand scoring breakdown UI.
- Done: lead scoring now prioritises older companies, companies with 500+ employees and single-member boards; CRM has dynamic UI filters for employee count, board size, age, mobile phone presence, and EMTAK industry.
- Done: VTA check logic automatically restricts funding for primary EMTAK sectors starting with 01, 02, or 03.
- Done: RIK warehouse importer extended to download and parse `isikud.csv` and `sidevahendid.csv`, extracting board sizes, calculating oldest board member ages via Estonian personal ID codes, and matching official mobile numbers.
- Done: CRM can batch-add the next 10 strongest unchecked firms to the VTA queue.
- Done: VTA worker RPC foundation added so AMOS/n8n-ops can claim small batches, store dated RAR/VTA snapshots and update CRM cards after a bounded lookup result.
- Consolidation (2026-06-10): the internal CRM and sales warehouse are moving to the AMOS/REV stack (02S-AMOS repo, task board `agent-prompts/2026-06-10-rik-beneficial-owners-and-rev-crm-task-board.md`, Track B). This repo keeps only the public pre-assessment site and a thin Supabase cache. See `CLAUDE.md` "Internal CRM Rules".
- Superseded by AMOS (do not build here): RAR/VTA adapter wiring and supervised batches (AMOS n8n-ops owns the worker; queue location is owner decision B4); multi-year annual-report import and revenue trends (AMOS warehouse); bulk avaandmed importer and single-code API refresh (AMOS restricted person-data zone); adding sales users / magic-link hardening (auth moves to Authentik with rev-web).
- Done (2026-06-10): homepage form reordered to value-first — step 1 company, step 2 funding filter with instant answer, step 3 contact for the verified answer; GA4 funnel split cleanly (`tool_start` on filter touch, `tool_completed` on result, `lead_form_start` only on contact-section touch).
- Done (2026-06-10): new `/avatud-toetused/` page shows the live status of all four EIS rounds with checked-date, budget-remaining facts and plain-language own-contribution example; round status fields added to `supportPrograms.ts` and `funding-programs.json`; linked from nav, footer and llms.txt.
- Done (2026-06-10): VTA, "liidestus" and the bare "RTE" nav label are now explained in plain language at first use on every public page.
- Next (recurring): re-check EIS round status and budget-remaining figures (digital roadmap ~183k €, RTE automation ~573k € as of 2026-06-10) and refresh `/avatud-toetused/`, `supportPrograms.ts`, `funding-programs.json` and `llms.txt` roughly weekly — budgets drain and the roadmap measure may close.
- Next (still this repo, public site): add email verification before showing a more detailed generated report.
- After Google Ads data arrives, refine the result/CTA section around phone calls and owner-level next steps.
- Keep official funding facts checked against official sources before publishing.
- Sunset (Track B6, sequenced — do not start early): after Twenty + rev-web worklist are live and the one-time restricted-contacts export to the AMOS restricted zone is verified, freeze `/crm` to read-only, then remove it and drop the unused `sales_crm` objects.

## Teekaart.ee

- Improve the route selector with a stronger final CTA per route.
- Add a one-page example of "omaniku teekaart" with practical next-step pricing.
- Cross-link route results to the right microsite with UTM parameters.
