#!/usr/bin/env python3
"""Patch live021r4 gemini MC-004 INVALID with targeted replay result."""
from __future__ import annotations

import json
import sys
from datetime import datetime, timezone
from pathlib import Path

_WEBAGENT = Path(__file__).resolve().parent.parent.parent / "webagent"
_SRC = _WEBAGENT / "src"
if str(_SRC) not in sys.path:
    sys.path.insert(0, str(_SRC))

from webagent.leader_calibration import compute_calibration_metrics, load_cases  # noqa: E402


def main() -> int:
    runs = _WEBAGENT / "data" / "leader_calibration" / "runs"
    main_path = runs / "live021r4.json"
    replay_path = runs / "live021r4-gemini-mc004.json"

    main = json.loads(main_path.read_text(encoding="utf-8"))
    replay = json.loads(replay_path.read_text(encoding="utf-8"))
    fix = next(
        r
        for r in replay["responses"]
        if r.get("participant") == "gemini"
        and r.get("case_id") == "MC-004"
        and r.get("ok")
    )
    fix = {k: fix[k] for k in ("participant", "case_id", "verdict", "reason", "raw_reply", "ok", "error")}

    patched = False
    for i, resp in enumerate(main["responses"]):
        if (
            resp.get("participant") == "gemini"
            and resp.get("case_id") == "MC-004"
            and not resp.get("ok")
        ):
            main["responses"][i] = fix
            patched = True
            break
    if not patched:
        print("ERROR: gemini MC-004 invalid entry not found", file=sys.stderr)
        return 1

    suite = load_cases(suite_id="moderator-v1")
    main["metrics"] = compute_calibration_metrics(suite, main["responses"])
    main["collected_at"] = datetime.now(timezone.utc).isoformat()
    main.setdefault("corrections", []).append(
        {
            "ts": datetime.now(timezone.utc).isoformat(),
            "case_id": "MC-004",
            "participant": "gemini",
            "source_run": "live021r4-gemini-mc004",
            "note": "Targeted replay replaced truncated relay INVALID",
        }
    )
    invalid = sum(1 for r in main["responses"] if not r.get("ok"))
    main_path.write_text(json.dumps(main, ensure_ascii=False, indent=2), encoding="utf-8")

    gemini_rank = next(x for x in main["metrics"]["rankings"] if x["participant"] == "gemini")
    print(
        f"patched ok invalid={invalid}/70 "
        f"gemini_n={gemini_rank['scored_cases']} "
        f"gemini_wt={gemini_rank['weighted_agreement']:.4f}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())