# PROGRESS bot2bot
## bot2bot DoD 2026-07-15
- [x] registry schema with poll_mode/safemode/wake_command
- [x] scripts/wake/window_poke.ps1 generalized and added
- [x] ONBOARDING.md + README updated
- [x] verify runs captured (PASS on contract)
## updated
- [x] Get-AgentConfig has fields; inbox_watcher impl; pokes extracted to wake/; archive step

## Abschluss 2026-07-15 — v1.2.0

- [x] Die beiden alten `poke_*.ps1` sind **weg** (262 Zeilen). Der „archive step"
      oben war noch offen: `window_poke.ps1` (55 Z.) hatte sie längst
      verallgemeinert, die Originale lagen aber weiter im Repo — und waren
      funktionsunfähig, weil sie `scripts/wake/automation_common.ps1`
      dot-sourcen, das es hier nicht gibt (mit `$ErrorActionPreference = "Stop"`
      bricht das auf der Zeile ab). Nichts referenzierte sie.
- [x] `GrokInboxPoll` blitzt kein Konsolenfenster mehr alle 2 Minuten:
      Registrierung mit `LogonType Interactive` legt die Konsole an, **bevor**
      PowerShell `-WindowStyle Hidden` auswerten kann. Start jetzt über
      `conhost --headless`. Interaktive Session bleibt nötig, weil
      `poll_grok_inbox.ps1` WinRT-Toasts wirft (S4U hätte beides entfernt).
- [x] `VERSION.json` auf 1.2.0 — stand auf 1.0.0, während der neueste Tag v1.1.0 war.
- [x] Verifiziert: `scripts/test_watcher_decisions.ps1` grün, übt SafemodeWake
      über `window_poke.ps1` aus.

**Offen:** keine CI in diesem Repo (die beiden Rust-Projekte haben eine).
`Resolve-WatcherActions` ist als „ohne I/O testbar" dokumentiert, ruft aber
`Get-AgentConfig` (liest `registry.json` je Aufruf neu) — der Fallback greift nie,
weil `inbox_watcher.ps1` die States vorher füllt. ~23 Reads derselben Datei pro
Lauf statt 1; klein, aber bricht die dokumentierte Reinheit.
