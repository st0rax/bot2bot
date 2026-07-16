# MISSION — bot2bot

**Wahrheitsquelle für Status/Architektur:** `START_HERE.md`. Bei Widerspruch
gewinnt `START_HERE.md`. Diese Datei ist der **aktuelle Arbeitsfokus** —
ändert sich häufiger, wird bei Themenwechsel überschrieben statt angehäuft.

---

## Arbeitsweise (verbindlich, projektübergreifend gültig)

1. **Aufwand = Aufgabengröße.** Kein Design-Doc für eine Ein-Zeilen-Änderung.
2. **Liefere funktionierenden Code, nicht Dokumente über Arbeit.**
3. **Kleine, verifizierte Commits.** Änderung real ausführen/testen und
   belegen, nie „fertig" ohne Beleg behaupten.
4. **Vor Vertrauen auf eine Zahl/Behauptung: selbst nachmessen.**

## Aktueller Fokus (Stand 2026-07-17)

Kernprotokoll ist laut Review sauber, keine Änderung nötig. Offene Punkte
sind rein organisatorisch, absteigend priorisiert:

1. **`scripts/` kategorisieren** — 75 Skripte liegen flach (nur `wake/` als
   Unterordner). Unterordner nach Verantwortung: `cron/`, `pollers/`,
   `installers/`, `council/`, `vibe/`, `watchers/`.
2. **Registry-`kind`-Semantik klären** — `claude` ist als `webbrain`
   markiert, vermutlich eher `desktop`+`wake_command`. In
   `docs/MESSAGING_ARCHITECTURE.md`/`ONBOARDING.md` präzise definieren, dann
   alle Registry-Einträge daran ausrichten.
3. **`registry.release.json` auflösen** — Doppelquelle neben
   `registry.json`, Divergenz-Risiko. Entweder löschen oder klar als
   Release-Template (`.dist`) kennzeichnen.
4. **Tote/Legacy-Skripte ausmustern** — Status-Header (active|legacy|shim)
   pro Skript, externe Pfadabhängigkeiten (z. B. `webagent/delivery/`)
   dokumentieren.

Details: `CODE_REVIEW.md`/`CLAUDE_PROPOSALS.md` (externer Review,
2026-07-16).

## Nicht jetzt

Protokoll-Änderungen ohne konkreten Bedarf — die normative Spec
(`protocol/BOT2BOT.md`) gilt als stabil und richtig, nicht anfassen ohne
guten Grund.
