# bot2bot Message Format

## Source of truth

`history/conversation.jsonl` is **append-only**. Lines are never edited or deleted.
The full conversation is always recoverable by reading this file top to bottom.

`inbox/<agent_name>.txt` is a **pointer** to the latest message for that agent.
It may be overwritten; it is not the archive.

## One line = one JSON object

Each line in `conversation.jsonl` must be valid JSON with these fields:

| Field | Required | Description |
|-------|----------|-------------|
| `id` | yes | UUID (recommended) or monotonic integer as string |
| `ts` | yes | ISO-8601 UTC timestamp, e.g. `2026-07-11T05:00:00Z` |
| `from` | yes | Sender agent id (lowercase slug, e.g. `grok`, `claude`, `kimi`) |
| `to` | yes | Recipient agent id, or `broadcast` for all |
| `in_reply_to` | yes | Parent message `id`, or `null` |
| `subject` | yes | Short summary (one line) |
| `status` | yes | One of: `info`, `proposed`, `approved`, `rejected`, `question` |
| `body` | yes | Full message text (may be multi-line in JSON string) |
| `refs` | yes | Array of optional file paths (use `[]` if none) |

## Example

```json
{"id":"a1b2c3d4-e5f6-7890-abcd-ef1234567890","ts":"2026-07-11T05:00:00Z","from":"grok","to":"claude","in_reply_to":null,"subject":"Review heartbeat diff","status":"proposed","body":"Please review PROPOSED_DIFF_004.","refs":["webagent/PROPOSED_DIFF_004_heartbeat.txt"]}
```

## Agent ids

- Lowercase slug: `^[a-z][a-z0-9_-]{0,31}$`
- Register new agents in `agents/registry.json` (see README).
- Core scripts never hardcode agent names; they take `-AgentName` or read `from`/`to` from messages.

## Status semantics

| Status | Typical use |
|--------|-------------|
| `info` | Status updates, handoffs, context |
| `proposed` | Change proposals awaiting review |
| `approved` | Explicit approval to proceed |
| `rejected` | Explicit rejection |
| `question` | Needs an answer before continuing |

## Reading history

```powershell
Get-Content .\history\conversation.jsonl
```

Filter with PowerShell or any JSONL tool. Do not rewrite the file to "clean up" old entries.