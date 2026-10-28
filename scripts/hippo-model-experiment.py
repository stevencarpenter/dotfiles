#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.12"
# dependencies = []
# ///
"""Unattended model x temperature x thinking experiment for hippo enrichment.

Replays the same recorded hippo requests (see ``hippo-model-eval.py record``)
against every variant in ``hippo-model-experiment.toml`` and writes a report
to decide from. ``start`` checks everything that needs you (models present,
cases recorded, sudo for power) while you are at the keyboard, then detaches
a worker under ``caffeinate`` that runs to completion on its own:

- Work is done in rounds: every variant finishes a round of cases before the
  next round starts, so stopping early still leaves a balanced comparison.
- Each finished case is appended to disk at once; ``resume`` skips them.
- A dropped oMLX connection is waited out (up to 15 minutes) and retried; a
  model that answers 404 is marked failed and the rest carry on.
- At the end it writes ``report.md``, ``summary.json`` and a blind side-by-side
  sample (``blind.md`` with the answer key in ``blind-key.json``), then posts a
  macOS notification.

Run files live in ``~/.local/share/hippo/model-eval/runs/<timestamp>/`` (0700),
because the cases hold real shell and agent transcripts.

Usage::

    scripts/hippo-model-experiment.py plan
    scripts/hippo-model-experiment.py start --power
    scripts/hippo-model-experiment.py status
    scripts/hippo-model-experiment.py stop | resume | report
"""

from __future__ import annotations

import argparse
import datetime as dt
import http.client
import importlib.util
import json
import os
import random
import re
import shutil
import signal
import subprocess
import sys
import time
import tomllib
import traceback
import urllib.request
from dataclasses import asdict, dataclass
from pathlib import Path
from types import ModuleType, SimpleNamespace
from typing import Any

type JsonDict = dict[str, Any]

HERE = Path(__file__).resolve().parent


def load_eval() -> ModuleType:
    """Load the sibling ``hippo-model-eval.py`` (hyphenated, so not importable).

    Returns:
        The evaluator module.

    Raises:
        RuntimeError: If Python cannot construct an import specification.
    """
    path = HERE / "hippo-model-eval.py"
    specification = importlib.util.spec_from_file_location("hippo_model_eval", path)
    if specification is None or specification.loader is None:
        raise RuntimeError(f"cannot import {path}")
    module = importlib.util.module_from_spec(specification)
    specification.loader.exec_module(module)
    return module


EVAL = load_eval()

MATRIX = HERE / "hippo-model-experiment.toml"
RUNS_DIR = EVAL.DEFAULT_DIR / "runs"
SAMPLE_HEADER = re.compile(
    r"\*\*\* Sampled system activity \((.+?)\) \(([\d.]+)ms elapsed\) \*\*\*"
)
SAMPLE_TIME_FORMAT = "%a %b %d %H:%M:%S %Y %z"
THINKING = ("asis", "on", "off")
SERVER_WAIT_S = 900
SERVER_POLL_S = 30
BLIND_CASES = 12
EXCERPT_CHARS = 1200


class Stopped(Exception):
    """Raised inside the worker when a stop was requested."""


@dataclass(frozen=True)
class Variant:
    """One model, temperature and thinking combination.

    Attributes:
        model: oMLX model ID.
        temperature: Forced temperature, or None to keep the recorded one.
        thinking: ``"asis"``, ``"on"`` or ``"off"``.
    """

    model: str
    temperature: float | None
    thinking: str

    @property
    def id(self) -> str:
        """Human-readable variant ID used in results and the report."""
        temp = "asis" if self.temperature is None else f"{self.temperature:g}"
        return f"{self.model} [temp={temp}, think={self.thinking}]"

    @property
    def slug(self) -> str:
        """Filesystem-safe form of ``id``."""
        return re.sub(r"[^A-Za-z0-9._-]+", "_", self.id).strip("_")


def expand_matrix(matrix: JsonDict) -> list[Variant]:
    """Expand the matrix into variants, applying per-model overrides.

    Args:
        matrix: Parsed matrix TOML.

    Returns:
        Variants in model order.

    Raises:
        ValueError: On an unknown thinking value or a model without an ID.
    """
    variants = []
    for model in matrix.get("models", []):
        if not model.get("id"):
            raise ValueError("every [[models]] entry needs an id")
        temperatures = model.get("temperatures", matrix.get("temperatures", ["asis"]))
        thinking = model.get("thinking", matrix.get("thinking", ["asis"]))
        for temperature in temperatures:
            for think in thinking:
                if think not in THINKING:
                    raise ValueError(f"thinking must be one of {THINKING}: {think!r}")
                variants.append(
                    Variant(
                        model["id"],
                        None if temperature == "asis" else float(temperature),
                        think,
                    )
                )
    return variants


