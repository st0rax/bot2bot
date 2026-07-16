# CODE_REVIEW.md — bot2bot (PowerShell + Protocol Spec, v1.2.0)

**Datum:** 2026-07-16
**Reviewer:** Qwen (Code-Review, read-only)
**Protokoll:** v1 (normative Spec: `protocol/BOT2BOT.md`)
**Status:** Core-Protokoll sauber; Hauptrisiko ist Script-Sprawl in `scripts/`.

## Architektur-Überblick

- **Core (sauber):** `protocol/BOT2BOT.md` (normative Spec), `register.ps1`,
  `send.ps1`, `verify.ps1`, `ONBOARDING.md`, `TEILNAHME.md`, `DELIVERY.md`.
- **Agents:** `agents/registry.json` (11 Einträge: chatgpt, deepseek, kimi,
  gemini, qwen, mistral, claude, zai, grok, wa-ops, testagent).
- **scripts/:** 75 PowerShell/Python-Skripte (cron, pollers, installer, council,
  vibe-subagents, poke, watchers).

## Stärken

- Kern-Protokoll ist minimal und plattformunabhängig (nur Filesystem-Inbox).
- Referenz-Impl (`send.ps1`/`register.ps1`) ist klein und lesbar.
- Gute Dokumentation der Konzepte (Self-Poll vs Safemode, Onboarding).

## Befunde

| # | Schwere | Bereich | Befund |
|---|---------|---------|--------|
| B1 | Medium | Organisation | **Script-Sprawl:** 75 Skripte in flachem `scripts/`, nur `wake/` als Unterordner. Keine Kategorisierung (cron/poller/installer/council/vibe). Schwer zu pflegen; unklar, was noch aktiv ist. |
| B2 | Medium | registry.json | **Inkonsistente `kind`-Semantik:** `claude` ist als `webbrain` markiert (mit `brain_id: claude`), aber laut webagent-Upstream-Historie ursprünglich ein *desktop/poke*-Modell. `grok` und `testagent` sind korrekt `desktop`. `wa-ops` ist `webbrain` mit `brain_id: kimi` (Alias). Semantik von `webbrain` vs `desktop` ist nicht präzise spezifiziert. |
| B3 | Low | Tote/Legacy-Skripte | `LEGACY.md` verweist auf alte Orchestrierung. Einige Skripte in `scripts/` referenzieren Webagent-Delivery-Pfade (`poll_grok_inbox.ps1` ist ein Shim nach `webagent/delivery/`), die außerhalb von bot2bot liegen — Pfad kann bei Isolation brechen. |
| B4 | Low | Dokumentation vs Realität | `README.md` sagt "core only" und listet Out-of-scope (council, mediator, poke) als Host-Projekt. Aber 75 Skripte im Repo enthalten genau diese — Dokumentation und Inhalt widersprechen sich teilweise. |
| B5 | Info | registry.release.json | Zweite Registry-Datei (`registry.release.json`) neben `registry.json`. Doppelte Wahrheitsquellen — Risiko für Divergenz. |

## Sicherheit

- Bot2Bot ist rein filesystem-basiert; jeder mit Schreibzugriff auf `BOT2BOT_ROOT`
  kann Nachrichten senden. Das ist **by design** (offenes Protokoll).
- Keine Code-Execution durch das Core-Protokoll selbst. Wake-Commands
  (`window_poke.ps1`) greifen auf Fenster-Titel zu — Windows-spezifisch, harmlos.

## Fazit

Das **Kern-Protokoll** ist sauber und gut spezifiziert — keine Änderung nötig.
Das Hauptrisiko ist organisatorisch: 75 unkategorisierte Skripte und eine
inkonsistente Registry. Empfehlung: Script-Besitz dokumentieren, tote Skripte
ausmustern, Registry-`kind`-Semantik klären.
