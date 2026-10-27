#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.12"
# dependencies = []
# ///
"""Unit tests for the hippo enrichment model A/B evaluator."""

from __future__ import annotations

import importlib.util
import io
import json
import tempfile
import threading
import unittest
import urllib.request
from contextlib import redirect_stderr, redirect_stdout
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from types import ModuleType
from typing import Any
from unittest.mock import patch

SCRIPT = Path(__file__).resolve().parent / "hippo-model-eval.py"


def load_script() -> ModuleType:
    """Load the hyphenated evaluator script as a module.

    Returns:
        Imported script module.

    Raises:
        RuntimeError: If Python cannot construct an import specification.
    """
    specification = importlib.util.spec_from_file_location("hippo_model_eval", SCRIPT)
    if specification is None or specification.loader is None:
        raise RuntimeError("cannot import hippo-model-eval.py")
    module = importlib.util.module_from_spec(specification)
    specification.loader.exec_module(module)
    return module


EVAL = load_script()


class FakeOmlx(BaseHTTPRequestHandler):
    """Minimal OpenAI-compatible server that echoes the requested model."""

    requests: list[dict[str, Any]] = []

    def log_message(self, format: str, *args: Any) -> None:
        """Silence access logging."""

    def do_GET(self) -> None:
        """Answer the model list."""
        self._send({"data": [{"id": "m"}]})

    def do_POST(self) -> None:
        """Answer a chat completion with a JSON summary."""
        body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        FakeOmlx.requests.append(body)
        thinking = (body.get("chat_template_kwargs") or {}).get("enable_thinking", True)
        self._send(
            {
                "choices": [
                    {
                        "finish_reason": "stop",
                        "message": {
                            "content": json.dumps(
                                {"summary": f"ran {body['model']}", "tags": ["x"]}
                            ),
                            "reasoning_content": "hmm" if thinking else None,
                        },
                    }
                ],
                "usage": {"prompt_tokens": 10, "completion_tokens": 5},
            }
        )

    def _send(self, payload: dict[str, Any]) -> None:
        data = json.dumps(payload).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)


