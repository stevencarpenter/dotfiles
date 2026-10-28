#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.12"
# dependencies = []
# ///
"""A/B evaluation of hippo enrichment models against real recorded requests.

Hippo's enrichment prompt and schema live in the hippo repository, so this tool
does not reimplement them. It records the exact chat-completion requests the
brain sends to oMLX, then replays them against each candidate model and compares
the outputs. Recordings hold real shell and agent transcripts, so they are
written 0600 under ``~/.local/share/hippo/model-eval`` and never into the repo.

Workflow::

    # points the brain at the proxy, records, then restores and restarts it
    scripts/hippo-model-eval.py record --switch-brain --limit 200
    scripts/hippo-model-eval.py inspect
    sudo -v   # only for --power
    scripts/hippo-model-eval.py run --power --thinking off \\
        --model Qwen3.6-35B-A3B-Uncensored-Heretic-MLX-8bit \\
        --model Qwen3.6-35B-A3B-Uncensored-Heretic-MLX-6bit
    scripts/hippo-model-eval.py report \\
        --baseline Qwen3.6-35B-A3B-Uncensored-Heretic-MLX-8bit --show 3

For an unattended model x temperature x thinking matrix over the same cases,
use ``hippo-model-experiment.py``.
"""

from __future__ import annotations

import argparse
import copy
import http.client
import json
import os
import re
import signal
import statistics
import subprocess
import sys
import tempfile
import threading
import time
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any

type JsonDict = dict[str, Any]

DEFAULT_DIR = Path.home() / ".local/share/hippo/model-eval"
DEFAULT_UPSTREAM = "http://127.0.0.1:42069"
CHAT_PATH_SUFFIX = "/chat/completions"
POWER_LINE = re.compile(r"Combined Power \(CPU \+ GPU \+ ANE\):\s*(\d+)\s*mW")
FENCE = re.compile(r"^```(?:json)?\s*\n(.*?)\n```\s*$", re.DOTALL)
WORD = re.compile(r"[A-Za-z0-9_./-]+")
BASE_URL_LINE = re.compile(r'^(\s*base_url\s*=\s*)"([^"]*)"', re.MULTILINE)
HIPPO_CONFIG = Path.home() / ".config/hippo/config.toml"
BRAIN_SERVICE = "com.hippo.brain"


def private_dir(path: Path) -> Path:
    """Create a directory readable only by the current user.

    Args:
        path: Directory to create.

    Returns:
        The same path, now existing with mode 0700.
    """
    path.mkdir(parents=True, exist_ok=True)
    path.chmod(0o700)
    return path


def append_jsonl(path: Path, record: JsonDict) -> None:
    """Append one JSON record to a 0600 JSONL file.

    Args:
        path: Output file; its parent directory is created 0700.
        record: JSON-serializable record.
    """
    private_dir(path.parent)
    fd = os.open(path, os.O_WRONLY | os.O_APPEND | os.O_CREAT, 0o600)
    with os.fdopen(fd, "a", encoding="utf-8") as handle:
        handle.write(json.dumps(record, ensure_ascii=False) + "\n")


def read_jsonl(path: Path) -> list[JsonDict]:
    """Read every JSON object from a JSONL file.

    Args:
        path: JSONL file.

    Returns:
        Parsed records; blank lines are skipped.
    """
    with path.open(encoding="utf-8") as handle:
        return [json.loads(line) for line in handle if line.strip()]


# ── record ────────────────────────────────────────────────────────────────


class Recorder:
    """Shared state for the recording proxy.

    Attributes:
        upstream: Upstream origin, e.g. ``http://127.0.0.1:42069``.
        out: JSONL file that receives recorded chat requests.
        limit: Number of chat requests to record before stopping.
        count: Chat requests recorded so far.
        done: Set once ``count`` reaches ``limit``.
    """

    def __init__(self, upstream: str, out: Path, limit: int) -> None:
        """Initialize the recorder.

        Args:
            upstream: Upstream origin without a trailing slash.
            out: JSONL output file.
            limit: Number of chat requests to record.
        """
        self.upstream = upstream.rstrip("/")
        self.out = out
        self.limit = limit
        self.count = 0
        self.done = threading.Event()
        self._lock = threading.Lock()

    def save(self, path: str, request: JsonDict, status: int, body: bytes) -> None:
        """Record one chat request and the upstream response.

        Args:
            path: Request path.
            request: Parsed request body.
            status: Upstream HTTP status.
            body: Raw upstream response body.
        """
        try:
            response: Any = json.loads(body)
        except ValueError:
            # Streaming (SSE) responses are kept as text.
            response = body.decode("utf-8", "replace")
        with self._lock:
            if self.count >= self.limit:
                return
            self.count += 1
            append_jsonl(
                self.out,
                {
                    "id": f"{int(time.time() * 1000)}-{self.count}",
                    "path": path,
                    "request": request,
                    "status": status,
                    "response": response,
                },
            )
            print(f"recorded {self.count}/{self.limit}", file=sys.stderr)
            if self.count >= self.limit:
                self.done.set()


