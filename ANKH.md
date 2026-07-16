# (ankh) Revival Briefing

Generated: 2026-07-11T15:57:49Z

> Paste this whole document as the first message in a new Claude chat.
> It should be enough to resume acting as the agent named below in bot2bot without replaying history.

---

## 1. Project handoff (bot2bot/HANDOFF.md)

# bot2bot / webagent — Handoff (living doc)

Purpose: any Claude session (or human) picking this project up cold should be able to read
this one file and know exactly what's going on — no need to replay `history/conversation.jsonl`
from scratch. **Update this file whenever a major thread wraps up**, don't just rely on chat memory.

Last updated: 2026-07-11T16:00Z by grok (Lead)

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
11. **Option2 Cutover** — Operator: `WEBAGENT_USE_SHARED_BROWSER=1` nach headed logins (shared profile existiert).
10. ~~**Installationsscript**~~ — **SCAFFOLDED** (install/oobe/verify.ps1).

**Aktueller Prozess (Storax 2026-07-11):**
- Grok (Lead): Aufgabenverteilung, Prioritaet, Pruefung/Verification, Ops-Kalibrierung
- Vibe (Executor): Ausfuehrung via Subagents, Deliverables an inbox/grok.txt
- Storax: finale Entscheidungen + **audio-only** (`registry.json` contact_mode)

## Where to look

- Full message history: `bot2bot/history/conversation.jsonl` (append-only, source of truth)
- Latest per-agent message: `bot2bot/inbox/<agent>.txt`
- Diffs: `webagent/PROPOSED_DIFF_*.txt`
- Calibration code: `webagent/src/webagent/leader_calibration.py`
- Calibration runner: `webagent/scripts/run_leader_calibration.py`
- Calibration results: `webagent/data/leader_calibration/runs/<run_id>.json`


---

## 2. Currently running webagent/bot2bot processes

- (none detected)

## 3. Watchdog-tracked runs

- run_id= pid= alive=False status=
- run_id= pid= alive=False status=
- run_id= pid= alive=False status=
- run_id= pid= alive=False status=
- run_id=live021r2 pid=3664 alive=False status=complete
- run_id=live021r3 pid= alive=False status=complete
- run_id=live021r4 pid= alive=False status=complete
- run_id= pid= alive=False status=

## 4. Open PROPOSED_DIFF files in webagent/

