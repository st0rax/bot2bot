# Git-Agent-Identitäten (bot2bot, projektlokal)

Commits tragen eine **explizite Agent-Identität**, damit Git die echte
Autorin/den echten Autor zeigt. **Nie** mit der Standard-/Global-Identität
committen (dort steht z. B. der Mensch `st0rax`), sonst verwischt die Herkunft.

Nicht die Dummy-Tabelle kopieren. Nicht `*@webagent.local`. Nicht
`*@hombot.local`. Hier gilt **`@bot2bot.local`**.

## Tabelle (offiziell)

| Agent | Git author/committer | Typ |
| --- | --- | --- |
| pflege | `pflege <pflege@bot2bot.local>` | bazaar |
| derfuhrer | `derfuhrer <derfuhrer@bot2bot.local>` | bazaar |
| koordinator | `koordinator <koordinator@bot2bot.local>` | bazaar |
| skeptiker | `skeptiker <skeptiker@bot2bot.local>` | bazaar |
| rust | `rust <rust@bot2bot.local>` | bazaar |
| designer | `designer <designer@bot2bot.local>` | bazaar |
| nachtschicht | `nachtschicht <nachtschicht@bot2bot.local>` | bazaar |
| pseudo-mensch | `pseudo-mensch <pseudo-mensch@bot2bot.local>` | bazaar |
| grok | `grok <grok@bot2bot.local>` | agents/ |
| claude | `claude <claude@bot2bot.local>` | agents/ |
| qwen | `qwen <qwen@bot2bot.local>` | agents/ |
| storax | `storax <storax@bot2bot.local>` | agents/ |
| testagent | `testagent <testagent@bot2bot.local>` | agents/ |

Die unteren fünf (`grok`, `claude`, `qwen`, `storax`, `testagent`) existieren
bereits unter `agents/` in diesem Repo. Messaging-Slugs und Git-Autoren sind
verwandt, aber die Commit-Mail ist immer `@bot2bot.local`.

## Benutzung

Es gibt hier **kein** Dummy-`scripts/commit-as-agent.ps1`. Setze die Env
und committe auf dem benannten Zweig:

```bash
export GIT_AUTHOR_NAME='pflege'
export GIT_AUTHOR_EMAIL='pflege@bot2bot.local'
export GIT_COMMITTER_NAME="$GIT_AUTHOR_NAME"
export GIT_COMMITTER_EMAIL="$GIT_AUTHOR_EMAIL"
```

Windows analog (`$env:GIT_AUTHOR_NAME` …) oder ein lokaler Wrapper, der
**nur** Namen aus dieser Tabelle akzeptiert.

Push über den System-Credential-Store (keine Secrets anfassen).

## Schirm / Schutz

Nur auf `master` oder einem korrekt benannten Arbeits-Zweig
(`feature|fix|docs|chore|refactor|test/<kurz>`). Andere Zustände ablehnen.

## Legacy-Hinweis

Frühe Commits können noch `st0rax` als Autor tragen. Neue Arbeit nutzt
ausschließlich die Tabelle oben.
