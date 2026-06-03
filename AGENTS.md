# Agent Entry Point

Read `CLAUDE.md` first. It is the single source of truth for this repository.

Before planning or finishing work, also check `BACKLOG.md`.

Do not deploy, rename domains, change analytics IDs, or alter lead-routing behavior unless the user explicitly asks for it.

## CRM & Sales View Architecture

When modifying the internal CRM (`src/pages/crm/index.astro` and `infra/lead-quality-engine/sql/*`):
1. **Focus Mode First:** The default view must remain "Focus Mode" (one card at a time). Do not revert to table/list views as the default.
2. **Cognitive Load:** Keep the UI radically simple. Emphasize the "Next Best Action" and immediate status updates.
3. **Nomenclature:** Use role-based, neutral naming (e.g., `sales_priority_board`, "sales user"). Do not use specific human names (like "Toomas") in code, comments, or UI texts.
