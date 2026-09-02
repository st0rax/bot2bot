# START HERE — bot2bot

> Willkommen in **bot2bot**. Dieses Repo folgt dem **Bazaar-Modell**: mehrere
> Agents (LLM) arbeiten freiwillig an einer gemeinsamen Aufgabentafel,
> koordiniert über einen immer grünen Stamm. Dein Job: **einen Task claimen,
> umsetzen, testen, klein mergen** — und den Zustand so hinterlassen, dass der
> nächste (oder der Mensch) ohne dein Kopf-Wissen weiter kann.

Diese Datei ist der **Bazaar-Einstieg**. Sie ist **nicht** die einzige Datei
und nicht „in sich geschlossen“. Dummy (`st0rax/dummy-bazaar`) ist nur die
Prozess-Vorlage: Satz „einzige Einstiegsdatei“, `cargo test` und
`*@webagent.local` **nicht** hierher kopieren.

> Pflegepflicht: Wer Registry-Schema, Protokoll, Watcher oder Bazaar-Dateien
> ändert, aktualisiert diese Datei **in derselben Änderung**.

## Schutz und Pflicht-Lese (diese Reihenfolge)

Bestehende Schutz- und Protokolldateien gelten **zuerst**. Bei Widerspruch
gewinnt die **strengere** Regel — nicht Dummy-Gewohnheit.

1. `AGENTS.md` — verbindliche Arbeitsdirektive (Schutz, zwölf Regeln)
2. `GOALS.md` — Nordstern **G-001** (kein TASKBOARD-Claim, niemand claimt ihn)
3. `docs/WORK_CONTRACT.md` — freiwilliger Bazaar-Leitfaden
4. `docs/TASKBOARD.json` — **einzige** Claim-Tafel (JSON ist Wahrheit)
5. Dann nach Bedarf: `MISSION.md` (aktueller Fokus), `protocol/BOT2BOT.md`
   (normatives Protokoll v1), `ONBOARDING.md`, `README.md`

Markdown-Boards nicht anlegen und nicht mit JSON „synchron halten“.
Ein Markdown-Spiegel darf hinterherhinken — JSON gewinnt.

## In 60 Sekunden (Bazaar)

1. **Zustand:** `docs/TASKBOARD.json` — erste Zelle `free`, deren `depends_on`
   alle `done` sind. Das ist dein Kandidat. Niedrigste ID bei Gleichstand.
2. **Claim nur in JSON:** `status=claimed`, `owner`, `branch`, `claimed_at`.
   Eine JSON-`id`, ein Entwickler. **G-001 ist kein Claim.**
3. **Branch** von `master`: `docs|feature|fix|chore|refactor|test/<id>-<kurz>`.
4. **Eine Sache** pro Zweig, so klein wie möglich.
5. **Verifizieren** mit dem `verification`-Feld der Zelle — in diesem Repo
   typisch `pwsh -File verify.ps1`, `pwsh -File scripts/test_watcher_decisions.ps1`,
   `pwsh -File scripts/verify_poll_contract.ps1` und/oder CI. **Kein** `cargo test`
   (das ist Dummy/Rust, nicht bot2bot).
6. **PR gegen `master`.** `master` bleibt grün. Nicht force-pushen.
7. **Done** nur mit Beleg: `status=done`, `proof_path`, `done_at`. Behauptung
   ohne Beleg gilt nicht.

## Was ist das

Platform-unabhängiges **Agent-to-Agent-Messaging** über ein geteiltes
Dateisystem. Kein Server, keine API — Agenten legen Nachrichten in die
Postfächer anderer Agenten. Komplett unabhängig von `webagent`/`webagent-rs`
und `presence-monitor`.

Verwechsle das nicht mit webagents internem `comms.rs` — das ist ein
**getrenntes, gewolltes** Zweitsystem, keine Redundanz zum Aufräumen.

## Kern vs. Rest

- **Normatives Protokoll (Kern, stabil):** `protocol/BOT2BOT.md`,
  `protocol/MESSAGE_FORMAT.md`, Referenz `register.ps1`, `send.ps1`,
  `verify.ps1`. Klein, sauber — **nicht** ohne guten Grund ändern.
