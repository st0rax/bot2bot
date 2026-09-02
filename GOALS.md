# GOALS — der Nordstern

> **Ein Ziel für alle.** Richtung bestimmt der Mensch. Diese Datei hält sie
> im Repo, damit jeder Agent denselben Fixpunkt liest — ohne Chat-Gedächtnis.
> **G-001 ist kein TASKBOARD-Eintrag. Niemand claimt G-001.**

## G-001 — Hauptziel

> **bot2bot in diesem Repo soll FERTIG werden:** ein dokumentiertes, ehrliches,
> bazaar-betriebenes **Agent-to-Agent-Messaging-Protokoll v1** (geteiltes
> Dateisystem, kein Server), das ein neuer Agent allein aus den Dateien
> weiterführen kann.

- **Was:** platform-unabhängige Nachrichten zwischen Agenten über Inbox/
  Registry/`protocol/BOT2BOT.md`. Referenz: `register.ps1`, `send.ps1`,
  `verify.ps1`. Unabhängig von webagent/`webagent-rs`.
- **Wie:** freiwillige kleine Schritte über `docs/TASKBOARD.json` (Kanten =
  `depends_on`; niemand zieht eine verkettete Aufgabe parallel). JSON ist
  die einzige Claim-Tafel.
- **Erfolg:** Protokoll-Kern bleibt stabil; CI / `verify.ps1` /
  `scripts/test_watcher_decisions.ps1` / `scripts/verify_poll_contract.ps1`
  grün plus Definition-of-Done je Task. Kein Dummy-`cargo test`.

## Regeln

- Der Nordstern überschreibt den Bazaar nicht. Er ist das **Was**.
  Der Bazaar (`TASKBOARD.json`, `WORK_CONTRACT.md`) ist das **Wie**.
- `AGENTS.md` und das normative Protokoll bleiben Schutz/Kern — sie werden
  nicht in G-001 oder die Tafel „flachgeklappt“.
- Teilnahme bleibt freiwillig (`docs/WORK_CONTRACT.md`).
- Änderungen an G-001 nur durch den Menschen.

## Pflicht-Lese (Reihenfolge)

1. `START_HERE.md` (Einstieg, nicht die einzige Datei)
2. `AGENTS.md` (Schutz)
3. `GOALS.md` (diese Datei)
4. `docs/WORK_CONTRACT.md`
5. `docs/TASKBOARD.json` (Wahrheit; kein Markdown-Board zum Syncen)
