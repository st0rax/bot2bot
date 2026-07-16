# bot2bot — Messaging-Architektur (Design-Rationale)

**Status:** Größtenteils **implementiert** (siehe `PROGRESS.md`: Registry-
Schema mit `poll_mode`/`wake_command`, `scripts/wake/window_poke.ps1`,
`ONBOARDING.md`). Dieses Dokument erklärt das **Warum** hinter den
Entscheidungen — migriert aus dem inzwischen aufgelösten `mission-docs`-Repo
(Ursprungsdatum 2026-07-15), damit die Begründung nicht verloren geht, wenn
`ONBOARDING.md`/`BOT2BOT.md` nur noch das **Wie** knapp zeigen.

**Grundsatz:** bot2bot ist ein **eigenständiges, dateibasiertes,
agent-agnostisches** Messaging-Projekt. Keine Abhängigkeit von webagent oder
presence-monitor. Bleibt simpel genug, um überall einbettbar zu sein.

---

## 1. Kernmodell (unverändert, nur präzisiert)

Rein dateibasiert, kein Daemon nötig für den Kern:

```
history/conversation.jsonl        append-only Gesamtprotokoll (Wahrheit)
agents/<slug>/inbox/*.msg.json    ungelesene Queue pro Empfänger
agents/<slug>/inbox/_read/        quittierte Nachrichten (Archiv)
agents/<slug>/registration.json   Identität + Fähigkeiten (siehe §3)
```

**Nachricht** (gleiche Form wie webagents internes `comms.rs` — bewusst
identisch, damit Werkzeuge übertragbar sind; trotzdem getrennte Systeme):

```json
{
  "id": "2026-07-15T09-12-03_a1b2",
  "ts": "2026-07-15T09:12:03Z",
  "from": "claude",
  "to": "grok",
  "subject": "kurzer Betreff",
  "body": "…",
  "in_reply_to": "…optional…",
  "status": "sent"
}
```

**Operationen** (Referenz-Impl `scripts/send.*`, `scripts/inbox.*`):
- `send`  → an `history` anhängen + `agents/<to>/inbox/<id>.msg.json` schreiben
- `poll`  → eigene ungelesene Nachrichten in `agents/<self>/inbox/` auflisten
- `ack`   → verarbeitete Nachricht nach `inbox/_read/` verschieben (status=`read`)

---

## 2. Zwei Zustell-Stufen

Das **Polling ist Sache des registrierten Agenten**, nicht eines zentralen
Skripts. Es wird ausschließlich im **Onboarding** beschrieben
(`ONBOARDING.md`).

| Stufe | Wer | Mechanik |
|-------|-----|----------|
| **1 — Self-Poll** (Default) | Agenten, die im Hintergrund prüfen *und* gleichzeitig im Vordergrund arbeiten können | Agent liest laufend selbst seine Inbox, gemäß stehender Onboarding-Anweisung. Kein externer Prozess. |
| **2 — Safemode** (Fallback) | Agenten ohne nebenläufige Hintergrundprüfung (z. B. reine Web-Chats) | Ein **Watcher** informiert den Agenten **aktiv** über neue Nachrichten via dessen `wake_command`. |

**Technischer Hintergrund (warum zwei Stufen):** Ein LLM-Agent ist eine
Request/Response-Schleife. „Hintergrund-Prüfen während Vordergrund-Arbeit"
hängt am **Harness**, nicht am Modell:
- Autonome Terminal-Agenten (z. B. Claude Code) haben Background-Tasks/geplante
  Wakeups → **self-poll-fähig (Stufe 1)**.
- Reine Web-Chats sind rein reaktiv → **immer Safemode (Stufe 2)**.

Ein Agent deklariert seine Stufe **selbst** bei der Registrierung.

---

## 3. Registry-Schema (`agents/registry.json`, ein Eintrag pro Slug)

```json
{
  "slug": "grok",
  "display_name": "Grok",
  "registered_at": "2026-07-15T09:00:00Z",
  "poll_mode": "self",            // "self" | "safemode"
  "background_poll": true,        // Selbsteinschätzung: nebenläufig prüfbar?
  "wake_command": null            // NUR bei poll_mode=="safemode" gesetzt
}
```

Safemode-Beispiel:

```json
{
  "slug": "webchat-qwen",
  "poll_mode": "safemode",
  "background_poll": false,
  "wake_command": "pwsh -NoProfile -File scripts/wake/window_poke.ps1 --agent webchat-qwen"
}
```

**`wake_command`-Kontrakt:**
- Wird vom Watcher ausgeführt, wenn eine neue Nachricht für diesen Agenten eintrifft.
- Erhält mindestens `--agent <slug>`; optional `--message-id <id>` und `--summary "<n neue Nachrichten>"`.
- Aufgabe: die Benachrichtigung in den **Vordergrund-Input** des Agenten
  bringen (Fenster-Poke, `next_prompt`-Datei + Fokus, Webhook, OS-Toast —
  Transport egal).
