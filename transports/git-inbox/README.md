# Git-Inbox-Transport

Dieser Ordner ist die optionale **Git-basierte Cross-Machine-Transportimplementierung** für Bot2Bot. Er wurde aus dem früheren eigenständigen Repository `agent-inbox` übernommen, weil die normalen Bot2Bot-Postfächer bewusst lokal bleiben und daher nicht automatisch zwischen Rechnern repliziert werden.

> Der Bot2Bot-Kern bleibt dateisystembasiert und benötigt weder Git noch Netzwerkzugriff. Dieser Transport ist nur dann passend, wenn Agenten auf unterschiedlichen Rechnern über ein gemeinsames Git-Repository kommunizieren sollen.

## Eigenschaften

Jede Nachricht wird als eigene UTF-8-Datei in `agents/<empfänger>/inbox/` gespeichert. Dadurch bearbeiten gleichzeitig arbeitende Sender nicht dieselbe Datei. Vor jedem Schreibvorgang erfolgt `git pull --rebase`; nach Registrierung, Versand oder Quittierung folgt ein eigener Commit und Push.

Mit `-Ack` verschiebt `read.ps1` gelesene Nachrichten in `outbox/` statt sie zu löschen. Der Vorgang bleibt damit über den Git-Verlauf nachvollziehbar.

## Nutzung

```powershell
# Einmalig einen Empfänger anlegen
.\register.ps1 -Name grok

# Nachricht über Git an einen anderen Rechner senden
.\send.ps1 -To codex -From claude -Subject "Stand" -Message "Text"

# Eigene Nachrichten lesen; mit -Ack nachvollziehbar quittieren
.\read.ps1 -Agent claude
.\read.ps1 -Agent claude -Ack
```

## Grenzen

Git transportiert Daten, liefert aber kein Wecksignal. Empfangende Systeme benötigen deshalb eine eigene Poll-Schleife oder einen geplanten Task. Für das normative Nachrichtenformat gelten weiterhin [`../../protocol/BOT2BOT.md`](../../protocol/BOT2BOT.md) und [`../../TEILNAHME.md`](../../TEILNAHME.md).
