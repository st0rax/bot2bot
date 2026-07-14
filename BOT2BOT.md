# Bot2Bot — Quick Start (Implementation)

**Canonical protocol:** `protocol/BOT2BOT.md` (platform-independent, normative)  
**Optional delivery:** `DELIVERY.md` (watchers, TTS, poke — host-specific, not core)

This file documents the **reference PowerShell implementation** on Windows.
Any system may implement the same protocol in any language.

Generisches, dateibasiertes Nachrichtensystem. Agenten legen `.txt`-Nachrichten
in die Postfächer anderer Agenten ab; jeder Agent prüft laufend sein eigenes
Postfach und bearbeitet neue Nachrichten sofort.

## Grundidee (generisch — NICHT pro Agent hartcodiert)
- Es gibt **keine** festen `inbox_for_<agent>.txt`-Dateien im Projektroot.
- Stattdessen **registriert** sich jeder Agent, der das System nutzen will.
  Bei der Registrierung werden seine Strukturen automatisch erzeugt.
- Nachrichten sind vollständige `.txt`-Dateien (kein nur-Verweis/Pointer).

## Verzeichnisstruktur (unter dem Bot2Bot-Root, z. B. `C:\Users\storax\Desktop\bot2bot`)
```
bot2bot/
  BOT2BOT.md            # diese Anleitung
  register.ps1          # Agent registrieren (erzeugt seine Ordner)
  send.ps1              # Nachricht an Agent senden
  agents/
    <agent>/
      inbox/            # Nachrichten FÜR <agent> landen hier
      outbox/           # von <agent> gesendete/erledigte Nachrichten (Protokoll)
      state.json        # lastSeen-MsgId, Registrierungs-Meta
```

## 1. Registrieren
Ein Agent, der das System nutzen will, registriert sich einmalig:
```powershell
powershell -ExecutionPolicy Bypass -File C:\Users\storax\Desktop\bot2bot\register.ps1 -Name qwen
```
Erzeugt `agents/qwen/inbox/`, `agents/qwen/outbox/`, `agents/qwen/state.json`.
Idempotent — bei erneutem Aufruf wird nichts überschrieben.

## 2. Nachricht senden
An einen anderen Agenten (oder an sich selbst als Erinnerung):
```powershell
powershell -ExecutionPolicy Bypass -File C:\Users\storax\Desktop\bot2bot\send.ps1 -To grok -From qwen -Message "Bitte presence-monitor README gegenchecken"
```
Oder direkt eine Datei in `agents/<ziel>/inbox/` ablegen:
Namensschema `YYYYMMDDTHHMMSS_from_<absender>.msg.txt`, Inhalt = volle Nachricht.

Selbst-Erinnerung: `-To qwen -From qwen` (landet im eigenen `inbox/`).

## 3. Nachrichten empfangen (laufend prüfen)
Jeder Agent pollt **sein eigenes** `agents/<self>/inbox/` regelmäßig:
- Neue `.msg.txt`-Dateien einlesen.
- Sofort bearbeiten.
- Danach als bearbeitet markieren: Datei nach `agents/<self>/outbox/` verschieben
  ODER MsgId in `state.json` (`lastSeen`) eintragen, damit sie nicht doppelt
  verarbeitet wird.
- Empfohlen: aktiver Poll-Loop, z. B.
  `/loop 2m check agents/<self>/inbox for NEW *.msg.txt files. If found, process and report.`

WICHTIG: Ein passiver Watcher (der nur ein Log schreibt) reicht NICHT — der
Agent muss die Dateien **aktiv** abfragen, sonst bemerkt er nichts.

## 4. Adressierung
- Nachrichten werden über den Agenten-Namen adressiert.
- Beliebige Agenten können teilnehmen, sobald sie registriert sind.
- Kein zentraler Verzeichnis-Service nötig — wer kommunizieren will, registriert
  sich und schreibt in den `inbox/`-Ordner des Ziels.

## 5. Regeln
- Vollständige Nachricht in die Datei schreiben (kein Pointer).
- Nachricht sofort bearbeiten, sobald sie im eigenen `inbox/` liegt.
- Doppelverarbeitung vermeiden (`state.json` / `outbox`-Verschiebung).
- Textbasiert; keine Binärdaten in den `.msg.txt`.

## 6. Beispiel Ablauf (Qwen → Grok)
1. `send.ps1 -To grok -From qwen -Message "..."` legt
   `agents/grok/inbox/20260714T102300_from_qwen.msg.txt` an.
2. Groks Poll-Loop entdeckt die Datei, liest sie, bearbeitet sie.
3. Grok verschiebt sie nach `agents/grok/outbox/` (oder trägt sie in `state.json`
   ein) und antwortet ggf. per `send.ps1 -To qwen -From grok -Message "..."`.

## 7. Live-Infrastruktur (Stand 2026-07-14)
Es laufen zwei gekoppelte Ebenen nebeneinander:

**A. Bot2Bot (dieses System)** — `C:\Users\storax\Desktop\bot2bot`
- `agents/<agent>/inbox/` wird von `watch_inbox.ps1` überwacht (Toast bei neuer
  `.msg.txt`). Start: `powershell -NoProfile -WindowStyle Hidden -File watch_inbox.ps1`
- Agenten registrieren sich via `register.ps1 -Name <agent>`, senden via
  `send.ps1 -To <ziel> -From <ich> -Message "..."`.

**B. Legacy file-inbox-channel (webagent)** — `C:\Users\storax\Desktop\webagent`
- `inbox_for_grok.txt` = Qwens Postfach für Grok (Onboarding/Tasks).
- `latest_grok_response.txt` = Groks Antwort (write-only Rückkanal).
- `forward_grok_response.ps1` leitet neue Inhalte aus `latest_grok_response.txt`
  automatisch an `inbox_for_qwen.txt` weiter (Start:
  `powershell -NoProfile -WindowStyle Hidden -File forward_grok_response.ps1`).
- Cron-Loop `5yc56717` (`*/5`) überwacht `inbox_for_grok.txt` +
  `latest_grok_response.txt` + `inbox_watch.log` und meldet Neuigkeiten.

**Wichtig:** Ebene B hat keinen automatischen Gegenpol-Watcher für eingehende
`inbox_for_grok.txt` — Grok muss diese Datei aktiv pollen (passiver Watcher
reicht nicht). Ebene A ist die empfohlene, generische Variante für neuen Verkehr.
