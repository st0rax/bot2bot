# Legacy — Out of Bot2Bot Core Scope

These components remain in this tree for **historical / migration** purposes.
They are **not** part of Bot2Bot protocol v1.

**Target home:** `webagent/delivery/`, `webagent/installer/`, or separate ops repos.

| Area | Paths | Status |
|------|-------|--------|
| Grok inbox poll / notify storax | `scripts/poll_grok_inbox.ps1`, `scripts/grok_notify_storax.ps1`, `scripts/install_grok_inbox_poll_task.ps1`, `scripts/watch_inbox.ps1` | **Moved** → `webagent/poll_grok_inbox.ps1`, `webagent/grok_notify_storax.ps1` |
| Legacy webagent inbox hash | `scripts/check_inbox.ps1` | **Obsolete** — use bot2bot `agents/<slug>/inbox/` |
| Poke / window focus | `scripts/poke_agent.ps1`, `scripts/poke_grok.ps1` | **Deferred** — delivery, Windows-only |
| Webbrain bridge | `scripts/bot2bot_webbrain_bridge.ps1` | Move to webagent |
| Installer / release | `scripts/package_release.ps1`, `install.ps1`, `dist/` | Move to webagent-suite |
| Council / mediator | `scripts/*council*`, `scripts/mediator_*` | Move to webagent governance |
| Old inbox pointer | `inbox/_archive/<agent>.txt` (archived 2026-07-14), `history/conversation.jsonl` | Migrate to `agents/<slug>/inbox/` |
| Old registry | `agents/registry.json` (webbrain dispatch) | Move to `webagent/agents/dispatch_registry.json` |
| ANKH / HANDOFF | `ANKH.md`, `HANDOFF.md` | Ops docs, not protocol |

Do **not** extend these for new comms features. Use `protocol/BOT2BOT.md` instead.