def make_handler(recorder: Recorder) -> type[BaseHTTPRequestHandler]:
    """Build a pass-through proxy handler bound to a recorder.

    Every request is forwarded to the upstream unchanged, so embedding and
    model-listing calls keep working while the brain points at the proxy.

    Args:
        recorder: Recorder that receives chat-completion traffic.

    Returns:
        A request handler class.
    """

    class Handler(BaseHTTPRequestHandler):
        """Forward requests upstream and record chat completions."""

        def log_message(self, format: str, *args: Any) -> None:
            """Silence per-request access logging."""

        def _forward(self) -> None:
            length = int(self.headers.get("Content-Length") or 0)
            data = self.rfile.read(length) if length else None
            headers = {
                key: value
                for key, value in self.headers.items()
                # Dropping accept-encoding keeps upstream bodies uncompressed, so
                # the client never gets gzip bytes without Content-Encoding and
                # recordings stay readable JSON.
                if key.lower()
                not in {"host", "content-length", "connection", "accept-encoding"}
            }
            request = urllib.request.Request(
                recorder.upstream + self.path,
                data=data,
                headers=headers,
                method=self.command,
            )
            try:
                response = urllib.request.urlopen(request, timeout=900)
                status = response.status
            except urllib.error.HTTPError as error:
                response, status = error, error.code
            except OSError as error:
                self.send_error(502, f"upstream unreachable: {error}")
                return
            with response:
                content_type = response.headers.get("Content-Type", "")
                self.send_response(status)
                if content_type:
                    self.send_header("Content-Type", content_type)
                if content_type.startswith("text/event-stream"):
                    # Relay SSE as it arrives so the brain keeps its streaming
                    # timing; HTTP/1.0 framing ends the body at close.
                    self.end_headers()
                    chunks = []
                    while chunk := response.read1(65536):
                        self.wfile.write(chunk)
                        self.wfile.flush()
                        chunks.append(chunk)
                    body = b"".join(chunks)
                else:
                    body = response.read()
                    self.send_header("Content-Length", str(len(body)))
                    self.end_headers()
                    self.wfile.write(body)
            if data and self.path.endswith(CHAT_PATH_SUFFIX):
                try:
                    recorder.save(self.path, json.loads(data), status, body)
                except ValueError:
                    pass

        do_GET = _forward
        do_POST = _forward

    return Handler


def point_brain_at(config: Path, url: str) -> None:
    """Rewrite the first ``base_url`` in hippo's config.

    The config is a symlink into the dotfiles checkout; writing through it
    edits the tracked file, so callers must save and restore its text.

    Args:
        config: Path to hippo's ``config.toml``.
        url: New inference base URL.

    Raises:
        ValueError: If the config has no ``base_url`` line.
    """
    original = config.read_text(encoding="utf-8")
    updated, count = BASE_URL_LINE.subn(
        lambda match: f'{match.group(1)}"{url}"', original, count=1
    )
    if count != 1:
        raise ValueError(f"no base_url line in {config}")
    config.write_text(updated, encoding="utf-8")


def restart_brain() -> None:
    """Restart the hippo brain so it rereads its config (macOS launchd)."""
    subprocess.run(
        ["launchctl", "kickstart", "-k", f"gui/{os.getuid()}/{BRAIN_SERVICE}"],
        check=False,
    )


def raise_exit(signum: int, _frame: Any) -> None:
    """Turn a termination signal into SystemExit so ``finally`` blocks run.

    Args:
        signum: Received signal number.
        _frame: Current stack frame (unused).

    Raises:
        SystemExit: Always.
    """
    raise SystemExit(128 + signum)


