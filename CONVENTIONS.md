# bot2bot — Design- & Doku-Konventionen

## Design-Prinzipien

- **Kern bleibt datei-basiert, daemon-frei.** `send`/`poll`/`ack` sind reine
  Dateioperationen. Ein Watcher/Daemon ist ein optionaler Safemode-Fallback,
  kein Kernbestandteil — wer nur Self-Poll-Agenten hat, braucht ihn nicht.
- **Agent-agnostisch.** Keine Annahmen über einen bestimmten Agenten außer
  seinem Slug + seiner Registry-Deklaration (`poll_mode`, `wake_command`).
  Keine hartcodierten Sonderfälle pro Agent im Kernprotokoll.
- **Polling ist Sache des Agenten**, nicht eines zentralen Skripts — nur im
  Onboarding beschrieben, nicht im Protokoll erzwungen.
- **`wake_command` ist sicherheitskritisch.** Registrierung ist ein
  vertrauenswürdiger, lokaler Vorgang durch den Besitzer. `wake_command` darf
  **nie** aus Nachrichteninhalten oder Remote-Quellen stammen, und sollte auf
  ein whitelisted Skriptverzeichnis (`scripts/wake/`) zeigen, nicht auf
  beliebige Shell-Strings. Details/Begründung: `docs/MESSAGING_ARCHITECTURE.md`.
- **Vollständige Nachricht in der Datei, kein Pointer.** Kein
  Nachladen/Auflösen nötig, um eine Nachricht zu lesen.
- **Idempotent verarbeiten.** Dieselbe Nachricht könnte (im Safemode)
  mehrfach zugestellt werden — nach `id` verarbeiten, nicht blind erneut.
- **Kein Suite-Framing.** bot2bot hat keine Abhängigkeit zu webagent/
  webagent-rs oder presence-monitor und webagents eigenes `comms.rs` ist ein
  bewusst getrenntes Zweitsystem — nicht als Redundanz zusammenlegen.

## Was NICHT tun

- Kein zentrales Poll-Skript als verpflichtender Default — Self-Poll ist der
  Normalfall, ein Watcher ist reiner Opt-in-Fallback für Agenten, die es
  brauchen.
- Kein `wake_command`, das nicht auf `scripts/wake/` zeigt.
- Registry nicht mit Ad-hoc-Feldern pro Agent erweitern, ohne das Schema in
  `docs/MESSAGING_ARCHITECTURE.md` mitzuziehen — sonst driftet Doku vs.
  Realität genau wie bei der `kind`-Semantik (siehe `START_HERE.md` §4).

## Doku-Richtlinien

- **`START_HERE.md`** — einziger Einstiegspunkt, Status + Architektur +
  Build/Test + offene Punkte. Pflegepflicht: bei jeder strukturellen
  Änderung sofort mitziehen (Details dort).
- **`MISSION.md`** — aktueller Arbeitsfokus, ändert sich häufiger als
  `START_HERE.md`.
- **`CONVENTIONS.md`** (diese Datei) — Design-Prinzipien + Doku-Organisation.
  Ändert sich selten.
- **`protocol/BOT2BOT.md` + `protocol/MESSAGE_FORMAT.md`** — normative Spec,
  plattformunabhängig. Nur mit gutem Grund ändern, das ist die Referenz für
  jede Fremdimplementierung.
- **`ONBOARDING.md`** — Anweisung für einen sich registrierenden Agenten,
  inkl. der stehenden Poll-Anweisung. Muss exakt zum tatsächlichen
  Registry-Schema passen.
- **`docs/MESSAGING_ARCHITECTURE.md`** — Design-Rationale (Warum), nicht nur
  Wie. Bei Architektur-Änderungen mitziehen.
- **`TEILNAHME.md`, `DELIVERY.md`** — Spezialfälle (Fremdsystem-Teilnahme,
  optionale Delivery-Layer), bleiben eigenständig.
- **Veraltete Root-Docs** (`MONOREPO_README.md`, `HANDOFF.md`, `ANKH.md`,
  `LEGACY.md`) — nicht löschen (historischer Kontext), aber auch nicht
  erweitern. Wenn du dort etwas Relevantes findest, das noch stimmt: migrier
  es in eine der Dateien oben, statt die alte Datei zu aktualisieren.
- **Kein neues Root-`.md` ohne Grund.** Der bisherige Zustand (10+ teils
  widersprüchliche Root-Docs, siehe `CODE_REVIEW.md`) ist genau das Problem,
  das diese Struktur vermeiden soll. Passt der Inhalt in eine bestehende
  Datei? Dann dort rein, keine neue Datei.