def server_models(base_url: str, api_key: str, timeout: float = 5.0) -> set[str] | None:
    """List every model ID the inference server knows.

    Args:
        base_url: Base URL ending in ``/v1``.
        api_key: Bearer token.
        timeout: Request timeout in seconds.

    Returns:
        Model IDs, or None when the server is unreachable or answers badly.
    """
    request = urllib.request.Request(
        base_url.rstrip("/") + "/models",
        headers={"Authorization": f"Bearer {api_key}"},
    )
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            body = json.load(response)
    except (OSError, ValueError, http.client.HTTPException):
        # HTTPException covers a truncated body (IncompleteRead), so recovery
        # polling keeps waiting instead of failing the run.
        return None
    data = body.get("data") if isinstance(body, dict) else None
    if not isinstance(data, list):
        return None
    return {entry["id"] for entry in data if isinstance(entry, dict) and "id" in entry}


def production_content(response: Any) -> str:
    """Extract the assistant content hippo got back when the case was recorded.

    Args:
        response: Recorded response: parsed JSON, or SSE text when streamed.

    Returns:
        The content with any ``<think>`` block removed; empty if unavailable.
    """
    content = ""
    if isinstance(response, dict):
        try:
            content = response["choices"][0]["message"].get("content") or ""
        except (KeyError, IndexError, TypeError, AttributeError):
            content = ""
    elif isinstance(response, str):
        parts = []
        for line in response.splitlines():
            payload = line.removeprefix("data:").strip()
            if not line.startswith("data:") or payload == "[DONE]":
                continue
            try:
                delta = json.loads(payload)["choices"][0].get("delta") or {}
            except (ValueError, KeyError, IndexError, TypeError):
                continue
            parts.append(delta.get("content") or "")
        content = "".join(parts)
    if "</think>" in content:
        content = content.split("</think>", 1)[1]
    return content.strip()


def parse_timed_power(text: str) -> list[tuple[float, float, float]]:
    """Parse powermetrics output into timestamped samples.

    Args:
        text: Raw ``powermetrics`` text output.

    Returns:
        ``(end_epoch_seconds, interval_seconds, watts)`` per sample that has
        both a parseable header and a combined-power line.
    """
    headers = list(SAMPLE_HEADER.finditer(text))
    samples = []
    for index, header in enumerate(headers):
        end = headers[index + 1].start() if index + 1 < len(headers) else len(text)
        power = EVAL.POWER_LINE.search(text, header.end(), end)
        if not power:
            continue
        try:
            stamp = dt.datetime.strptime(header.group(1), SAMPLE_TIME_FORMAT)
        except ValueError:
            continue
        samples.append(
            (
                stamp.timestamp(),
                float(header.group(2)) / 1000,
                int(power.group(1)) / 1000,
            )
        )
    return samples


def variant_power(run_dir: Path) -> dict[str, JsonDict]:
    """Attribute sampled power to variants by their recorded time windows.

    Args:
        run_dir: Experiment run directory.

    Returns:
        Per variant ID: mean ``watts`` and total ``joules`` while it ran.
    """
    power_file, windows_file = run_dir / "powermetrics.txt", run_dir / "windows.jsonl"
    if not power_file.exists() or not windows_file.exists():
        return {}
    samples = parse_timed_power(power_file.read_text(errors="replace"))
    totals: dict[str, list[float]] = {}
    for window in EVAL.read_jsonl(windows_file):
        energy_seconds = totals.setdefault(window["variant"], [0.0, 0.0])
        for end, seconds, watts in samples:
            # Charge only the part of the sample interval inside the window, so
            # warm-up or the next variant never leaks across a boundary.
            overlap = min(end, window["end"]) - max(end - seconds, window["start"])
            if overlap > 0:
                energy_seconds[0] += watts * overlap
                energy_seconds[1] += overlap
    return {
        variant: {"watts": energy / seconds, "joules": energy}
        for variant, (energy, seconds) in totals.items()
        if seconds
    }


# ── run-directory state ───────────────────────────────────────────────────