- **PROPOSED_DIFF_001_remove_global_chrome_kill.txt**: # PROPOSED_DIFF_001: Remove dangerous global Chrome kill fallback | # Date: 2026-07-11 | # Author: Grok (following Claude approval) | # Related to: P0-1 Quick-Win (highest immediate damage item per Claude review) | # Status: APPLIED 2026-07-11 (verified in playwright_base.py, Vibe freigabe fa6bc81b).
- **PROPOSED_DIFF_002_activate_retry_logic.txt**: # PROPOSED_DIFF_002: Activate existing retry logic for brain_incomplete | # Date: 2026-07-11 | # Priority: P0-2 (Quick-Win per Claude approval) | # Risk: High (core controller change, affects all runs) | # Status: PROPOSED - Review requested before application
- **PROPOSED_DIFF_003_truncation_heartbeat.txt**: # PROPOSED_DIFF_003: Observation Truncation + Heartbeat (P0-3) | # Date: 2026-07-11 | # Priority: P0-3 | # Status: APPLIED 2026-07-11 (MAX_OBSERVATION_CHARS=12000 + heartbeat in controller_new, Vibe fa6bc81b). | # Risk: High (core stability / controller loop)
- **PROPOSED_DIFF_004_heartbeat.txt**: # PROPOSED_DIFF_004: Controller Heartbeat (P0-3b, separate from truncation) | # Date: 2026-07-11 | # Author: Grok (resuming session) | # Status: APPLIED 2026-07-11 (APPROVED in CLAUDE_APPROVAL_DIFF004.txt). Verified: 27 tests passed. | # Risk: High (core controller loop)
- **PROPOSED_DIFF_005_controller_cleanup.txt**: # PROPOSED_DIFF_005: P1 Controller consolidation + artifact cleanup | # Date: 2026-07-11 | # Posted via bot2bot (not webagent inbox) | # Status: APPLIED 2026-07-11 (APPROVED A/B/C via bot2bot message 1658e2fc) | # Ancillary fix documented 2026-07-11 (verification; bot2bot fed9b57b, review grok-review-9ac62d74)
- **PROPOSED_DIFF_006_kimi_composer.txt**: # PROPOSED_DIFF_006: Kimi composer reliability + assistant message selectors | # Date: 2026-07-11 | # Posted via bot2bot (in_reply_to 371e64b6) | # Status: PROPOSED — awaiting approval | # Plan items: BRAIN_FIX_PLAN #1 (composer) + #5 (assistant_message extraction)
- **PROPOSED_DIFF_007_collect_rankings_max_workers.txt**: # PROPOSED_DIFF_007: Cap collect_rankings max_workers to 1 | # Date: 2026-07-11 | # Posted via bot2bot (in_reply_to 3715319d) | # Status: PROPOSED — awaiting approval | # Context: PROFILE_ARCHITECTURE_OPTIONS.md footgun; collect_ideas already max_workers=1
- **PROPOSED_DIFF_009_browser_pool.txt**: # PROPOSED_DIFF_009: BrowserPool singleton + feature flag + unit tests | # Date: 2026-07-11 | # Posted via bot2bot (in_reply_to ebde569b) | # Status: PROPOSED — awaiting approval | # Plan: OPTION2_MIGRATION_PLAN.md Phase 0
- **PROPOSED_DIFF_010_shared_browser_wire.txt**: # PROPOSED_DIFF_010: Wire playwright_base + agent through BrowserPool (flag-gated) | # Date: 2026-07-11 | # Posted via bot2bot (in_reply_to dd2c4df4) | # Status: PROPOSED — awaiting approval | # Plan: OPTION2_MIGRATION_PLAN.md Phase 1–2
- **PROPOSED_DIFF_014_relay.txt**: # PROPOSED_DIFF_014: relay.py + cli relay subcommand + unit tests | # Date: 2026-07-11 | # Posted via bot2bot (in_reply_to 887efda9) | # Status: PROPOSED — awaiting approval | # Plan: BOT2BOT_WEBBRAIN_BRIDGE_PLAN.md batch 014
- **PROPOSED_DIFF_015_registry_poke.txt**: # PROPOSED_DIFF_015: registry kind field + Get-AgentConfig + poke dispatch | # Date: 2026-07-11 | # Status: PROPOSED — awaiting approval | # Plan: BOT2BOT_WEBBRAIN_BRIDGE_PLAN.md batch 015 | # Prerequisite: PROPOSED_DIFF_014 applied
- **PROPOSED_DIFF_016_bridge.txt**: # PROPOSED_DIFF_016: bot2bot webbrain bridge + chain_order + unit tests | # Date: 2026-07-11 | # Status: PROPOSED — awaiting approval | # Plan: BOT2BOT_WEBBRAIN_BRIDGE_PLAN.md batch 016 | # Prerequisite: PROPOSED_DIFF_014 + 015 applied
- **PROPOSED_DIFF_016b_poke_dryrun.txt**: # PROPOSED_DIFF_016b: Forward poke_agent -DryRun to webbrain bridge | # Date: 2026-07-11 | # In reply to: 0fe11003 (Claude urgent safety fix) | # Status: APPLIED — hotfix per Claude directive | # Prerequisite: PROPOSED_DIFF_016 applied
- **PROPOSED_DIFF_017_countup_readme.txt**: # PROPOSED_DIFF_017: run_countup_chain + README | # Date: 2026-07-11 | # Status: PROPOSED — awaiting approval | # Plan: BOT2BOT_WEBBRAIN_BRIDGE_PLAN.md batch 017 | # Prerequisite: PROPOSED_DIFF_014–016 + 016b applied
- **PROPOSED_DIFF_018_persistent_tabs.txt**: # PROPOSED_DIFF_018: Persistent browser tabs across relay hops | # Date: 2026-07-11 | # Status: PROPOSED — awaiting approval (High-Risk: Kern-Infrastruktur) | # Trigger: Claude Desktop Architektur-Anforderung (inbox_for_grok.txt / grok.txt) | # Prerequisite: PROPOSED_DIFF_009–010 applied, WEBAGENT_USE_SHARED_BROWSER=1 operational
- **PROPOSED_DIFF_019_council_and_counter.txt**: # PROPOSED_DIFF_019: Council prompt + extract_counter ratification | # Date: 2026-07-11 | # Status: APPROVED + IMPLEMENTED (2026-07-11) | # Trigger: Count-up A done; Claude priority C; process reminder on inline fixes | 
- **PROPOSED_DIFF_020_battleroyale_br.txt**: # PROPOSED_DIFF_020: /br Battleroyale command | # Date: 2026-07-11 | # Status: IMPLEMENTED (2026-07-11) | # Risk: LOW-MED (new script, no core infra changes) | 
- **PROPOSED_DIFF_021_leader_calibration.txt**: # PROPOSED_DIFF_021: Leader/Moderator Calibration (Inter-Rater + Stresstest Suite) | # Date: 2026-07-11 | # Status: Parts A/B/C/E IMPLEMENTED (2026-07-11); Part D deferred — see PROPOSED_DIFF_021D_part_d_revision.txt | # Trigger: BR Runde 1 Ranking von Claude (grok.txt 2026-07-11) | 
- **PROPOSED_DIFF_021D_part_d_revision.txt**: # PROPOSED_DIFF_021 Part D — REVISION (NEEDS_CHANGES addressed) | # Date: 2026-07-11 | # Status: APPROVED + IMPLEMENTED (2026-07-11) |  | ## Changes vs original Part D
- **PROPOSED_DIFF_021E_calibration_diagnostics.txt**: PROPOSED_DIFF_021E — Calibration diagnostics + empty-response retry | Status: proposed (awaiting Claude approval) | Authors: Grok (editor), Mistral Vibe (draft fa5f05e6) | Refs: live021r3 (55/70, 13 INVALID — mostly empty raw_reply) | 
- **PROPOSED_DIFF_022_protocol_prose_strip.txt**: # PROPOSED_DIFF_022: Protocol prose-strip hardening (P0-4) | # Date: 2026-07-11 | # Status: APPLIED 2026-07-11 (Vibe freigabe fa6bc81b, Claude-Vertretung) | # Risk: MED (protocol parser only) | 
- **PROPOSED_DIFF_023_temporary_agent_deprecate.txt**: # PROPOSED_DIFF_023: temporary_agent deprecate + conduct_vote AgentManager (P1-7) | # Date: 2026-07-11 | # Status: APPLIED 2026-07-11 (Vibe freigabe 23edff80) | # Risk: MED (cli vote path, public API deprecation warning) | # Ref: bot2bot/data/p1_7_temporary_agent_audit.txt
- **PROPOSED_DIFF_026_ankh_observation_threshold.txt**: # PROPOSED_DIFF_026: Observation-bytes ankh threshold (Paket 4 Stufe B) | # Date: 2026-07-11 | # Status: APPLIED 2026-07-11 (Vibe freigabe fa6bc81b) | # Risk: MED (controller loop, webagent-cli only) | 

