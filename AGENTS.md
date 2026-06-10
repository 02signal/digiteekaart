# Agent Entry Point

Read `CLAUDE.md` first. It is the single source of truth for this repository.

Before planning or finishing work, also check `BACKLOG.md`.

Do not deploy, rename domains, change analytics IDs, or alter lead-routing behavior unless the user explicitly asks for it.

## CRM & Sales View Architecture

**FROZEN FOR NEW FEATURES (2026-06-10):** the internal CRM is being consolidated into the AMOS/REV stack (see `CLAUDE.md` "Internal CRM Rules" consolidation note). Only keep-the-lights-on fixes here; new sales/CRM capability goes to the 02S-AMOS repo.

When modifying the internal CRM (`src/pages/crm/index.astro` and `infra/lead-quality-engine/sql/*`):
1. **Master-Detail Layout:** The default view is a 3-pane Master-Detail layout (Filters -> List -> Detail Worksheet). Do not revert to a single-card "Focus Mode" or a wide table/list view, as the 3-pane layout provides necessary context without overwhelming the user.
2. **Cognitive Load & UX:** Keep the UI radically simple. Emphasize the "Next Best Action". Use neutral "outline" styles for action buttons (e.g., "Märgi: Helistatud") to avoid the psychological impression that the action is already completed.
3. **Filtering:** Support dynamic text and number filters, notably the "Tegevusala (EMTAK)" filter which restricts VTA eligibility based on primary activity code (01, 02, 03 are restricted).
4. **Nomenclature:** Use role-based, neutral naming (e.g., `sales_priority_board`, "sales user"). Do not use specific human names (like "Toomas") in code, comments, or UI texts.
