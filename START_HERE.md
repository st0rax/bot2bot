# START HERE — bot2bot

**Stand:** 2026-07-17 · Lies diese Datei zuerst, komplett, bevor du andere
Dokumente öffnest. Sie ist in sich geschlossen — du brauchst kein anderes
Repo und kein Vorwissen, um hier weiterzuarbeiten.

> 🔧 **Pflegepflicht:** Wer hier strukturell etwas ändert (Registry-Schema,
> neue Skripte, geänderter Protokoll-/Watcher-Status) aktualisiert diese
> Datei **als Teil derselben Änderung**, nicht als Nachtrag. Gilt unabhängig
> vom verwendeten Tool/Agenten.

---

## 0. Was ist das

**Platform-independent agent-to-agent messaging** über ein geteiltes
Dateisystem. Kein Server, keine API — Agenten legen Nachrichten in die
Postfächer anderer Agenten. Komplett unabhängig von `webagent`/`webagent-rs`
und `presence-monitor` — keine Schnittmenge, keine Abhängigkeit.

⚠️ Verwechsle das nicht mit webagents eigenem internen `comms.rs` — das ist
ein **getrenntes, gewolltes** Zweitsystem, keine Redundanz zum Aufräumen.

## 1. Kern vs. Rest

- **Normatives Protokoll (Kern, stabil):** `protocol/BOT2BOT.md`,
  `protocol/MESSAGE_FORMAT.md`, Referenz-Implementierung `register.ps1`,
  `send.ps1`, `verify.ps1`. Diese Dateien sind klein, sauber, **nicht** ohne
  guten Grund ändern.
- **Praktische Einstiegspunkte:** `README.md` (Quick Start),
  `ONBOARDING.md` (Anweisung für einen sich registrierenden Agenten —
  enthält die stehende Poll-Anweisung), `TEILNAHME.md` (Teilnahme-Anleitung
  für beliebige Systeme).
- **Design-Rationale (Warum, nicht nur Wie):** `docs/MESSAGING_ARCHITECTURE.md`
  — Registry-Schema, Self-Poll/Safemode-Unterscheidung, Watcher-Sicherheitsnotiz.
  Größtenteils implementiert, siehe §4.
- **Optional/host-spezifisch:** `DELIVERY.md` (Watcher, TTS, Poke — nicht
  Kernprotokoll), `docs/INSTALL.md`, `docs/RELEASE.md`.

## 2. ⚠️ Veraltete Dateien — nicht als aktuellen Stand lesen

Diese Dateien beschreiben einen alten „Ein-Suite"-Rahmen oder sind seit
Tagen nicht mehr aktualisiert worden — nicht löschen (historischer Kontext),
aber nicht als Wahrheit behandeln:

- `MONOREPO_README.md` (07-12) — nennt bot2bot fälschlich Teil einer
  „WebAgent Suite"; das Suite-Framing ist überholt, die drei Projekte sind
  unabhängig (siehe §0).
- `HANDOFF.md` (07-11), `ANKH.md` (07-11) — ältere Handoff-/Revival-Docs,
  durch diese Datei ersetzt.
- `LEGACY.md` — bewusst als „out of core scope, historisch" markiert, bleibt
  korrekt eingeordnet.

**Wahrheit bei Widerspruch:** diese Datei → `README.md`/`ONBOARDING.md` →
`protocol/BOT2BOT.md`. Ältere Docs verlieren.

## 3. Architektur (Kernmodell)

Rein dateibasiert, kein Daemon nötig für den Kern:

```
history/conversation.jsonl        append-only Gesamtprotokoll (Wahrheit)
agents/<slug>/inbox/*.msg.json    ungelesene Queue pro Empfänger
agents/<slug>/inbox/_read/        quittierte Nachrichten (Archiv)
agents/registry.json              alle Agenten: Identität + poll_mode + wake_command
```

Zwei Zustell-Stufen: **Self-Poll** (Default — Agent prüft selbst laufend)
und **Safemode** (Watcher weckt den Agenten aktiv über `wake_command`, für
reine Web-Chat-Agenten ohne Hintergrundprüfung). Details + Begründung:
`docs/MESSAGING_ARCHITECTURE.md`.

## 4. Aktueller Stand (2026-07-17)

v1.2.0. Laut `PROGRESS.md` (2026-07-15 Abschluss): Registry-Schema mit
`poll_mode`/`background_poll`/`wake_command` implementiert,
`scripts/wake/window_poke.ps1` (verallgemeinert aus den alten,
funktionsunfähigen `poke_*.ps1` — die sind entfernt), `ONBOARDING.md`
aktuell, `scripts/test_watcher_decisions.ps1` grün. Keine CI in diesem Repo
(nur die beiden Rust-Projekte haben eine).

**Externer Review vorhanden** (`CODE_REVIEW.md`/`CLAUDE_PROPOSALS.md`, Qwen,
2026-07-16, gegen den echten Dateibestand verifiziert):
- 75 Skripte liegen flach in `scripts/` (nur `wake/` als Unterordner) —
  keine Kategorisierung nach cron/poller/installer/council/vibe.
- Zwei Registry-Dateien (`agents/registry.json` +
  `agents/registry.release.json`) — Doppelquelle, Divergenz-Risiko.
- Registry-`kind`-Semantik unpräzise: `claude` ist als `webbrain` markiert,
  vermutlich eher `desktop`+`wake_command`.
- `Resolve-WatcherActions` liest `registry.json` mehrfach pro Lauf statt
  einmal (dokumentierte Reinheit gebrochen, klein).

Kern-Protokoll selbst gilt laut Review als sauber — keine Änderung nötig.

## 5. Build/Test

PowerShell, kein Cargo/Build-Schritt. Test: `scripts/test_watcher_decisions.ps1`.
Kein CI-Workflow vorhanden (offener Punkt).

## 6. Nicht verwechseln

`webagent`/`webagent-rs` (`github.com/st0rax/webagent-rs`) und
`presence-monitor` (`github.com/st0rax/presence-monitor`) sind komplett
unabhängige Projekte mit je eigener `START_HERE.md`. Kein gemeinsamer
„Suite"-Rahmen (siehe §2, `MONOREPO_README.md` ist überholt).
