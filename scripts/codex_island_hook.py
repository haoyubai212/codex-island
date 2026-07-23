#!/usr/bin/env python3
import fcntl
import json
import os
import sys
import time
from pathlib import Path


ROTATE_AT_BYTES = 5 * 1024 * 1024
ROTATED_KEEP_BYTES = 5 * 1024 * 1024


def trim_to_recent_lines(path: Path, max_bytes: int) -> None:
    size = path.stat().st_size
    if size <= max_bytes:
        return

    with path.open("rb+") as file:
        file.seek(-max_bytes, os.SEEK_END)
        tail = file.read()
        newline = tail.find(b"\n")
        if newline >= 0:
            tail = tail[newline + 1 :]
        file.seek(0)
        file.write(tail)
        file.truncate()


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
    rotated_file = events_dir / "events.jsonl.1"
    lock_file = events_dir / "events.lock"
    encoded_event = (
        json.dumps(event, ensure_ascii=False, separators=(",", ":")) + "\n"
    ).encode("utf-8")

    # 独立锁文件可跨 rename 持续协调并发 hook。当前文件达到 5 MB 时，
    # 保留一个最多 5 MB 的轮转文件，总占用稳定在约 10 MB 以内。
    with lock_file.open("a+b") as lock:
        fcntl.flock(lock.fileno(), fcntl.LOCK_EX)
        try:
            if events_file.exists() and events_file.stat().st_size >= ROTATE_AT_BYTES:
                os.replace(events_file, rotated_file)
                trim_to_recent_lines(rotated_file, ROTATED_KEEP_BYTES)

            with events_file.open("ab", buffering=0) as file:
                file.write(encoded_event)
        finally:
            fcntl.flock(lock.fileno(), fcntl.LOCK_UN)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
