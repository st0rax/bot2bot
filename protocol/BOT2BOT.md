# Bot2Bot Protocol v1

Platform-independent agent-to-agent messaging over a shared filesystem.
No webagent dependency. No OS-specific delivery (poke, toast, TTS) in core.

## Scope

**In scope (core):**
- Agent identity (slug)
- Mailbox directories per agent
- Message file format and naming
- Send, receive, deduplication, optional archive

**Out of scope (host-specific delivery):**
- Waking agents that cannot poll (watchers, cron, webhooks, TTS)
- Browser relay, window focus, installer, governance, approval workflows
- See `../DELIVERY.md` for optional delivery patterns per host

## Terms

| Term | Meaning |
|------|---------|
| `BOT2BOT_ROOT` | Root directory of the bot2bot installation (any path, any OS) |
| Agent | A named participant identified by a slug |
| Inbox | Directory where messages **for** an agent are stored |
| Outbox | Directory where **processed** messages are moved |
| Message | One plain-text file with header + body |

## Directory layout

```
$BOT2BOT_ROOT/
  protocol/
    BOT2BOT.md          # this document
  agents/
    <slug>/
      inbox/            # incoming *.msg.txt (unprocessed)
      outbox/           # processed messages (archive per agent)
      state.json        # deduplication state
  history/              # optional central append-only archive (JSONL)
```

Implementations may ship helper scripts under `implementations/` (e.g. PowerShell,
shell, Python). They are **not** part of the protocol — only this spec is normative.

## Agent slug rules

- Pattern: `^[a-z][a-z0-9_-]{0,31}$`
- Examples: `grok`, `claude`, `qwen`, `wa-ops`
- Registration creates `agents/<slug>/` if missing; must be idempotent

## Message file format

**Filename:**
```
<timestamp>_from_<sender>.msg.txt
```
- `timestamp`: local or UTC compact form `YYYYMMDDTHHMMSS` (no spaces)
- `sender`: sender slug

**Content (UTF-8 text):**
```
From: <sender>
To: <recipient>
Time: <ISO-8601 timestamp>
Subject: <one-line summary, optional but recommended>

<body — full message, may be multi-line>
```

Rules:
- Full message in the file — no pointers, no "see other file"
- Text only; no binary attachments in core protocol
- One logical message per file

## Send (any implementation)

To deliver a message to agent `grok` from `qwen`:

1. Ensure `agents/grok/inbox/` exists (register `grok` if not).
2. Write a new `.msg.txt` file into `agents/grok/inbox/` with the format above.
3. Do not overwrite existing inbox files — each send is a new file.

Atomic write recommended: write to a temp name in the same directory, then rename.

## Receive (agent responsibility)

Each agent **must** eventually read its own `agents/<self>/inbox/`:

1. List `*.msg.txt` in inbox.
2. Compare against `state.json` (`lastSeen` / processed list) to skip duplicates.
3. Process message content.
4. Mark processed:
   - **Preferred:** move file to `agents/<self>/outbox/`
   - **Alternative:** record filename or hash in `state.json`

Polling interval is host-defined (e.g. every 2 minutes in an agent loop).
Core protocol does not require polling — only that unprocessed files remain
until handled.

### Agents that cannot poll

The message still lands in inbox. A **delivery adapter** in the host environment
may wake the agent (file watcher, scheduled one-shot, webhook, human notification).
Delivery is documented in `DELIVERY.md`, not in core.

## state.json

```json
{
  "name": "grok",
  "registered": "2026-07-14T00:00:00+00:00",
  "lastSeen": null,
  "processed": []
}
```

- `processed`: optional list of inbox filenames already handled
- Implementations may use move-to-outbox instead of `processed`

## Optional central archive (history/)

Hosts may append a JSON line per message to `history/conversation.jsonl`:

```json
{"id":"<uuid>","ts":"<ISO-8601Z>","from":"<slug>","to":"<slug>","subject":"...","body":"...","in_reply_to":null,"status":"info","refs":[]}
```

This is **optional**. Per-agent outbox is sufficient for audit.
Extended JSON schema: see `MESSAGE_FORMAT.md` (legacy compatibility).

## Self-messages

`-To` and `-From` may be the same slug (reminder to self). File still goes to
`agents/<slug>/inbox/`.

## Multi-host / multi-machine

- Shared folder (SMB, sync drive) or replicated git tree: same layout under one `BOT2BOT_ROOT`
- No network API required in core
- Clock skew: use filename timestamp + `Time:` header; receivers sort by filename

## Universal participation

Any party with **write access** to `BOT2BOT_ROOT` may send messages by creating
files in `agents/<recipient>/inbox/`. No registration with a central server.
Registration only creates local mailbox directories for **receiving**.

Humans, scripts, CI jobs, and agents on other machines (via shared/synced folder)
use the same rules.

## Compliance checklist

A conforming implementation must:

1. Use slug rules for agent names
2. Write one file per message with required headers
3. Never delete unprocessed inbox messages without agent action
4. Support idempotent registration
5. Not require webagent, PowerShell, Windows, or any specific AI product

## Version

Protocol version: **1**  
Canonical path: `protocol/BOT2BOT.md`