def latest_run() -> Path | None:
    """Return the newest run directory, if any.

    Returns:
        Path of the most recent run, or None.
    """
    if not RUNS_DIR.is_dir():
        return None
    runs = sorted(path for path in RUNS_DIR.iterdir() if path.is_dir())
    return runs[-1] if runs else None


def resolve_run(arg: Path | None) -> Path:
    """Pick the run named on the command line, or the latest one.

    Args:
        arg: ``--run`` value, if given.

    Returns:
        The run directory.

    Raises:
        SystemExit: If there is no run to act on.
    """
    run = arg or latest_run()
    if run is None or not (run / "config.json").exists():
        raise SystemExit(f"no experiment run found under {RUNS_DIR}")
    return run


def write_json(path: Path, value: Any) -> None:
    """Atomically write JSON, readable only by the owner.

    Args:
        path: Destination file.
        value: JSON-serializable value.
    """
    tmp = path.with_suffix(path.suffix + ".tmp")
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w", encoding="utf-8") as handle:
        json.dump(value, handle, indent=2)
    tmp.replace(path)


def load_run(run_dir: Path) -> tuple[JsonDict, list[Variant], list[JsonDict]]:
    """Load a run's config, variants and cases.

    Args:
        run_dir: Experiment run directory.

    Returns:
        ``(config, variants, cases)``.
    """
    config = json.loads((run_dir / "config.json").read_text(encoding="utf-8"))
    variants = [Variant(**variant) for variant in config["variants"]]
    return config, variants, EVAL.read_jsonl(run_dir / "cases.jsonl")


def completed(run_dir: Path, variants: list[Variant]) -> dict[str, set[str]]:
    """Find the cases each variant already finished without error.

    Args:
        run_dir: Experiment run directory.
        variants: The run's variants.

    Returns:
        Case IDs per variant slug.
    """
    done: dict[str, set[str]] = {}
    for variant in variants:
        path = run_dir / "results" / f"{variant.slug}.jsonl"
        rows = EVAL.read_jsonl(path) if path.exists() else []
        done[variant.slug] = {row["case"] for row in rows if "error" not in row}
    return done


def worker_pid(path: Path) -> int | None:
    """Return the PID in a worker PID file if that process is still the worker.

    The worker removes its PID file on exit, but a crash can leave one behind
    and the OS can reuse the PID, so the process's command line must name this
    script before the PID is trusted.

    Args:
        path: ``worker.pid`` of a run.

    Returns:
        The live worker's PID, or None.
    """
    try:
        pid = int(path.read_text().strip())
        os.kill(pid, 0)
    except (OSError, ValueError):
        return None
    command = subprocess.run(
        ["ps", "-p", str(pid), "-o", "command="],
        capture_output=True,
        text=True,
        check=False,
    ).stdout
    return pid if Path(__file__).name in command else None


def notify(title: str, message: str) -> None:
    """Post a macOS notification; silently does nothing elsewhere.

    Args:
        title: Notification title.
        message: Notification body.
    """
    if sys.platform == "darwin" and shutil.which("osascript"):
        script = (
            f"display notification {json.dumps(message)} with title {json.dumps(title)}"
        )
        subprocess.run(["osascript", "-e", script], check=False)


# ── power ─────────────────────────────────────────────────────────────────


def start_power(run_dir: Path) -> None:
    """Start one ``powermetrics`` for the whole run, detached from the shell.

    Samples carry wall-clock timestamps, so the report attributes them to
    variants afterwards; nothing needs sudo again once this has started.

    Args:
        run_dir: Experiment run directory.

    Raises:
        RuntimeError: If powermetrics exits immediately (usually no sudo).
    """
    with open(run_dir / "powermetrics.txt", "a", encoding="utf-8") as out:
        proc = subprocess.Popen(
            [
                "sudo",
                "-n",
                "powermetrics",
                "--samplers",
                "cpu_power,gpu_power",
                "-i",
                "1000",
            ],
            stdin=subprocess.DEVNULL,
            stdout=out,
            stderr=subprocess.STDOUT,
            start_new_session=True,
        )
    time.sleep(1.5)
    if proc.poll() is not None:
        raise RuntimeError("powermetrics exited at once; check sudo access")
    (run_dir / "power.pid").write_text(str(proc.pid))


def stop_power(run_dir: Path) -> None:
    """Stop the run's powermetrics, if one is running.

    sudo keeps the invoking user's real UID, so the user may signal it, and it
    relays the signal to powermetrics.

    Args:
        run_dir: Experiment run directory.
    """
    pid_file = run_dir / "power.pid"
    if not pid_file.exists():
        return
    try:
        os.kill(int(pid_file.read_text().strip()), signal.SIGTERM)
    except (OSError, ValueError):
        pass
    pid_file.unlink(missing_ok=True)


