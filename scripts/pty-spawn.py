#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.9"
# dependencies = []
# ///
"""Run a command under a pseudo-terminal and propagate its exit status.

The capability-gating suite needs a deterministic pty so the TTY-guarded
branches of sync-side-channels.sh are exercised. `script` has incompatible
BSD/util-linux flag forms, so this allocates the pty directly.

``pty.spawn`` returns an encoded wait status, so a child exiting 1 becomes 256
and ``sys.exit(256)`` truncates to 0 — the harness would report success for a
failed run. ``waitstatus_to_exitcode`` decodes it.

Usage:
    scripts/pty-spawn.py <command> [args...]
"""

import os
import pty
import sys

if len(sys.argv) < 2:
    print("usage: pty-spawn.py <command> [args...]", file=sys.stderr)
    sys.exit(2)

sys.exit(os.waitstatus_to_exitcode(pty.spawn(sys.argv[1:])))