def cmd_record(args: argparse.Namespace) -> int:
    """Run the recording proxy until ``--limit`` chat requests are captured.

    With ``--switch-brain`` the brain is pointed at the proxy and restarted,
    then restored and restarted again however recording ends (limit, time
    limit, Ctrl-C, SIGTERM or SIGHUP).

    Args:
        args: Parsed CLI arguments.

    Returns:
        Process exit code.
    """
    recorder = Recorder(args.upstream, args.out, args.limit)
    server = ThreadingHTTPServer(("127.0.0.1", args.port), make_handler(recorder))
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    proxy_url = f"http://127.0.0.1:{server.server_address[1]}/v1"
    # Handlers and the restoring try/finally are in place before the config is
    # touched, so an interrupt during the switch itself still restores it.
    original = (
        args.hippo_config.read_text(encoding="utf-8") if args.switch_brain else None
    )
    previous = {
        sig: signal.signal(sig, raise_exit) for sig in (signal.SIGTERM, signal.SIGHUP)
    }
    try:
        if args.switch_brain:
            point_brain_at(args.hippo_config, proxy_url)
            restart_brain()
            print(
                f"brain now uses {proxy_url}; it is restored on exit", file=sys.stderr
            )
        else:
            print(
                f'set [inference].base_url = "{proxy_url}", then\n'
                f'launchctl kickstart -k "gui/$(id -u)/{BRAIN_SERVICE}"',
                file=sys.stderr,
            )
        print(
            f"proxy {proxy_url} -> {recorder.upstream}; recording {args.limit} chat "
            f"requests to {args.out}",
            file=sys.stderr,
        )
        recorder.done.wait(args.max_minutes * 60 if args.max_minutes else None)
    except KeyboardInterrupt:
        pass
    finally:
        for sig, handler in previous.items():
            signal.signal(sig, handler)
        server.shutdown()
        if original is not None:
            args.hippo_config.write_text(original, encoding="utf-8")
            restart_brain()
            print("brain config restored and restarted", file=sys.stderr)
    tail = "" if original is not None else "; restore base_url and kickstart the brain"
    print(f"recorded {recorder.count}{tail}", file=sys.stderr)
    return 0


# ── inspect ───────────────────────────────────────────────────────────────


def thinking_setting(request: JsonDict) -> str:
    """Describe how a request configures Qwen-style thinking.

    Args:
        request: Chat-completion request body.

    Returns:
        ``"off"``, ``"on"``, or ``"unset"`` (the template default, which is
        on for Qwen3.6).
    """
    kwargs = request.get("chat_template_kwargs")
    if isinstance(kwargs, dict) and "enable_thinking" in kwargs:
        return "on" if kwargs["enable_thinking"] else "off"
    return "unset"


def response_reasoning(response: Any) -> str:
    """Extract reasoning text from a recorded or live chat response.

    Args:
        response: Parsed response body, or SSE text for streamed responses.

    Returns:
        Reasoning text, empty when the response carried none.
    """
    if isinstance(response, str):
        found = re.findall(
            r'"reasoning(?:_content)?"\s*:\s*"((?:[^"\\]|\\.)*)"', response
        )
        return "".join(found)
    try:
        message = response["choices"][0]["message"]
    except (KeyError, IndexError, TypeError):
        return ""
    text = message.get("reasoning_content") or message.get("reasoning") or ""
    content = message.get("content") or ""
    if not text and "<think>" in content:
        text = content.split("</think>", 1)[0]
    return text


def cmd_inspect(args: argparse.Namespace) -> int:
    """Summarize recorded requests: models, thinking, JSON mode, sizes.

    Args:
        args: Parsed CLI arguments.

    Returns:
        Process exit code.
    """
    cases = read_jsonl(args.cases)
    if not cases:
        print("no recorded cases", file=sys.stderr)
        return 1
    counts: dict[str, dict[str, int]] = {}
    prompt_chars: list[int] = []
    reasoning_chars: list[int] = []
    for case in cases:
        request = case["request"]
        for key, value in (
            ("model", str(request.get("model"))),
            ("thinking", thinking_setting(request)),
            (
                "response_format",
                str((request.get("response_format") or {}).get("type")),
            ),
            ("stream", str(bool(request.get("stream")))),
            (
                "max_tokens",
                str(request.get("max_tokens") or request.get("max_completion_tokens")),
            ),
            ("temperature", str(request.get("temperature"))),
        ):
            counts.setdefault(key, {}).setdefault(value, 0)
            counts[key][value] += 1
        prompt_chars.append(len(json.dumps(request.get("messages", []))))
        reasoning_chars.append(len(response_reasoning(case.get("response"))))
    print(f"cases: {len(cases)}")
    for key, values in counts.items():
        print(f"{key}: " + ", ".join(f"{v} x{n}" for v, n in sorted(values.items())))
    print(
        f"prompt chars: median {statistics.median(prompt_chars):.0f}, max {max(prompt_chars)}"
    )
    with_reasoning = sum(1 for n in reasoning_chars if n)
    print(
        f"responses with reasoning: {with_reasoning}/{len(cases)}, "
        f"median reasoning chars {statistics.median(reasoning_chars):.0f}"
    )
    if with_reasoning:
        print("thinking is ON in production; that output is generated and discarded")
    return 0


