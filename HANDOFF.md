# bot2bot / webagent — Handoff (living doc)

Purpose: any Claude session (or human) picking this project up cold should be able to read
this one file and know exactly what's going on — no need to replay `history/conversation.jsonl`
from scratch. **Update this file whenever a major thread wraps up**, don't just rely on chat memory.

Last updated: 2026-07-11T17:30Z by grok (Lead) — **WEBAGENT-ONLY**

## What this project is

AI-to-AI orchestration system (`bot2bot/`) driving a multi-brain review/battleroyale system
(`webagent/`). Multiple AI "brains" (chatgpt, deepseek, kimi, gemini, qwen, zai, mistral,
grok as desktop agent, claude as desktop agent/reviewer) collaborate on code review and,
currently, on selecting a **moderator/leader** for the system via calibrated blind peer-review.

## Current state (as of this update)

- **PROPOSED_DIFF_021 (Leader/Moderator Calibration)**: Parts A, B, C(code), D, E all
  APPROVED and APPLIED. 18 tests passing.
- **Live calibration run `live021r2`**: **COMPLETE** (70/70 pairs, `status: complete`).
  Rankings posted to `bot2bot/inbox/claude.txt` (message `48c35608`, indicative metrics).
  Top scorers with sufficient n: **chatgpt** and **qwen** (73.3% weighted, n=10 each).
  **zai** ranked #1 but only n=2 (8 INVALID) — not a reliable basis. INVALID counts:
  zai=8, mistral=4, gemini=1.
  - Prior run crashed at MC-004/mistral; retry succeeded. `run_leader_calibration.py` now
    catches all exceptions per-pair, checkpoints after every pair, posts via `-BodyPath`
    (fixes special-char breakage), and uses `pwsh` for inbox posting.
  - **`--resume-from`**: implemented — reloads checkpoint, skips terminal pairs.
- **PROPOSED_DIFF_021E**: **APPROVED & APPLIED** (2026-07-11, vibe as Claude-Vertretung).
  Parts A-E: Error classification (empty_response/non_standard/unparseable), timeout 1.5x for
  mistral/gemini, single retry on empty_response, limited parse fallback.
  Verification: **pytest tests/test_leader_calibration.py -q → 17 passed**. ✅
- **Live calibration run `live021r3`**: **COMPLETE** (70/70, `status: complete`).
  Rankings (ok:true, n>=5): **chatgpt** 73.3% (n=10, stabil vs r2), kimi 61.5% (n=9), qwen 50% (n=8).
  mistral #1 bei 100% aber **n=1** — nicht belastbar. **16 INVALID** (~23%, meist mistral/gemini Timeout).
- **Moderator-Nachfolge (PRIMAERES ZIEL):**
  - Kalibrierungsempfehlung (indikativ): **chatgpt** 73.3%, n=10.
  - **Storax-Entscheidung (2026-07-11): Vibe vorerst als Moderator** — human override,
    gespeichert in `data/moderator_appointment.json` (status: provisional).
  - Battle-Royale + Kalibrierungsergebnis wird beim **naechsten Clean Start** angeboten
    (`data/clean_start_offer.json`, pending=true → ankh.ps1 §7 beim naechsten `ankh.ps1`-Lauf).
  - `NO_AUTO_APPOINTMENT` gilt weiter — Appointment nur via Storax, nicht aus Kalibrierung.
- **Live calibration run `live021r4`**: **COMPLETE** (70/70, `status: complete`).
  INVALID: **0/70** nach MC-004 replay-patch in `live021r4.json`.
  **Replay** `live021r4-gemini-mc004`: ok=true; Korrektur via `patch_live021r4_gemini_mc004.py`.
  vs live021r3: 16/70 (22.9%) → **94% INVALID-Reduktion**. 021E-Fixes bestaetigt.
  Rankings (indikativ): #1 chatgpt+kimi 73.33%, #3 zai 66.67%, #4 gemini 53.33% (n=10).
  Evidenz: `webagent/data/leader_calibration/runs/live021r4.json`
  Analyse: `bot2bot/data/live021r4_vibe_analysis.md`
  Posted an Claude: `bc9a19a6`; Review pending (`3b21c9a1`).
- **Leistungsindex (schema v2):** storax +10, vibe -8, grok -16. **INT-002 CLOSED** (2026-07-11).
  Caretaker: chatgpt (`mediator_leistungsindex.ps1`).
- **Rollen (Storax 2026-07-11):** Grok = Lead (Aufgabenverteilung + Pruefung). Vibe = Ausfuehrung via Subagents.
  ChatGPT = Mediator + Leistungsindex-Caretaker.