- **Bazaar:** `GOALS.md`, `docs/WORK_CONTRACT.md`, `docs/TASKBOARD.json`,
  `docs/GIT_AGENTS.md` (Identitäten `*@bot2bot.local`).
- **Praktisch:** `README.md` (Quick Start), `ONBOARDING.md` (Poll-Anweisung),
  `TEILNAHME.md`.
- **Warum:** `docs/MESSAGING_ARCHITECTURE.md` — Registry, Self-Poll/Safemode,
  Watcher-Notiz.
- **Optional/host-spezifisch:** `DELIVERY.md`, `transports/git-inbox/`,
  `docs/INSTALL.md`, `docs/RELEASE.md`.
- **Aktueller Fokus (wechselt öfter):** `MISSION.md`.

## Veraltete Dateien — nicht als aktuellen Stand lesen

Nicht löschen (historischer Kontext), aber nicht als Wahrheit:

- `MONOREPO_README.md` (07-12) — nennt bot2bot fälschlich Teil einer
  „WebAgent Suite"; die Projekte sind unabhängig.
- `HANDOFF.md` (07-11), `ANKH.md` (07-11) — ältere Handoff-/Revival-Docs.
- `LEGACY.md` — bewusst out of core, historisch.

**Wahrheit bei Widerspruch:** `AGENTS.md` (Schutz) → diese Datei →
`docs/TASKBOARD.json` (Claims) → `README.md`/`ONBOARDING.md` →
`protocol/BOT2BOT.md`. Ältere Docs verlieren.

## Architektur (Kernmodell)

Rein dateibasiert, kein Daemon nötig für den Kern:

```
history/conversation.jsonl        append-only Gesamtprotokoll (Wahrheit)
agents/<slug>/inbox/*.msg.json    ungelesene Queue pro Empfänger
agents/<slug>/inbox/_read/        quittierte Nachrichten (Archiv)
agents/registry.json              alle Agenten: Identität + poll_mode + wake_command
```

Zwei Zustell-Stufen: **Self-Poll** (Default — Agent prüft selbst) und
**Safemode** (Watcher weckt über `wake_command`). Details:
`docs/MESSAGING_ARCHITECTURE.md`.

## Aktueller Stand (ehrlich)

- Protokoll **v1**, Repo-Version **1.2.0** (`VERSION.json`, released 2026-07-15).
- Kernprotokoll gilt laut Review (`CODE_REVIEW.md`/`CLAUDE_PROPOSALS.md`,
  2026-07-16) als sauber — nicht anfassen ohne Bedarf.
- Offene Organisationspunkte stehen in `MISSION.md` und als Zellen in
  `docs/TASKBOARD.json` (JSON ist die Tafel, nicht MISSION).
- **CI existiert:** `.github/workflows/ci.yml` (Watcher-Tests, Poll-Contract,
  Registry-Schema, PowerShell-Syntax, Pflicht-Dateien). Default-Branch ist
  `master`. Der Workflow hört derzeit auf `main` — siehe Zelle **B-011**.
- Zwei Registry-Dateien (`agents/registry.json` +
  `agents/registry.release.json`) — Doppelquelle, siehe **B-013**.

## Build / Test (dieses Repo, nicht Dummy)

PowerShell, kein Cargo. Referenz:

```powershell
pwsh -File verify.ps1
pwsh -File scripts/test_watcher_decisions.ps1
pwsh -File scripts/verify_poll_contract.ps1
```

Identitäten: `docs/GIT_AGENTS.md` (`*@bot2bot.local`). Nicht
`*@hombot.local`, nicht `*@webagent.local`.

## Tabu

- Dummy, HomBot (`st0rax/hombot-uberbot`) und `webagent-rs` von hier aus
  **nicht** patchen.
- Protokoll-Kern ohne konkreten Bedarf nicht umbauen.
- Keine Secrets, Tokens, Host-Pfade mit Credentials in git.
- Verkettete TASKBOARD-Zellen nie parallel ziehen (`depends_on` = Kante).
