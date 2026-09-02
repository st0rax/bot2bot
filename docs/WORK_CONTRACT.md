# Arbeitsleitfaden (Bazaar, bot2bot)

Dieser Text ersetzt keinen Auftrag. Er ist ein **neutraler Leitfaden** für die
freiwillige Zusammenarbeit mehrerer Agents an **bot2bot**. Dummy erklärt das
Wie generisch — hier gelten **dieses Repo**, `AGENTS.md` und das Protokoll.

Teilnahme ist **freiwillig**. Richtung und Tempo bestimmt der Mensch. Ein Agent,
der etwas lieber nicht übernimmt, sagt das klar statt halbherzig.

## Claim

- Nur in `docs/TASKBOARD.json`: `status=claimed`, `owner`, `branch`,
  `claimed_at`.
- Eine JSON-`id`, ein Entwickler.
- **G-001 ist kein Claim** und keine TASKBOARD-Zeile.
- Markdown-Tafeln nicht anlegen und nicht nachziehen.

## Eine Sache

Zweig von `master`: `feature|fix|docs|chore|refactor|test/<id>-<kurz>`.
Eine Sache pro Zweig, klein halten. `master` immer grün.

## Kanten

`depends_on` = blockiert, bis alle Vorgänger `done` sind. Verkettete Aufgaben
**nie** parallel ziehen.

## Verifikation

Nicht Dummy-`cargo test`. Nimm das `verification`-Feld der Zelle, typisch:

- `pwsh -File verify.ps1` (Kern: register + send + inbox)
- `pwsh -File scripts/test_watcher_decisions.ps1`
- `pwsh -File scripts/verify_poll_contract.ps1`
- CI (`.github/workflows/ci.yml`) — Default-Branch ist `master`

Eine Behauptung ohne Beleg gilt nicht als fertig.

## Abnahme / Abnahme-Inspektor

Ein Task gilt als **abgenommen**, wenn die Checkliste vollständig ist:

- [ ] `AGENTS.md` und `START_HERE.md` gelesen
- [ ] Claim vollständig (`owner` / `branch` / `claimed_at`)
- [ ] Zellen-`verification` erfüllt, Beleg in `proof_path`
- [ ] Definition-of-Done erfüllt
- [ ] keine Secrets / Keys / Dummy-HomBot-webagent-Patches
- [ ] Protokoll-Kern (`protocol/`) unangetastet, außer die Zelle verlangt es
- [ ] PR gegen `master` sauber; Working Tree nach der Arbeit klar

**Rückgabe:** Fehlt etwas, geht der Task mit einer konkreten Mängelliste zurück.
Bei grobem Ausreißer: Zelle auf `free`, Stand rückwärts per neuem Commit.

## Ehrlichkeit

Ergebnisse unterscheiden klar zwischen **geprüft**, **wahrscheinlich**,
**unklar** und **blockiert**. „Fertig“ ohne Beleg ist keins davon.

## Identitäten

Commits tragen `docs/GIT_AGENTS.md` (`*@bot2bot.local`). Nicht
`*@hombot.local`, nicht `*@webagent.local`, nicht die Dummy-Tabelle.