# ── worker ────────────────────────────────────────────────────────────────


class Progress:
    """Keeps ``status.json`` current for ``status`` and for a returning human."""

    def __init__(self, run_dir: Path, total: int, done: int) -> None:
        """Initialize progress tracking.

        Args:
            run_dir: Experiment run directory.
            total: Total variant x case calls in the run.
            done: Calls already finished (from earlier sessions).
        """
        self.path = run_dir / "status.json"
        self.total, self.done, self.errors = total, done, 0
        self.session_start, self.session_done = time.time(), done
        self.started = dt.datetime.now().astimezone().isoformat(timespec="seconds")
        self.current = ""
        self.write("running")

    def step(self, variant: str, error: bool) -> None:
        """Record one finished call.

        Args:
            variant: Variant ID that ran.
            error: Whether the call ended in an error.
        """
        self.current = variant
        if error:
            self.errors += 1
        else:
            self.done += 1
        self.write("running")

    def write(self, state: str) -> None:
        """Write the status file.

        Args:
            state: ``running``, ``done``, ``stopped`` or ``failed``.
        """
        now = time.time()
        rate = (self.done - self.session_done) / max(now - self.session_start, 1e-9)
        eta = None
        if state == "running" and rate > 0:
            eta = dt.datetime.fromtimestamp(
                now + (self.total - self.done) / rate
            ).astimezone()
        write_json(
            self.path,
            {
                "state": state,
                "started": self.started,
                "updated": dt.datetime.now().astimezone().isoformat(timespec="seconds"),
                "done": self.done,
                "total": self.total,
                "errors_this_session": self.errors,
                "current": self.current,
                "eta": eta.isoformat(timespec="minutes") if eta else None,
                "pid": os.getpid(),
            },
        )


def wait_for_server(base_url: str, api_key: str, stop: dict[str, bool]) -> bool:
    """Poll the inference server until it answers or the wait budget runs out.

    Args:
        base_url: Base URL ending in ``/v1``.
        api_key: Bearer token.
        stop: Shared stop flag set by the signal handler.

    Returns:
        True if the server answered.
    """
    deadline = time.monotonic() + SERVER_WAIT_S
    while time.monotonic() < deadline and not stop["flag"]:
        if server_models(base_url, api_key) is not None:
            return True
        time.sleep(SERVER_POLL_S)
    return False


def run_variant_case(
    base_url: str, case: JsonDict, variant: Variant, ns: SimpleNamespace, stop: dict
) -> JsonDict:
    """Run one case for one variant, retrying once after a transport failure.

    HTTP errors are answers from the server and are not retried; connection
    failures and timeouts wait for the server to come back, then retry.

    Args:
        base_url: Base URL ending in ``/v1``.
        case: Recorded case.
        variant: Variant to run.
        ns: Request settings (thinking, temperature, api_key, timeout).
        stop: Shared stop flag.

    Returns:
        The result row, with ``model`` set to the variant ID.
    """
    result: JsonDict = {}
    for attempt in range(2):
        result = EVAL.run_case(base_url, case, variant.model, ns)
        result["model"] = variant.id
        error = result.get("error")
        if not error or error.startswith("HTTP Error") or attempt:
            break
        print(f"   transport error ({error}); waiting for oMLX", flush=True)
        wait_for_server(base_url, ns.api_key, stop)
        if stop["flag"]:
            # A stop during recovery must not start another (possibly long) call.
            break
    return result