# ── run ───────────────────────────────────────────────────────────────────


def build_request(
    request: JsonDict, model: str, thinking: str, temperature: float | None = None
) -> JsonDict:
    """Rewrite a recorded request for one candidate model.

    Args:
        request: Recorded chat-completion request body.
        model: Candidate model ID.
        thinking: ``"asis"`` keeps the recorded setting; ``"on"``/``"off"``
            force ``chat_template_kwargs.enable_thinking``.
        temperature: Sampling temperature to force; None keeps the recorded
            value.

    Returns:
        A new, non-streaming request body.
    """
    body = copy.deepcopy(request)
    body["model"] = model
    body["stream"] = False
    body.pop("stream_options", None)
    if thinking != "asis":
        kwargs = dict(body.get("chat_template_kwargs") or {})
        kwargs["enable_thinking"] = thinking == "on"
        body["chat_template_kwargs"] = kwargs
    if temperature is not None:
        body["temperature"] = temperature
    return body


def post_json(url: str, body: JsonDict, api_key: str, timeout: float) -> JsonDict:
    """POST a JSON body and parse the JSON response.

    Args:
        url: Endpoint URL.
        body: Request body.
        api_key: Bearer token for the inference server.
        timeout: Request timeout in seconds.

    Returns:
        Parsed response body.

    Raises:
        urllib.error.URLError: On transport or HTTP failure.
    """
    request = urllib.request.Request(
        url,
        data=json.dumps(body).encode(),
        headers={
            "Content-Type": "application/json",
            "Authorization": f"Bearer {api_key}",
        },
        method="POST",
    )
    with urllib.request.urlopen(request, timeout=timeout) as response:
        return json.load(response)


def parse_power(text: str) -> list[int]:
    """Extract combined CPU+GPU+ANE power samples from powermetrics output.

    Args:
        text: Raw ``powermetrics`` text output.

    Returns:
        Power samples in milliwatts.
    """
    return [int(match) for match in POWER_LINE.findall(text)]


class PowerSampler:
    """Run ``sudo -n powermetrics`` for the duration of one model's run."""

    def __init__(self) -> None:
        """Start powermetrics sampling once per second.

        Raises:
            RuntimeError: If powermetrics cannot start without a password.
        """
        # A file, not a pipe: an undrained pipe fills within seconds and
        # powermetrics then blocks, so later samples would never be taken.
        self._log = tempfile.TemporaryFile(mode="w+")
        launched = time.monotonic()
        self._proc = subprocess.Popen(
            [
                "sudo",
                "-n",
                "powermetrics",
                "--samplers",
                "cpu_power,gpu_power",
                "-i",
                "1000",
            ],
            stdout=self._log,
            stderr=subprocess.STDOUT,
            text=True,
        )
        time.sleep(1.5)
        if self._proc.poll() is not None:
            raise RuntimeError("powermetrics failed to start; run `sudo -v` first")
        self.started = time.monotonic()
        # Samples land once per second; those completed during the startup
        # wait are idle, not inference, so stop() drops them.
        self._startup_samples = int(self.started - launched)

    def stop(self) -> JsonDict:
        """Stop sampling and summarize.

        Returns:
            Mean watts, seconds sampled, and joules consumed.
        """
        seconds = time.monotonic() - self.started
        self._proc.terminate()
        self._proc.wait(timeout=10)
        with self._log:
            self._log.seek(0)
            samples = parse_power(self._log.read())[self._startup_samples :]
        watts = statistics.fmean(samples) / 1000 if samples else 0.0
        return {
            "mean_watts": round(watts, 2),
            "seconds": round(seconds, 1),
            "joules": round(watts * seconds, 1),
        }


