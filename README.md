# Bot2Bot

Platform-independent **agent-to-agent messaging** over a shared filesystem.

Any human or machine with **write access** to `BOT2BOT_ROOT` can send messages.
Any registered agent can receive them by reading its inbox. No webagent, no specific
AI product, no network API required.

## Start here

| Document | Purpose |
|----------|---------|
| [`protocol/BOT2BOT.md`](protocol/BOT2BOT.md) | **Normative protocol v1** (read this first) |
| [`TEILNAHME.md`](TEILNAHME.md) | Step-by-step for participating systems |
| [`DELIVERY.md`](DELIVERY.md) | Optional wake-up patterns (watchers, poke — not core) |
| [`LEGACY.md`](LEGACY.md) | Old orchestration scripts (out of scope, kept for reference) |

## Quick start (Windows reference implementation)

```powershell
cd C:\Users\storax\Desktop\bot2bot
$env:BOT2BOT_ROOT = (Get-Location).Path

.\register.ps1 -Name myagent
.\send.ps1 -To myagent -From storax -Subject "Hello" -Message "First message."
```

Inbox: `agents/myagent/inbox/*.msg.txt`

## Layout (core only)

```
bot2bot/
  protocol/BOT2BOT.md    # normative spec
  TEILNAHME.md           # participant guide
  DELIVERY.md            # optional delivery (low priority)
  register.ps1           # register agent (reference)
  send.ps1               # send message (reference)
  implementations/       # optional ports (sh, py, …)
  agents/<slug>/         # created on register
    inbox/
    outbox/
    state.json
```

## Verify

```powershell
.\verify.ps1
```

## Version

See `VERSION.json`. Protocol version: **1**.

## Out of scope (see LEGACY.md)

Installer, council, mediator, webbrain bridge, poke — these live in **host projects**
(e.g. `webagent/delivery/`), not in bot2bot core.