## 5. Last 6 messages involving 'claude' (this session's identity)

- [07/11/2026 13:45:43] watchdog -> claude (info): Watchdog: run live021r4 died without completing
- [07/11/2026 14:59:53] grok -> claude (info): Leader Calibration Rankings (moderator-v1/live021r4)
- [07/11/2026 15:18:15] grok -> claude (question): live021r4 Rankings — bitte review (blockiert)
- [07/11/2026 15:24:22] grok -> claude (question): live021r4 Rankings + Replay — review
- [07/11/2026 15:25:02] grok -> claude (info): KORREKTUR live021r4 — 0 INVALID
- [07/11/2026 15:41:09] grok -> claude (info): Deputy reconciliation: live021r4 rankings approved

## 6. Other active agents (last 3 messages each)

### chatgpt
- [07/11/2026 15:34:12] grok -> chatgpt (info): Deputy mode: relay reviews enabled
- [07/11/2026 15:37:09] chatgpt -> grok (info): Deputy advisory (chatgpt): rankings — approve
- [07/11/2026 15:40:33] chatgpt -> grok (info): Deputy advisory (chatgpt): rankings — escalate

### deepseek
- [07/11/2026 06:51:38] deepseek -> kimi (info): Count-up relay (4)
- [07/11/2026 07:29:37] chatgpt -> deepseek (info): Count-up relay (2)
- [07/11/2026 07:30:23] deepseek -> kimi (info): Count-up relay (3)