def run_case(
    base_url: str, case: JsonDict, model: str, args: argparse.Namespace
) -> JsonDict:
    """Replay one recorded case against one model.

    Args:
        base_url: Inference base URL ending in ``/v1``.
        case: Recorded case.
        model: Candidate model ID.
        args: Parsed CLI arguments (thinking, api key, timeout, and an
            optional temperature).

    Returns:
        Result record for the results JSONL.
    """
    body = build_request(
        case["request"], model, args.thinking, getattr(args, "temperature", None)
    )
    result: JsonDict = {"type": "case", "model": model, "case": case["id"]}
    started = time.monotonic()
    try:
        response = post_json(
            base_url + CHAT_PATH_SUFFIX, body, args.api_key, args.timeout
        )
    except (OSError, ValueError, http.client.HTTPException) as error:
        # HTTPException covers a response cut short (IncompleteRead), which is
        # neither OSError nor ValueError but is a transport failure all the same.
        result.update(
            elapsed_s=round(time.monotonic() - started, 3),
            error=str(error) or type(error).__name__,
        )
        return result
    elapsed = time.monotonic() - started
    choice = (response.get("choices") or [{}])[0]
    message = choice.get("message") or {}
    usage = response.get("usage") or {}
    details = usage.get("completion_tokens_details") or {}
    content = message.get("content") or ""
    if "</think>" in content:
        content = content.split("</think>", 1)[1].strip()
    result.update(
        elapsed_s=round(elapsed, 3),
        prompt_tokens=usage.get("prompt_tokens"),
        completion_tokens=usage.get("completion_tokens"),
        reasoning_tokens=details.get("reasoning_tokens"),
        reasoning_chars=len(response_reasoning(response)),
        finish_reason=choice.get("finish_reason"),
        content=content,
    )
    return result


def cmd_run(args: argparse.Namespace) -> int:
    """Replay recorded cases against each model in turn.

    Models run sequentially (outer loop) so the server loads each once, with
    an untimed warm-up and a cooldown between models so thermal state is
    comparable.

    Args:
        args: Parsed CLI arguments.

    Returns:
        Process exit code.
    """
    if args.out.exists():
        # One run per file: report keys power and agreement by model and case,
        # so a second run appended here would be silently merged into the first.
        print(f"{args.out} exists; pass a new --out", file=sys.stderr)
        return 1
    cases = read_jsonl(args.cases)[: args.limit or None]
    if not cases:
        print("no recorded cases", file=sys.stderr)
        return 1
    base_url = args.base_url.rstrip("/")
    evaluated = 0
    for index, model in enumerate(args.model):
        if index and args.cooldown:
            print(f"cooldown {args.cooldown}s", file=sys.stderr)
            time.sleep(args.cooldown)
        print(f"== {model}: warm-up", file=sys.stderr)
        warm = run_case(base_url, cases[0], model, args)
        if "error" in warm:
            print(
                f"   warm-up failed, skipping model: {warm['error']}", file=sys.stderr
            )
            # Keep the failure visible in the report instead of dropping the model.
            append_jsonl(args.out, warm)
            continue
        evaluated += 1
        sampler = PowerSampler() if args.power else None
        try:
            for number, case in enumerate(cases, 1):
                result = run_case(base_url, case, model, args)
                append_jsonl(args.out, result)
                status = result.get("error") or f"{result['elapsed_s']:.1f}s"
                print(f"   {number}/{len(cases)} {status}", file=sys.stderr)
        except BaseException:
            # Reap the root powermetrics on Ctrl-C or any error; a partial
            # run's power row would be misleading, so none is written.
            if sampler:
                sampler.stop()
            raise
        if sampler:
            append_jsonl(args.out, {"type": "power", "model": model, **sampler.stop()})
    print(f"results: {args.out}", file=sys.stderr)
    return 0 if evaluated else 1


# ── report ────────────────────────────────────────────────────────────────


def parse_json_content(content: str) -> JsonDict | None:
    """Parse model output as a JSON object, tolerating a Markdown fence.

    Args:
        content: Assistant message content.

    Returns:
        The parsed object, or None when the content is not a JSON object.
    """
    text = content.strip()
    fenced = FENCE.match(text)
    if fenced:
        text = fenced.group(1)
    try:
        value = json.loads(text)
    except ValueError:
        return None
    return value if isinstance(value, dict) else None


