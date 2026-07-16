#!/usr/bin/env python3
"""Battleroyale (/br) — poll webbrains for methodology suggestions."""
from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path

_BOT2BOT_ROOT = Path(__file__).resolve().parent.parent
_WEBAGENT_SRC = _BOT2BOT_ROOT.parent / "webagent" / "src"
if str(_WEBAGENT_SRC) not in sys.path:
    sys.path.insert(0, str(_WEBAGENT_SRC))

from webagent.battleroyale import (  # noqa: E402
    DEFAULT_BR_TITLE,
    DEFAULT_MODERATOR_TOPIC,
    run_battleroyale,
)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Battleroyale (/br): collect methodology suggestions from webbrains",
    )
    parser.add_argument(
        "--topic",
        default=DEFAULT_MODERATOR_TOPIC,
        help="Question/topic for methodology suggestions",
    )
    parser.add_argument(
        "--title",
        default=DEFAULT_BR_TITLE,
        help="Short title shown in prompts and inbox subject",
    )
    parser.add_argument("--run-id", default="", help="Optional run id (default: random 8 hex)")
    parser.add_argument("--headed", action="store_true", help="Visible browser")
    parser.add_argument("--timeout", type=float, default=300.0)
    parser.add_argument("--retry-on-empty", action="store_true")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--no-inbox", action="store_true", help="Skip append_message to claude")
    args = parser.parse_args(argv)

    result = run_battleroyale(
        bot2bot_root=_BOT2BOT_ROOT,
        topic=args.topic,
        title=args.title,
        headless=not args.headed,
        timeout=args.timeout,
        retry_on_empty=args.retry_on_empty,
        dry_run=args.dry_run,
        post_inbox=not args.no_inbox,
        run_id=args.run_id or None,
    )
    print(result.report)
    return 0 if any(r.ok for r in result.replies) or args.dry_run else 1


if __name__ == "__main__":
    raise SystemExit(main())