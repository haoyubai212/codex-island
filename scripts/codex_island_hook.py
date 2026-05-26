#!/usr/bin/env python3
import json
import sys
import time
from pathlib import Path


def main() -> int:
    event_name = sys.argv[1] if len(sys.argv) > 1 else ""
    raw = sys.stdin.read()

    try:
        payload = json.loads(raw) if raw.strip() else {}
    except json.JSONDecodeError:
        payload = {"raw": raw}

    if not isinstance(payload, dict):
        payload = {"payload": payload}

    event = dict(payload)
    event["event"] = event_name or event.get("hook_event_name") or ""
    event["timestamp"] = time.time()

    tool_input = event.get("tool_input")
    if isinstance(tool_input, dict) and isinstance(tool_input.get("command"), str):
        event["command"] = tool_input["command"]

    # Tool output can be very large; the island only needs lifecycle metadata.
    event.pop("tool_response", None)

    events_dir = Path.home() / ".codex-island"
    events_dir.mkdir(parents=True, exist_ok=True)
    events_file = events_dir / "events.jsonl"

    with events_file.open("a", encoding="utf-8") as file:
        file.write(json.dumps(event, ensure_ascii=False, separators=(",", ":")))
        file.write("\n")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