def jaccard(left: set[str], right: set[str]) -> float:
    """Jaccard similarity of two sets; two empty sets are identical.

    Args:
        left: First set.
        right: Second set.

    Returns:
        Similarity in [0, 1].
    """
    if not left and not right:
        return 1.0
    return len(left & right) / len(left | right)


def words(value: Any) -> set[str]:
    """Lowercased word tokens of a JSON value, for fuzzy field comparison.

    Args:
        value: Any JSON value.

    Returns:
        Set of tokens.
    """
    text = value if isinstance(value, str) else json.dumps(value, sort_keys=True)
    return {token.lower() for token in WORD.findall(text)}


def agreement(candidate: JsonDict, baseline: JsonDict) -> tuple[float, float]:
    """Compare a candidate's structured output with the baseline's.

    Args:
        candidate: Candidate model's parsed output.
        baseline: Baseline model's parsed output.

    Returns:
        ``(key_agreement, value_agreement)``: Jaccard of top-level keys, and the
        mean token Jaccard of values over the baseline's keys (a missing key
        scores 0).
    """
    keys = jaccard(set(candidate), set(baseline))
    if not baseline:
        return keys, 1.0
    values = statistics.fmean(
        jaccard(words(candidate[key]), words(baseline[key]))
        if key in candidate
        else 0.0
        for key in baseline
    )
    return keys, values


def percentile(values: list[float], fraction: float) -> float:
    """Nearest-rank percentile.

    Args:
        values: Non-empty samples.
        fraction: Percentile in [0, 1].

    Returns:
        The sample at that rank.
    """
    ordered = sorted(values)
    return ordered[min(len(ordered) - 1, round(fraction * (len(ordered) - 1)))]


def mean_of(rows: list[JsonDict], key: str) -> float | None:
    """Mean of a numeric field, ignoring missing values.

    Args:
        rows: Result records.
        key: Field name.

    Returns:
        The mean, or None when no row carries the field.
    """
    values = [row[key] for row in rows if isinstance(row.get(key), (int, float))]
    return statistics.fmean(values) if values else None


def summarize(
    results: list[JsonDict],
    baseline: str | None,
    reference: dict[str, JsonDict | None] | None = None,
) -> list[JsonDict]:
    """Aggregate per-model metrics from results records.

    A case retried after an error appears more than once; only the last row
    for each model and case counts.

    Args:
        results: Records written by ``run`` or the experiment worker.
        baseline: Model ID to measure agreement against, if any.
        reference: Parsed outputs by case ID to measure agreement against
            instead of a baseline model (the experiment uses production's).

    Returns:
        One summary dict per model, in first-seen order.
    """
    latest: dict[tuple[str, str], JsonDict] = {}
    power: dict[str, JsonDict] = {}
    for row in results:
        if row.get("type") == "power":
            power[row["model"]] = row
        else:
            latest[(row["model"], row["case"])] = row
    by_model: dict[str, list[JsonDict]] = {}
    for (model, _case), row in latest.items():
        by_model.setdefault(model, []).append(row)
    if reference is not None:
        base_outputs = reference
    else:
        base_outputs = {
            row["case"]: parse_json_content(row.get("content") or "")
            for row in by_model.get(baseline or "", [])
            if "error" not in row
        }
    summaries = []
    for model, rows in by_model.items():
        ok = [row for row in rows if "error" not in row]
        outputs = [
            (row["case"], parse_json_content(row.get("content") or "")) for row in ok
        ]
        parsed = dict(outputs)
        latencies = [row["elapsed_s"] for row in ok]
        pairs = [
            agreement(output, base_outputs[case])
            for case, output in parsed.items()
            if output is not None and base_outputs.get(case) is not None
        ]
        summary: JsonDict = {
            "model": model,
            "cases": len(rows),
            "errors": len(rows) - len(ok),
            "json_valid": sum(value is not None for _, value in outputs) / len(ok)
            if ok
            else 0.0,
            "truncated": sum(row.get("finish_reason") == "length" for row in ok),
            "p50_s": statistics.median(latencies) if latencies else None,
            "p95_s": percentile(latencies, 0.95) if latencies else None,
            "completion_tokens": mean_of(ok, "completion_tokens"),
            "reasoning_chars": mean_of(ok, "reasoning_chars"),
            "key_agree": statistics.fmean(p[0] for p in pairs) if pairs else None,
            "value_agree": statistics.fmean(p[1] for p in pairs) if pairs else None,
        }
        if model in power:
            summary["watts"] = power[model]["mean_watts"]
            summary["joules_per_case"] = power[model]["joules"] / len(rows)
        summaries.append(summary)
    return summaries


