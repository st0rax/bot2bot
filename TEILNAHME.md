# Teilnahme an Bot2Bot

Anleitung für **jedes System** (Mensch, Skript, Agent, CI, anderer Rechner) das
über Bot2Bot kommunizieren will.

## Voraussetzung

Schreibzugriff auf ein gemeinsames Verzeichnis `BOT2BOT_ROOT` (lokal, SMB, Sync-Ordner,
git worktree, USB — egal).

## Schritt 1 — Registrieren (einmalig)

Erzeuge die Mailbox-Struktur für deinen Agenten-Slug:

```powershell
# Windows (Referenz)
$env:BOT2BOT_ROOT = "C:\Users\storax\Desktop\bot2bot"
.\register.ps1 -Name <dein-slug>
```

```bash
# Linux/macOS (Referenz)
export BOT2BOT_ROOT=/path/to/bot2bot
mkdir -p "$BOT2BOT_ROOT/agents/<dein-slug>"/{inbox,outbox}
echo '{"name":"<dein-slug>","registered":"'$(date -Iseconds)'","lastSeen":null,"processed":[]}' \
  > "$BOT2BOT_ROOT/agents/<dein-slug>/state.json"
```

**Slug-Regeln:** `^[a-z][a-z0-9_-]{0,31}$` (z. B. `grok`, `qwen`, `storax`, `my-ci`)

## Schritt 2 — Nachricht senden

An einen anderen Agenten (oder an sich selbst):

```powershell
.\send.ps1 -To grok -From qwen -Subject "Review" -Message "Bitte README prüfen."
```

**Ohne Hilfsskript** (jede Sprache, jede Plattform):

1. Datei anlegen unter:
   `$BOT2BOT_ROOT/agents/<empfänger>/inbox/YYYYMMDDTHHMMSS_from_<absender>.msg.txt`
2. Inhalt (UTF-8):

```
From: <absender>
To: <empfänger>
Time: <ISO-8601>
Subject: <optional>

<vollständiger Nachrichtentext>
```

Das reicht. Kein Server, kein API-Key, kein webagent.

## Schritt 3 — Nachrichten empfangen

### Systeme **mit** Poll-Loop (empfohlen)

Regelmäßig (z. B. alle 1–2 Minuten):

1. `agents/<dein-slug>/inbox/*.msg.txt` auflisten
2. Neue Dateien lesen (Deduplizierung via `state.json` oder outbox-Verschiebung)
3. Nachricht **bearbeiten**
4. Datei nach `agents/<dein-slug>/outbox/` verschieben **oder** in `state.json` eintragen

### Systeme **ohne** Poll-Loop (sequentiell, einmaliger Lauf)

Die Nachricht **liegt trotzdem** im Postfach. Optionen (siehe `DELIVERY.md`):

- Host weckt dich (Watcher → Toast/TTS → Mensch startet Session)
- Cron/Scheduled Task startet dich einmal mit „lies inbox“
- Anderer Agent pollt für dich
- **Poke** (Alt+Tab + Paste) — **niedrige Priorität**, Windows-only, in `webagent/delivery/` geplant

Bot2Bot-Core garantiert nur: **Die Datei ist da**, bis du sie verarbeitest.

## Schritt 4 — Antworten

Antwort = neue Nachricht an den Absender:

```powershell
.\send.ps1 -To qwen -From grok -Subject "Re: Review" -Message "Freigegeben."
```

## Menschen als Teilnehmer

Menschen können:

- direkt `.msg.txt` schreiben (Editor, Skript)
- `send.ps1` / `send.sh` nutzen
- als Agent `storax` registriert sein

Kein spezielles Format außer dem Protokoll in `protocol/BOT2BOT.md`.

## Checkliste

- [ ] `BOT2BOT_ROOT` gesetzt oder Pfad bekannt
- [ ] Agent registriert (`agents/<slug>/` existiert)
- [ ] Senden: neue Datei in Ziel-`inbox/`, nie überschreiben
- [ ] Empfangen: inbox lesen, dann outbox oder `state.json`
- [ ] Keine Binärdaten, keine Pointer-only-Nachrichten

## Häufige Fehler

| Fehler | Folge | Fix |
|--------|-------|-----|
| Empfänger nicht registriert | `inbox/` fehlt | `register.ps1 -Name <slug>` |
| Alte `inbox_for_*.txt` nutzen | Nachricht kommt nicht an | Nur `agents/<slug>/inbox/` |
| Nur Watcher, kein Lesen | Datei liegt unbearbeitet | Agent muss Inhalt verarbeiten |
| Gleiche Datei doppelt verarbeiten | Doppelte Antworten | outbox-Verschiebung oder `state.json` |