# Agent Entry Point

<!-- AMOS-TÖÖKORD:ALGUS (levitatud allikast – ära muuda siin) -->
## AMOS-i ühine töökord (omanik 16.10.2026)

Kehtib igale sessioonile ja agendile (Claude Code, Codex, pilv) selles repos.

- **Kohustus = GitHub issue.** Selle repo töö issue on selles repos. Sõnum ilma issue'ta ununeb.
- **Sildid:** `ala:<ala>` (üks), `olek:töös` / `olek:blokeeritud`, `omanik` (vajab omaniku otsust), `teise-ala`, `prio:kõrge`. Issue keha: `Väärtus:` (konversioon / õppija edu / CS aeg) ja `Valmis, kui:`.
- **Alustades** vaata oma ala järjekorda ja võta suurima väärtusega asi, mitte kõige uuem sõnum. WIP ≤ 5 `olek:töös`; GO + pakett valmis ja ootab ainult live'i akent → `olek:ootab-akent` (ei loe WIP-i). Sulge ainult tõendiga (PR, readback, link).
- **Sõnumid ainult üleandmiseks**, alati issue lingiga.
- **Andmed:** saladusi (paroole, võtmeid, tokeneid) ei kirjutata kuhugi. Selle repo issue'desse, PR-idesse ja commit'idesse isikuandmeid ei panda.
- **Muudatus läheb sisse PR-i ja sõltumatu ülevaatusega** (autor ≠ kontrollija).
<!-- AMOS-TÖÖKORD:LÕPP -->

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
