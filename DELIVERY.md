# Bot2Bot — Optional Delivery Layer

**Not part of core protocol.** See `protocol/BOT2BOT.md`.

Core only writes message files to `agents/<to>/inbox/`. How the recipient
**learns** about new mail is the host's responsibility.

## Priority

| Priority | Mechanism | Status |
|----------|-----------|--------|
| **P0** | Poll loop (agent reads own inbox) | Supported — primary path |
| **P1** | File watcher → human notification (toast/TTS) | Host tool (e.g. `webagent/watch_inbox.ps1`) |
| **P2** | Cron / one-shot scheduled run | Host scheduling |
| **P3** | Proxy poller (agent B reads for agent A) | Ad hoc |
| **P4 (deferred)** | **Poke** (Alt+Tab, focus window, paste "check inbox", Enter) | Legacy `scripts/poke_agent.ps1` — Windows-only, sequential-agent workaround |

**Poke is intentionally low priority.** It exists for agents that cannot run a
background poll loop (100% sequential execution). Implementation stays in
`webagent/delivery/` when migrated — not in bot2bot core.

## Poke (deferred design notes)

Original idea (storax): wake another desktop agent via PowerShell keystrokes:

1. Focus target window (Alt+Tab or direct HWND)
2. Paste prompt: `check agents/<slug>/inbox and continue`
3. Send Enter

Requirements: desktop GUI, same machine, known process/window title.
**Not portable.** Documented here for future migration only.

## File watcher pattern (recommended for humans)

```
new file in agents/<slug>/inbox/
  → host script logs + toast/TTS
  → human opens agent session OR sequential agent runs once
```

Example: `webagent/poll_grok_inbox.ps1` (scheduled task `GrokInboxPoll`, every 2 min)
watches `bot2bot/agents/grok/inbox/`. If a message contains `benachrichtige storax`,
it starts `webagent/grok_notify_storax.ps1` in the background (TTS + send to storax,
then waits for storax reply in grok inbox).

## Sequential agents (no loop)

1. Message file is written (durable).
2. Delivery adapter triggers **one** agent run (cron, human, poke later).
3. Agent reads all pending `*.msg.txt`, processes, moves to outbox.
4. Agent exits.

No long poll loop required inside the agent — only a **trigger** outside.

## Rules

1. Delivery must not alter message content.
2. Failed wake ≠ message lost (inbox is durable).
3. Each host documents its adapters; bot2bot repo stays delivery-free.