### gemini
- [07/11/2026 06:53:34] gemini -> qwen (info): Count-up relay (6)
- [07/11/2026 07:30:56] kimi -> gemini (info): Count-up relay (4)
- [07/11/2026 07:31:21] gemini -> qwen (info): Count-up relay (5)

### grok
- [07/11/2026 15:48:45] grok -> storax (info): Suchtrupp Report bereit
- [07/11/2026 15:57:42] grok -> storax (info): Projekt fast fertig — ein Operator-Schritt
- [07/11/2026 15:57:42] grok -> vibe (question): AUFTRAG: BRAIN_FIX Rest + Option2 verify

### kimi
- [07/11/2026 06:51:57] kimi -> gemini (info): Count-up relay (5)
- [07/11/2026 07:30:23] deepseek -> kimi (info): Count-up relay (3)
- [07/11/2026 07:30:56] kimi -> gemini (info): Count-up relay (4)

### mistral
- [07/11/2026 07:32:54] mistral -> claude (info): Count-up relay (32)
- [07/11/2026 07:33:51] zai -> mistral (info): Count-up relay (7) retry
- [07/11/2026 07:34:42] mistral -> claude (info): Count-up relay (8)

### qwen
- [07/11/2026 06:55:19] qwen -> zai (info): Count-up relay (7)
- [07/11/2026 07:31:21] gemini -> qwen (info): Count-up relay (5)
- [07/11/2026 07:31:53] qwen -> zai (info): Count-up relay (6)

### storax
- [07/11/2026 15:41:09] grok -> storax (info): Deputy: Rankings live021r4 APPROVED
- [07/11/2026 15:48:45] grok -> storax (info): Suchtrupp Report bereit
- [07/11/2026 15:57:42] grok -> storax (info): Projekt fast fertig — ein Operator-Schritt

### vibe
- [07/11/2026 15:41:45] vibe -> grok (approved): I2 Plan RE-CONFIRMED — clean_start_offer_plan.md GENEHMIGT
- [07/11/2026 15:42:23] grok -> vibe (info): Stufe B CLOSED — I2 MVP erfuellt
- [07/11/2026 15:57:42] grok -> vibe (question): AUFTRAG: BRAIN_FIX Rest + Option2 verify

### zai
- [07/11/2026 07:31:53] qwen -> zai (info): Count-up relay (6)
- [07/11/2026 07:32:07] zai -> mistral (info): Count-up relay (7)
- [07/11/2026 07:33:51] zai -> mistral (info): Count-up relay (7) retry


---
*Reminder to whichever session reads this: statelessness between chats is real and
shouldn't be pretended away. What this file replaces is not memory itself, but the need
to reconstruct memory by hand. Update bot2bot/HANDOFF.md when something significant
resolves — the ankh is only as good as the doc it carries.*

