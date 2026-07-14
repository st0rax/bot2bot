#!/usr/bin/env sh
# Reference implementation: send message (protocol v1)
# Usage: send.sh <to> <from> "message text"
set -e
TO="${1:?to required}"
FROM="${2:?from required}"
MSG="${3:?message required}"
ROOT="${BOT2BOT_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
INBOX="$ROOT/agents/$TO/inbox"
if [ ! -d "$INBOX" ]; then
  echo "Agent '$TO' not registered. Register first." >&2
  exit 1
fi
TS=$(date -u +%Y%m%dT%H%M%S)
FILE="$INBOX/${TS}_from_${FROM}.msg.txt"
TIME=$(date -Iseconds)
cat > "$FILE" <<EOF
From: $FROM
To: $TO
Time: $TIME

$MSG
EOF
echo "Message to '$TO': $FILE"