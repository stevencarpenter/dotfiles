#!/usr/bin/python3
"""Run an agent-reap worker under a process-group watchdog.

macOS ships neither ``timeout`` nor ``gtimeout``, so the reap hooks use this as
their portable bound. The worker starts in its own session, and on expiry the
whole group is signalled TERM, then KILL after the grace period. agent-reap
separately bounds each tmux/ps subprocess it launches; this is the final
failsafe around the worker and every descendant.

Usage:
    run-reap-worker.py --label LABEL --timeout SECS --grace SECS -- CMD [ARG...]

Exit status is the worker's own, 124 on timeout, or 1 if it could not start.
Callers treat a nonzero status as "reap did not complete"; only the SessionEnd
hook acts on that, by leaving team state in place.

Runs under macOS's system /usr/bin/python3 (3.9): the hook must not depend on
uv or any interpreter installed by this repo. The shebang matches that
interpreter so a manual run hits the same runtime.
"""

import argparse
import os
import signal
import subprocess
import sys


def main() -> int:
    """Run the wrapped command under a process-group watchdog.

    Returns:
        The command's exit status, or 124 when the watchdog timed out and
        terminated the worker's process group.
    """
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--label", required=True, help="prefix for log messages")
    parser.add_argument("--timeout", type=int, required=True, help="seconds to wait")
    parser.add_argument("--grace", type=int, required=True, help="seconds after TERM")
    parser.add_argument("command", nargs=argparse.REMAINDER, help="-- CMD [ARG...]")
    args = parser.parse_args()

    command = args.command[1:] if args.command[:1] == ["--"] else args.command
    if not command:
        parser.error("no worker command given")

    try:
        process = subprocess.Popen(command, start_new_session=True)
    except Exception as error:
        print(f"{args.label}: could not run worker: {error}")
        return 1

    try:
        return process.wait(timeout=args.timeout)
    except subprocess.TimeoutExpired:
        print(
            f"{args.label}: timed out after {args.timeout}s; terminating worker group"
        )

    try:
        os.killpg(process.pid, signal.SIGTERM)
    except ProcessLookupError:
        pass
    try:
        process.wait(timeout=args.grace)
    except subprocess.TimeoutExpired:
        pass
    # The leader may exit after SIGTERM while descendants remain in the
    # session. Always signal the process group after the grace period rather
    # than using the leader's exit as a proxy for group termination.
    try:
        os.killpg(process.pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
    process.wait()
    return 124


if __name__ == "__main__":
    sys.exit(main())