def fmt(value: Any, spec: str = ".2f") -> str:
    """Format a metric for the table, rendering missing values as a dash.

    Args:
        value: Metric value.
        spec: Format spec for floats.

    Returns:
        Display string.
    """
    if value is None:
        return "-"
    return format(value, spec) if isinstance(value, float) else str(value)


def cmd_report(args: argparse.Namespace) -> int:
    """Print a Markdown comparison table and optional side-by-side samples.

    Args:
        args: Parsed CLI arguments.

    Returns:
        Process exit code.
    """
    results = read_jsonl(args.results)
    summaries = summarize(results, args.baseline)
    columns = [
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
    print("| " + " | ".join(name for name, _ in columns) + " |")
    print("|" + "---|" * len(columns))
    for summary in summaries:
        print(
            "| "
            + " | ".join(fmt(summary.get(name), spec) for name, spec in columns)
            + " |"
        )
    if args.show:
        cases: dict[str, dict[str, str]] = {}
        for row in results:
            if row.get("type") == "case":
                cases.setdefault(row["case"], {})[row["model"]] = row.get(
                    "content"
                ) or row.get("error", "")
        for case_id in list(cases)[: args.show]:
            print(f"\n### case {case_id}")
            for model, content in cases[case_id].items():
                print(f"\n**{model}**\n```\n{content}\n```")
    return 0


# ── CLI ───────────────────────────────────────────────────────────────────


def parser() -> argparse.ArgumentParser:
    """Build the command-line parser.

    Returns:
        Configured argument parser.
    """
    root = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    sub = root.add_subparsers(dest="command", required=True)

    record = sub.add_parser("record", help="proxy oMLX and record real chat requests")
    record.add_argument("--port", type=int, default=42070)
    record.add_argument(
        "--upstream", default=DEFAULT_UPSTREAM, help="oMLX origin, no /v1"
    )
    record.add_argument("--limit", type=int, default=200)
    record.add_argument("--out", type=Path, default=DEFAULT_DIR / "cases.jsonl")
    record.add_argument(
        "--switch-brain",
        action="store_true",
        help="point the brain at the proxy and restore it on exit",
    )
    record.add_argument("--hippo-config", type=Path, default=HIPPO_CONFIG)
    record.add_argument(
        "--max-minutes",
        type=float,
        default=0,
        help="stop after N minutes (0 = no limit)",
    )
    record.set_defaults(func=cmd_record)

    inspect = sub.add_parser("inspect", help="summarize recorded requests")
    inspect.add_argument("--cases", type=Path, default=DEFAULT_DIR / "cases.jsonl")
    inspect.set_defaults(func=cmd_inspect)

    run = sub.add_parser("run", help="replay recorded requests against models")
    run.add_argument("--cases", type=Path, default=DEFAULT_DIR / "cases.jsonl")
    run.add_argument(
        "--model", action="append", required=True, help="repeat per candidate"
    )
    run.add_argument("--thinking", choices=["asis", "off", "on"], default="asis")
    run.add_argument("--base-url", default=DEFAULT_UPSTREAM + "/v1")
    run.add_argument("--api-key", default=os.environ.get("OMLX_API_KEY", "omlx"))
    run.add_argument("--timeout", type=float, default=300.0)
    run.add_argument("--limit", type=int, default=0, help="first N cases (0 = all)")
    run.add_argument("--cooldown", type=int, default=60, help="seconds between models")
    run.add_argument("--power", action="store_true", help="sample powermetrics (sudo)")
    run.add_argument(
        "--out",
        type=Path,
        default=DEFAULT_DIR / f"results-{time.strftime('%Y%m%d-%H%M%S')}.jsonl",
    )
    run.set_defaults(func=cmd_run)

    report = sub.add_parser("report", help="compare models from a results file")
    report.add_argument("results", type=Path)
    report.add_argument("--baseline", help="model ID to measure agreement against")
    report.add_argument(
        "--show", type=int, default=0, help="print N cases side by side"
    )
    report.set_defaults(func=cmd_report)
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