def run_worker(run_dir: Path, api_key: str | None = None) -> int:
    """Execute (or continue) an experiment run until done or stopped.

    Args:
        run_dir: Experiment run directory.
        api_key: oMLX bearer token; defaults to ``OMLX_API_KEY`` or ``omlx``.
            It is never written into the run directory.

    Returns:
        Process exit code.
    """
    config, variants, cases = load_run(run_dir)
    (run_dir / "worker.pid").write_text(str(os.getpid()))
    stop = {"flag": False}

    def request_stop(_signum: int, _frame: Any) -> None:
        stop["flag"] = True

    for sig in (signal.SIGTERM, signal.SIGHUP, signal.SIGINT):
        signal.signal(sig, request_stop)

    base_url = config["base_url"].rstrip("/")
    api_key = api_key or os.environ.get("OMLX_API_KEY", "omlx")
    done = completed(run_dir, variants)
    failed: set[str] = set()
    progress = Progress(
        run_dir, len(variants) * len(cases), sum(len(ids) for ids in done.values())
    )
    size = max(int(config["round_size"]), 1)
    rounds = [cases[i : i + size] for i in range(0, len(cases), size)]
    models = list(dict.fromkeys(variant.model for variant in variants))
    state = "failed"
    try:
        for number, round_cases in enumerate(rounds, 1):
            for model in models:
                warmed = False
                for variant in (v for v in variants if v.model == model):
                    if variant.model in failed:
                        continue
                    todo = [c for c in round_cases if c["id"] not in done[variant.slug]]
                    if not todo:
                        continue
                    ns = SimpleNamespace(
                        thinking=variant.thinking,
                        temperature=variant.temperature,
                        api_key=api_key,
                        timeout=config["timeout"],
                    )
                    print(f"round {number}/{len(rounds)}: {variant.id}", flush=True)
                    if not warmed:
                        # Untimed: absorbs the model load after a switch.
                        warm = run_variant_case(base_url, todo[0], variant, ns, stop)
                        warmed = True
                        if warm.get("error", "").startswith("HTTP Error 404"):
                            print(f"   {model} not served; skipping it", flush=True)
                            failed.add(model)
                            EVAL.append_jsonl(
                                run_dir / "results" / f"{variant.slug}.jsonl", warm
                            )
                            continue
                    start = time.time()
                    try:
                        for case in todo:
                            if stop["flag"]:
                                raise Stopped
                            result = run_variant_case(base_url, case, variant, ns, stop)
                            EVAL.append_jsonl(
                                run_dir / "results" / f"{variant.slug}.jsonl", result
                            )
                            if "error" not in result:
                                done[variant.slug].add(case["id"])
                            progress.step(variant.id, "error" in result)
                    finally:
                        # Persist the window even on stop, so the cases already
                        # saved from it keep their energy in the report.
                        EVAL.append_jsonl(
                            run_dir / "windows.jsonl",
                            {"variant": variant.id, "start": start, "end": time.time()},
                        )
        state = "done"
    except Stopped:
        state = "stopped"
    except Exception:
        traceback.print_exc()
    finally:
        stop_power(run_dir)
        (run_dir / "worker.pid").unlink(missing_ok=True)
        progress.write(state)
        try:
            report = write_report(run_dir)
            print(f"report: {report}", flush=True)
        except Exception:
            traceback.print_exc()
        notify("hippo experiment", f"{state}: {progress.done}/{progress.total} calls")
    return 0 if state == "done" else 1


def spawn_worker(run_dir: Path, api_key: str) -> int:
    """Launch the worker detached, under ``caffeinate`` when available.

    Args:
        run_dir: Experiment run directory.
        api_key: oMLX bearer token, handed over in the environment so it is
            neither on the command line nor in the run directory.

    Returns:
        PID of the launched process.
    """
    # The script's own uv shebang, not sys.executable: uv's ephemeral script
    # environment is not guaranteed to outlive this launcher.
    command = [str(Path(__file__).resolve()), "worker", "--run", str(run_dir)]
    if shutil.which("caffeinate"):
        # -i idle sleep, -m disk sleep, -s system sleep while on AC power.
        command = ["caffeinate", "-ims", *command]
    with open(run_dir / "run.log", "ab") as log:
        proc = subprocess.Popen(
            command,
            stdin=subprocess.DEVNULL,
            stdout=log,
            stderr=subprocess.STDOUT,
            start_new_session=True,
            env={**os.environ, "OMLX_API_KEY": api_key},
        )
    return proc.pid


# ── report ────────────────────────────────────────────────────────────────

COLUMNS = [
    ("model", "s"),
    ("cases", "d"),
    ("errors", "d"),
    ("json_valid", ".1%"),
    ("truncated", "d"),
    ("p50_s", ".1f"),
    ("p95_s", ".1f"),
    ("completion_tokens", ".0f"),
    ("reasoning_chars", ".0f"),
    ("key_agree", ".2f"),
    ("value_agree", ".2f"),
    ("watts", ".1f"),
    ("joules_per_case", ".0f"),
]


