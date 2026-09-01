#!/usr/bin/env python3
"""log_pair.py — append one blind-vs-context paired-review record as JSONL.

Reads a JSON object from a file argument (or stdin), stamps recorded_at,
and appends it as one line to ~/.local/share/blind-review/pairs.jsonl.
Part of the blind-review PoC; the pair log is the eval dataset for whether
context-blind review surfaces different findings than status-quo review.
"""

from __future__ import annotations

import datetime
import json
import sys
from pathlib import Path

LOG = Path.home() / ".local" / "share" / "blind-review" / "pairs.jsonl"


def main() -> int:
    raw = Path(sys.argv[1]).read_text() if len(sys.argv) > 1 else sys.stdin.read()
    record = json.loads(raw)
    record.setdefault(
        "recorded_at",
        datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds"),
    )
    record.setdefault("poc", True)
    LOG.parent.mkdir(parents=True, exist_ok=True)
    with LOG.open("a", encoding="utf-8") as fh:
        fh.write(json.dumps(record, ensure_ascii=False) + "\n")
    print(f"logged pair record -> {LOG}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