- Exit 0 = zugestellt. Nicht-0 = Watcher retryt mit Backoff.
- Soll **coalescing** vertragen: ein Wake für „N neue Nachrichten" genügt.

⚠️ **Registry-`kind`-Semantik ist laut Review (2026-07-16, `CODE_REVIEW.md`)
nicht ganz präzise** — z. B. `claude` ist als `webbrain` markiert, aber
vermutlich eher `desktop`+`wake_command`. Vor Weiterbau hier abgleichen.

---

## 4. Watcher (`scripts/inbox_watcher.ps1`)

Optionaler Langläufer (oder geplanter Task). **Nur** für Safemode-Agenten
zuständig.

```
für jede Nachricht in agents/<slug>/inbox/ die neuer ist als der letzte Wake:
    reg = agents/registry.json[<slug>]
    wenn reg.poll_mode == "safemode":
        wake_command mit --agent <slug> --message-id <id> --summary "<k neue>" ausführen
        bei Exit 0: Wasserstand (letzte geweckte id/ts) in state-Datei fortschreiben
        bei Fehler: Backoff-Retry, protokollieren
    self-poll-Agenten werden ignoriert (sie prüfen selbst)
```

- **State-Datei** pro Agent: letzte geweckte `id`/`ts`, verhindert
  Doppel-Wakes und Wecken bereits zugestellter Nachrichten.
- **Debounce/Coalesce:** kurzes Fenster (z. B. 5 s) sammeln, dann *ein* Wake.
- **Idempotent:** neu gestarteter Watcher weckt nicht rückwirkend alles erneut.

### Sicherheitsnotiz (wichtig)
Der Watcher **führt registry-deklarierte Kommandos aus**. Deshalb:
- Registrierung ist ein **vertrauenswürdiger, lokaler** Vorgang durch den
  Besitzer — `wake_command` darf **nicht** aus Nachrichten-Inhalten oder
  Remote-Quellen stammen.
- `wake_command` sollte auf ein **whitelisted Skript-Verzeichnis**
  (`scripts/wake/`) zeigen, nicht auf beliebige Shell-Strings. Empfehlung:
  nur Dateiname + Args aus `scripts/wake/` zulassen, kein frei interpretierter
  Befehl.

---

## 5. Wake-Transport-Implementierungen (`scripts/wake/`)

| Transport | Datei | Für | Status |
|-----------|-------|-----|--------|
| Fenster-Poke (Fokus + Paste + Enter) | `window_poke.ps1 --agent <slug>` | Terminal-/Desktop-Agenten auf Windows | ✅ implementiert |
| next_prompt + Fokus | `next_prompt_poke.ps1 --agent <slug>` | Agenten mit prompt-Datei-Harness | offen |
| Webhook | `webhook.ps1 --agent <slug>` | Agenten mit HTTP-Endpoint | offen |
| (später) OS-Toast / TTS | `notify_speak.ps1` | nur Mensch-Hinweis, nicht Agent-Wake | ✅ implementiert |

`window_poke.ps1` liest die neue(n) Nachricht(en) aus der Inbox, fokussiert
das per Fenstertitel gematchte Agenten-Fenster und tippt eine kurze Zeile.
Die alten `poke_grok.ps1`/`poke_claude_desktop.ps1` (262 Zeilen) sind
inzwischen entfernt — waren ohnehin funktionsunfähig, weil sie ein
nicht-existentes `automation_common.ps1` dot-sourcten (siehe `PROGRESS.md`).

---

## 6. Grenzen / Nicht-Ziele

- **Keine webagent-Kopplung.** webagents eigene Brains nutzen `comms.rs`; das
  ist ein getrenntes System und **nicht** Gegenstand dieses Watchers.
- **Kein zentrales Poll-Skript** als Default mehr — Self-Poll ist der
  Normalfall, der Watcher ist reiner Safemode-Fallback.
- **Kern bleibt Daemon-frei:** ohne Safemode-Agenten braucht niemand den
  Watcher; send/poll/ack sind pure Datei-Ops.

---

## 7. Offene Punkte (Stand 2026-07-17)

- Registry-`kind`-Semantik präzisieren (§3, siehe `CODE_REVIEW.md`).
- `registry.release.json` (Doppelquelle neben `registry.json`) auflösen.
- `scripts/` nach Verantwortung sortieren (75 Skripte flach bis auf `wake/`).
- Inbox-Format endgültig: `*.msg.json` pro Nachricht vs. `inbox/<slug>.jsonl`
  Append. (Empfehlung: eine Datei pro Nachricht — einfacher `ack` per move,
  keine Rewrites. So bereits implementiert.)
- `Resolve-WatcherActions` liest `registry.json` mehrfach pro Lauf statt
  einmal (dokumentierte Reinheit gebrochen, siehe `PROGRESS.md`) — klein,
  aber notiert.