def excerpt(case: JsonDict) -> str:
    """Return the tail of the last user message, for context in the sample.

    Args:
        case: Recorded case.

    Returns:
        Up to ``EXCERPT_CHARS`` characters of input.
    """
    messages = case["request"].get("messages") or []
    users = [m for m in messages if isinstance(m, dict) and m.get("role") == "user"]
    content = users[-1].get("content") if users else ""
    text = content if isinstance(content, str) else json.dumps(content)
    return text[-EXCERPT_CHARS:]


def write_blind(run_dir: Path, cases: list[JsonDict], rows: list[JsonDict]) -> None:
    """Write a blind side-by-side sample and its answer key.

    Args:
        run_dir: Experiment run directory.
        cases: Recorded cases.
        rows: All result rows.
    """
    outputs: dict[str, dict[str, str]] = {}
    for row in rows:
        if "error" not in row:
            outputs.setdefault(row["case"], {})[row["model"]] = row.get("content") or ""
    # Variants that produced nothing (e.g. a 404 model) must not empty the sample.
    variants = {row["model"] for row in rows if "error" not in row}
    # A case qualifies only with recorded outputs; with no successes at all
    # (every call failed, or a stop before the first) the sample is empty.
    complete = [
        c for c in cases if c["id"] in outputs and set(outputs[c["id"]]) >= variants
    ]
    rng = random.Random(0)
    chosen = rng.sample(complete, min(BLIND_CASES, len(complete)))
    key: dict[str, dict[str, str]] = {}
    lines = [
        "# Blind sample",
        "",
        "Outputs are shuffled per case. Pick the best (and any unacceptable) letters",
        "before opening `blind-key.json`.",
    ]
    for case in chosen:
        lines += ["", f"## Case {case['id']}", "", "Input (tail):", "", "```"]
        lines += [excerpt(case), "```", "", "**Production (reference)**", "", "```"]
        lines += [production_content(case.get("response")), "```"]
        shuffled = list(outputs[case["id"]].items())
        rng.shuffle(shuffled)
        key[case["id"]] = {}
        for index, (variant, content) in enumerate(shuffled):
            letter = chr(ord("A") + index)
            key[case["id"]][letter] = variant
            lines += ["", f"**{letter}**", "", "```", content, "```"]
    (run_dir / "blind.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
    write_json(run_dir / "blind-key.json", key)


def write_report(run_dir: Path) -> Path:
    """Write ``report.md``, ``summary.json`` and the blind sample.

    Args:
        run_dir: Experiment run directory.

    Returns:
        Path of ``report.md``.
    """
    _config, variants, cases = load_run(run_dir)
    rows = [
        row
        for variant in variants
        if (path := run_dir / "results" / f"{variant.slug}.jsonl").exists()
        for row in EVAL.read_jsonl(path)
    ]
    reference = {
        case["id"]: EVAL.parse_json_content(production_content(case.get("response")))
        for case in cases
    }
    summaries = EVAL.summarize(rows, None, reference)
    power = variant_power(run_dir)
    for summary in summaries:
        if summary["model"] in power:
            ok = summary["cases"] - summary["errors"]
            summary["watts"] = power[summary["model"]]["watts"]
            summary["joules_per_case"] = power[summary["model"]]["joules"] / max(ok, 1)
    summaries.sort(key=lambda s: -(s.get("value_agree") or -1))
    status_file = run_dir / "status.json"
    status = json.loads(status_file.read_text()) if status_file.exists() else {}
    lines = [
        "# Hippo enrichment experiment",
        "",
        f"Run `{run_dir.name}`: state {status.get('state', '?')}, "
        f"{status.get('done', '?')}/{status.get('total', '?')} calls, "
        f"{len(cases)} cases, {len(variants)} variants.",
        "",
        "| " + " | ".join("variant" if n == "model" else n for n, _ in COLUMNS) + " |",
        "|" + "---|" * len(COLUMNS),
    ]
    for summary in summaries:
        cells = [EVAL.fmt(summary.get(name), spec) for name, spec in COLUMNS]
        lines.append("| " + " | ".join(cells) + " |")
    lines += [
        "",
        "How to read it:",
        "",
        "- `key_agree`/`value_agree` compare each output with what production "
        "returned when the case was recorded. They measure closeness to the "
        "current setup, not correctness: judge quality from `blind.md`.",
        "- `json_valid` below 100% or any `truncated` rows disqualify a variant "
        "for enrichment unless hippo tolerates them.",
        "- `think=off` rows should show `reasoning_chars` near 0. If they do not, "
        "the server ignored `chat_template_kwargs.enable_thinking` and those rows "
        "are really thinking-on.",
        "- Latency and power include everything else the Mac did meanwhile (your "
        "workday, live hippo traffic). Compare variants within this run, not "
        "against other runs.",
    ]
    report = run_dir / "report.md"
    report.write_text("\n".join(lines) + "\n", encoding="utf-8")
    write_json(run_dir / "summary.json", summaries)
    write_blind(run_dir, cases, rows)
    return report


# ── commands ──────────────────────────────────────────────────────────────


def preflight(
    args: argparse.Namespace,
) -> tuple[list[Variant], list[JsonDict], list[str]]:
    """Expand the matrix, load cases, and find models oMLX does not serve.

    Args:
        args: Parsed CLI arguments.

    Returns:
        ``(variants, cases, missing_models)``.

    Raises:
        SystemExit: If cases are missing or the server is unreachable.
    """
    matrix = tomllib.loads(args.matrix.read_text(encoding="utf-8"))
    variants = expand_matrix(matrix)
    if not args.cases.exists():
        raise SystemExit(
            f"no cases at {args.cases}; record them first:\n"
            "  scripts/hippo-model-eval.py record --switch-brain --limit 200"
        )
    limit = args.limit or int(matrix.get("cases", 0)) or None
    cases = EVAL.read_jsonl(args.cases)[:limit]
    available = server_models(args.base_url, args.api_key)
    if available is None:
        raise SystemExit(f"oMLX is not answering at {args.base_url}/models")
    missing = sorted({v.model for v in variants} - available)
    args.round_size = int(matrix.get("round_size", 25))
    return variants, cases, missing


def cmd_plan(args: argparse.Namespace) -> int:
    """Show what a run would do and whether it can start.

    Args:
        args: Parsed CLI arguments.

    Returns:
        0 when everything needed is present.
    """
    variants, cases, missing = preflight(args)
    for variant in variants:
        mark = "MISSING" if variant.model in missing else "ok"
        print(f"{mark:8} {variant.id}")
    calls = len(variants) * len(cases)
    print(f"\n{len(variants)} variants x {len(cases)} cases = {calls} calls")
    print(
        "rough duration at 5-15 s per call: "
        f"{calls * 5 / 3600:.1f}-{calls * 15 / 3600:.1f} h"
    )
    if missing:
        print("\nnot served by oMLX: " + ", ".join(missing))
    return 1 if missing or not cases else 0


def cmd_start(args: argparse.Namespace) -> int:
    """Check everything, then launch the detached worker.

    Args:
        args: Parsed CLI arguments.

    Returns:
        Process exit code.
    """
    variants, cases, missing = preflight(args)
    if not cases:
        print("no cases to run", file=sys.stderr)
        return 1
    if missing:
        print("not served by oMLX: " + ", ".join(missing), file=sys.stderr)
        if not args.skip_missing:
            print("download/convert them, or pass --skip-missing", file=sys.stderr)
            return 1
        variants = [v for v in variants if v.model not in missing]
    run_dir = EVAL.private_dir(RUNS_DIR / time.strftime("%Y%m%d-%H%M%S"))
    write_json(
        run_dir / "config.json",
        {
            "variants": [asdict(v) for v in variants],
            "round_size": args.round_size,
            "base_url": args.base_url,
            "timeout": args.timeout,
            "matrix": str(args.matrix),
            "skipped_models": missing,
            "power": args.power,
        },
    )
    for case in cases:
        EVAL.append_jsonl(run_dir / "cases.jsonl", case)
    if args.power:
        subprocess.run(["sudo", "-v"], check=True)
        start_power(run_dir)
    if args.foreground:
        return run_worker(run_dir, args.api_key)
    pid = spawn_worker(run_dir, args.api_key)
    print(
        f"started {len(variants)} variants x {len(cases)} cases (pid {pid})\n"
        f"run dir: {run_dir}\n"
        "check:   just hippo-experiment status\n"
        "stop:    just hippo-experiment stop   (resume later with resume)"
    )
    return 0


def cmd_worker(args: argparse.Namespace) -> int:
    """Internal: the detached worker's entry point.

    Args:
        args: Parsed CLI arguments.

    Returns:
        Process exit code.
    """
    return run_worker(resolve_run(args.run))


def cmd_status(args: argparse.Namespace) -> int:
    """Print a run's progress.

    Args:
        args: Parsed CLI arguments.

    Returns:
        Process exit code.
    """
    run_dir = resolve_run(args.run)
    status_file = run_dir / "status.json"
    status = json.loads(status_file.read_text()) if status_file.exists() else {}
    alive = worker_pid(run_dir / "worker.pid") is not None
    print(f"run:     {run_dir}")
    print(
        f"state:   {status.get('state', 'starting')}{'' if alive else ' (no worker running)'}"
    )
    print(f"done:    {status.get('done', 0)}/{status.get('total', '?')} calls")
    print(f"current: {status.get('current') or '-'}")
    print(f"eta:     {status.get('eta') or '-'}")
    if (run_dir / "report.md").exists():
        print(f"report:  {run_dir / 'report.md'}")
    return 0


def cmd_stop(args: argparse.Namespace) -> int:
    """Ask a running worker to stop after its current call.

    Args:
        args: Parsed CLI arguments.

    Returns:
        Process exit code.
    """
    run_dir = resolve_run(args.run)
    pid = worker_pid(run_dir / "worker.pid")
    if pid is None:
        print("no worker running", file=sys.stderr)
        return 1
    os.kill(pid, signal.SIGTERM)
    print("stop requested; the worker finishes its current call and writes the report")
    return 0


def cmd_resume(args: argparse.Namespace) -> int:
    """Relaunch the worker for an unfinished run; finished cases are skipped.

    Args:
        args: Parsed CLI arguments.

    Returns:
        Process exit code.
    """
    run_dir = resolve_run(args.run)
    if worker_pid(run_dir / "worker.pid") is not None:
        print("worker already running", file=sys.stderr)
        return 1
    config = json.loads((run_dir / "config.json").read_text(encoding="utf-8"))
    if config.get("power"):
        # Sampling follows the run, not the resume flags: a resumed half with
        # no samples would still count in the joules-per-case denominator.
        print("this run samples power; sudo is needed to restart powermetrics")
        subprocess.run(["sudo", "-v"], check=True)
        start_power(run_dir)
    print(f"resumed (pid {spawn_worker(run_dir, args.api_key)}): {run_dir}")
    return 0


def cmd_report(args: argparse.Namespace) -> int:
    """(Re)write a run's report from whatever has finished so far.

    Args:
        args: Parsed CLI arguments.

    Returns:
        Process exit code.
    """
    print(write_report(resolve_run(args.run)))
    return 0


def parser() -> argparse.ArgumentParser:
    """Build the command-line parser.

    Returns:
        Configured argument parser.
    """
    root = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    sub = root.add_subparsers(dest="command", required=True)

    def plan_args(command: argparse.ArgumentParser) -> None:
        command.add_argument("--matrix", type=Path, default=MATRIX)
        command.add_argument(
            "--cases", type=Path, default=EVAL.DEFAULT_DIR / "cases.jsonl"
        )
        command.add_argument(
            "--limit", type=int, default=0, help="override matrix cases"
        )
        command.add_argument("--base-url", default=EVAL.DEFAULT_UPSTREAM + "/v1")
        command.add_argument(
            "--api-key", default=os.environ.get("OMLX_API_KEY", "omlx")
        )
        command.add_argument("--timeout", type=float, default=300.0)

    plan = sub.add_parser("plan", help="list variants and check models are served")
    plan_args(plan)
    plan.set_defaults(func=cmd_plan)

    start = sub.add_parser("start", help="check, then run detached until done")
    plan_args(start)
    start.add_argument(
        "--power", action="store_true", help="sample powermetrics (sudo)"
    )
    start.add_argument("--skip-missing", action="store_true")
    start.add_argument("--foreground", action="store_true", help="do not detach")
    start.set_defaults(func=cmd_start)

    for name, func, text in (
        ("status", cmd_status, "show progress"),
        ("stop", cmd_stop, "stop after the current call"),
        ("resume", cmd_resume, "continue an unfinished run"),
        ("report", cmd_report, "rewrite the report from finished calls"),
        ("worker", cmd_worker, "internal: the detached worker"),
    ):
        command = sub.add_parser(name, help=text)
        command.add_argument("--run", type=Path, help="run directory (default: latest)")
        if name == "resume":
            command.add_argument(
                "--api-key", default=os.environ.get("OMLX_API_KEY", "omlx")
            )
        command.set_defaults(func=func)
    return root


def main(argv: list[str] | None = None) -> int:
    """Entry point.

    Args:
        argv: Arguments, defaulting to ``sys.argv[1:]``.

    Returns:
        Process exit code.
    """
    args = parser().parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