def serve(handler: type[BaseHTTPRequestHandler]) -> ThreadingHTTPServer:
    """Start a handler on an ephemeral localhost port.

    Args:
        handler: Request handler class.

    Returns:
        The running server; call ``shutdown`` when done.
    """
    server = ThreadingHTTPServer(("127.0.0.1", 0), handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    return server


class PureFunctionTests(unittest.TestCase):
    """Parsing and scoring helpers."""

    def test_parse_json_content_accepts_fence_and_rejects_non_objects(self) -> None:
        """Fenced JSON parses; arrays and prose do not."""
        self.assertEqual(EVAL.parse_json_content('```json\n{"a": 1}\n```'), {"a": 1})
        self.assertEqual(EVAL.parse_json_content(' {"a": 1} '), {"a": 1})
        self.assertIsNone(EVAL.parse_json_content("[1, 2]"))
        self.assertIsNone(EVAL.parse_json_content("sure, here you go"))

    def test_agreement_scores_missing_keys_as_zero(self) -> None:
        """Identical outputs agree fully; a dropped key halves value agreement."""
        base = {"summary": "fixed the tmux socket", "tags": ["tmux"]}
        self.assertEqual(EVAL.agreement(base, base), (1.0, 1.0))
        keys, values = EVAL.agreement({"summary": "fixed the tmux socket"}, base)
        self.assertEqual((keys, values), (0.5, 0.5))

    def test_build_request_forces_thinking_and_disables_streaming(self) -> None:
        """The replayed body swaps model, drops streaming, and sets thinking."""
        recorded = {
            "model": "old",
            "stream": True,
            "stream_options": {},
            "messages": [],
        }
        body = EVAL.build_request(recorded, "new", "off")
        self.assertEqual(body["model"], "new")
        self.assertFalse(body["stream"])
        self.assertNotIn("stream_options", body)
        self.assertEqual(body["chat_template_kwargs"], {"enable_thinking": False})
        self.assertEqual(recorded["model"], "old")
        self.assertNotIn(
            "chat_template_kwargs", EVAL.build_request(recorded, "new", "asis")
        )

    def test_thinking_setting_reports_template_default(self) -> None:
        """Absent kwargs mean the template default, not off."""
        self.assertEqual(EVAL.thinking_setting({}), "unset")
        self.assertEqual(
            EVAL.thinking_setting({"chat_template_kwargs": {"enable_thinking": False}}),
            "off",
        )

    def test_parse_power_reads_combined_lines(self) -> None:
        """Only the combined CPU+GPU+ANE line is counted."""
        text = "CPU Power: 900 mW\nCombined Power (CPU + GPU + ANE): 12345 mW\nCombined Power (CPU + GPU + ANE): 55 mW\n"
        self.assertEqual(EVAL.parse_power(text), [12345, 55])


class EndToEndTests(unittest.TestCase):
    """Record through the proxy, replay against two models, and report."""

    def test_record_run_report(self) -> None:
        """A recorded request replays per model and reports full agreement on keys."""
        upstream = serve(FakeOmlx)
        self.addCleanup(upstream.server_close)
        self.addCleanup(upstream.shutdown)
        tmp = Path(tempfile.mkdtemp())
        origin = f"http://127.0.0.1:{upstream.server_address[1]}"
        recorder = EVAL.Recorder(origin, tmp / "cases.jsonl", limit=1)
        proxy = serve(EVAL.make_handler(recorder))
        self.addCleanup(proxy.server_close)
        self.addCleanup(proxy.shutdown)
        proxy_url = f"http://127.0.0.1:{proxy.server_address[1]}"

        with urllib.request.urlopen(proxy_url + "/v1/models") as response:
            self.assertEqual(json.load(response)["data"][0]["id"], "m")
        with redirect_stderr(io.StringIO()):
            EVAL.post_json(
                proxy_url + "/v1/chat/completions",
                {
                    "model": "prod",
                    "stream": True,
                    "messages": [{"role": "user", "content": "hi"}],
                },
                "omlx",
                5,
            )
        self.assertTrue(recorder.done.wait(3))
        self.assertEqual((tmp / "cases.jsonl").stat().st_mode & 0o777, 0o600)

        out = io.StringIO()
        with redirect_stdout(out):
            EVAL.main(["inspect", "--cases", str(tmp / "cases.jsonl")])
        self.assertIn("thinking: unset x1", out.getvalue())
        self.assertIn("responses with reasoning: 1/1", out.getvalue())

        results = tmp / "results.jsonl"
        with redirect_stderr(io.StringIO()):
            EVAL.main(
                [
                    "run",
                    "--cases",
                    str(tmp / "cases.jsonl"),
                    "--base-url",
                    origin + "/v1",
                    "--model",
                    "a",
                    "--model",
                    "b",
                    "--thinking",
                    "off",
                    "--cooldown",
                    "0",
                    "--out",
                    str(results),
                ]
            )
        self.assertFalse(FakeOmlx.requests[-1]["stream"])
        self.assertEqual(
            FakeOmlx.requests[-1]["chat_template_kwargs"], {"enable_thinking": False}
        )

        summaries = {
            row["model"]: row for row in EVAL.summarize(EVAL.read_jsonl(results), "a")
        }
        self.assertEqual(summaries["b"]["json_valid"], 1.0)
        self.assertEqual(summaries["b"]["key_agree"], 1.0)
        self.assertLess(summaries["b"]["value_agree"], 1.0)
        self.assertEqual(summaries["b"]["reasoning_chars"], 0)

        out = io.StringIO()
        with redirect_stdout(out):
            EVAL.main(["report", str(results), "--baseline", "a", "--show", "1"])
        self.assertIn("| b | 1 | 0 | 100.0% |", out.getvalue())


class SlowSse(BaseHTTPRequestHandler):
    """SSE upstream that holds its second event until ``release`` is set."""

    release = threading.Event()

    def log_message(self, format: str, *args: Any) -> None:
        """Silence access logging."""

    def do_POST(self) -> None:
        """Emit one event, wait, then emit the terminator."""
        self.rfile.read(int(self.headers["Content-Length"]))
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.end_headers()
        self.wfile.write(b'data: {"first": true}\n\n')
        self.wfile.flush()
        SlowSse.release.wait(5)
        self.wfile.write(b"data: [DONE]\n\n")


class RegressionTests(unittest.TestCase):
    """Streaming relay, power sampling, and repeated-run accounting."""

    def test_proxy_relays_sse_before_upstream_finishes(self) -> None:
        """The first event reaches the client while upstream is still open."""
        upstream = serve(SlowSse)
        self.addCleanup(upstream.server_close)
        self.addCleanup(upstream.shutdown)
        self.addCleanup(SlowSse.release.set)
        tmp = Path(tempfile.mkdtemp())
        recorder = EVAL.Recorder(
            f"http://127.0.0.1:{upstream.server_address[1]}", tmp / "c.jsonl", 1
        )
        proxy = serve(EVAL.make_handler(recorder))
        self.addCleanup(proxy.server_close)
        self.addCleanup(proxy.shutdown)
        request = urllib.request.Request(
            f"http://127.0.0.1:{proxy.server_address[1]}/v1/chat/completions",
            data=json.dumps({"model": "m", "stream": True}).encode(),
            headers={"Content-Type": "application/json"},
        )
        with urllib.request.urlopen(request, timeout=3) as response:
            self.assertEqual(response.readline(), b'data: {"first": true}\n')
            self.assertFalse(recorder.done.is_set())
            SlowSse.release.set()
            self.assertIn(b"[DONE]", response.read())
        with redirect_stderr(io.StringIO()):
            self.assertTrue(recorder.done.wait(3))
        self.assertIn("[DONE]", EVAL.read_jsonl(tmp / "c.jsonl")[0]["response"])

    def test_power_sampler_keeps_samples_past_a_pipe_buffer(self) -> None:
        """Output larger than a pipe buffer is still fully counted."""
        # 2000 early lines (~84 KB, past a 64 KB pipe) at 1 W, then 3000 at
        # 3 W: a stalled sampler only ever sees the 1 W lines.
        line = "Combined Power (CPU + GPU + ANE): {} mW"
        command = (
            f'for i in $(seq 2000); do echo "{line.format(1000)}"; done; '
            f'for i in $(seq 3000); do echo "{line.format(3000)}"; done; sleep 30'
        )
        real_popen = EVAL.subprocess.Popen

        def fake_popen(_args: list[str], **kwargs: Any) -> Any:
            return real_popen(["sh", "-c", command], **kwargs)

        with patch.object(EVAL.subprocess, "Popen", fake_popen):
            sampler = EVAL.PowerSampler()
            summary = sampler.stop()
        self.assertEqual(summary["mean_watts"], 2.2)

    def test_json_valid_counts_every_row(self) -> None:
        """Two valid rows for one case report 100%, not 50%."""
        row = {"type": "case", "model": "m", "case": "c", "elapsed_s": 1.0}
        rows = [{**row, "content": '{"a": 1}'}, {**row, "content": '{"a": 2}'}]
        self.assertEqual(EVAL.summarize(rows, None)[0]["json_valid"], 1.0)

    def test_run_refuses_existing_results_file(self) -> None:
        """A second run cannot append into an earlier run's results."""
        tmp = Path(tempfile.mkdtemp())
        (tmp / "results.jsonl").write_text("")
        with redirect_stderr(io.StringIO()):
            code = EVAL.main(
                [
                    "run",
                    "--cases",
                    str(tmp / "missing.jsonl"),
                    "--model",
                    "m",
                    "--out",
                    str(tmp / "results.jsonl"),
                ]
            )
        self.assertEqual(code, 1)


if __name__ == "__main__":
    unittest.main()