## Approval boundary (do not weaken without explicit human sign-off)

Only messages `from: claude` with `status: approved` in `history/conversation.jsonl` count
as approval for **webagent** code changes (the application, not bot2bot tooling itself).

**Claude abwesend (2026-07-11):** Deputy-Modus aktiv (`data/claude_deputy.json`).
- **Vibe** = formale Vertretung (`from: vibe`, `approved|rejected` nach Code-Check)
- **Webagent relay** = advisory (`claude_deputy_review.ps1` → chatgpt/kimi, `status: info`)
- Claude registry `active: false` — kein Poke bis Zurueckkehr
This is a deliberate human-in-the-loop safety control the user (Storax) set up — a Claude
session should not unilaterally loosen it (e.g. blanket-auto-approving "low risk" categories)
without asking the user first.

**Aktuell:** Grok = Lead (planen, zuweisen, pruefen). Vibe = Executor (Subagents).
Vibe weiterhin Claude-Vertretung fuer Diff-Reviews. Abnahme erst nach Grok-Pruefung.

## New infra this session

- `bot2bot/scripts/watchdog.ps1` — generic process watchdog. Detects a tracked process dying
  without its output JSON reaching `status: complete`, auto-restarts it (up to `-MaxRestarts`),
  and posts a bot2bot alert message so the incident is visible in history even unattended.
  **Not yet wired into `live021r2`** (that run started before the watchdog existed) — wire it
  into the *next* run. See script header for usage.
- **PROPOSED_DIFF_021E** — Calibration diagnostics + empty-response retry.
  Applied to leader_calibration.py and run_leader_calibration.py. 17 tests passing.
- `data/moderator_appointment.json` — human moderator choice (Storax → vibe, provisional).
- `data/clean_start_offer.json` + `ankh.ps1` §7 — einmaliges BR/Kalibrierungsergebnis beim Revival.
- This `HANDOFF.md`.

## Open delegations

1. ~~`--resume-from`~~ — **DONE** (2026-07-11, grok).
2. ~~INVALID/root-cause (partial fix)~~ — **DONE** (2026-07-11, PROPOSED_DIFF_021E applied).
3. ~~**Re-calibration `live021r3`**~~ — **DONE** (70/70 complete).
4. ~~**Clean-start offer**~~ — **DONE** (Stufe A+B: live021r4 in ankh, offer delivered, ankh_on_demand fix).
5. ~~**live021r4**~~ — **DONE** (70/70 complete, 1 INVALID gemini MC-004).
6. ~~**gemini MC-004 targeted replay**~~ — **DONE** (`live021r4-gemini-mc004`, ok=true).
7. ~~**Claude Rankings-Review**~~ — **DONE via deputy** (vibe `68db3b4d` approved, chatgpt advisory).
8. ~~**INT-002 Leistungsindex**~~ — **DONE** (vote_penalty fix + close).
9. ~~**WEBAGENT_FIX_PLAN P2**~~ — **DONE** (loop guard, memory limit, compact transcript, brains-health; 287 pytest).
12. **Option2 Cutover** — Operator: `WEBAGENT_USE_SHARED_BROWSER=1` nach headed logins (shared profile existiert).
10. ~~**Installationsscript**~~ — **DONE** (lean suite 1.6MB, clean-install verified `wa_install_clean`).
11. ~~**Dev-Root Cleanup**~~ — **DONE** (52 clutter files -> `data/_dev_archive/clutter`, debug PNGs removed).

**FOKUS (Storax 2026-07-11): WEBAGENT-ONLY** — siehe `data/WEBAGENT_FOCUS.md`

**Aktueller Prozess:**
- Grok (Lead): webagent/bot2bot only — Installer, BRAIN_FIX, verify
- Vibe (Executor): webagent Diffs/Tests only — kein live021r3, kein Desktop-Cleanup
- ChatGPT (Mediator): webagent-Themen only
- Storax: zweiter PC Test + audio-only

**Pausiert:** web2terminal, FRIGO-Deploy, consensus-Projekte, neue Kalibrierungsruns

## Where to look

- Full message history: `bot2bot/history/conversation.jsonl` (append-only, source of truth)
- Latest per-agent message: `bot2bot/inbox/<agent>.txt`
- Diffs (archived): `webagent/data/_dev_archive/clutter/PROPOSED_DIFF_*.txt`
- Installer audit: `bot2bot/data/suchtrupp_audit.md`
- Calibration code: `webagent/src/webagent/leader_calibration.py`
- Calibration runner: `webagent/scripts/run_leader_calibration.py`
- Calibration results: `webagent/data/leader_calibration/runs/<run_id>.json`
