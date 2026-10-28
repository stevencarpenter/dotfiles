#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.12"
# dependencies = []
# ///
"""Unit and end-to-end tests for the unattended hippo model experiment."""

from __future__ import annotations

import importlib.util
import io
import json
import os
import signal
import sys
import tempfile
import threading
import tomllib
import unittest
from contextlib import redirect_stderr, redirect_stdout
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from types import ModuleType, SimpleNamespace
from typing import Any
from unittest.mock import patch

HERE = Path(__file__).resolve().parent


def load_script() -> ModuleType:
    """Load the hyphenated experiment script as a module.

    Returns:
        Imported script module.

    Raises:
        RuntimeError: If Python cannot construct an import specification.
    """
    path = HERE / "hippo-model-experiment.py"
    specification = importlib.util.spec_from_file_location("hippo_experiment", path)
    if specification is None or specification.loader is None:
        raise RuntimeError("cannot import hippo-model-experiment.py")
    module = importlib.util.module_from_spec(specification)
    # dataclasses resolve string annotations through sys.modules.
    sys.modules[specification.name] = module
    specification.loader.exec_module(module)
    return module


EXP = load_script()


class FakeOmlx(BaseHTTPRequestHandler):
    """OpenAI-compatible fake: serves ``served``, 404s ``gone``, can SIGTERM."""

    served = ["a", "b", "gone"]
    posts: list[dict[str, Any]] = []
    auth: list[str] = []
    sigterm_after: int | None = None

    def log_message(self, format: str, *args: Any) -> None:
        """Silence access logging."""

    def do_GET(self) -> None:
        """List served models."""
        self._send(200, {"data": [{"id": model} for model in FakeOmlx.served]})

    def do_POST(self) -> None:
        """Answer a chat completion whose summary depends on the variant."""
        body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        FakeOmlx.posts.append(body)
        FakeOmlx.auth.append(self.headers.get("Authorization", ""))
        if body["model"] == "gone":
            self._send(404, {"error": "model not loaded"})
            return
        if FakeOmlx.sigterm_after and len(FakeOmlx.posts) >= FakeOmlx.sigterm_after:
            FakeOmlx.sigterm_after = None
            os.kill(os.getpid(), signal.SIGTERM)
        thinking = (body.get("chat_template_kwargs") or {}).get("enable_thinking")
        summary = {"summary": f"fixed tmux {body['model']}", "tags": ["tmux"]}
        self._send(
            200,
            {
                "choices": [
                    {
                        "finish_reason": "stop",
                        "message": {
                            "content": json.dumps(summary),
                            "reasoning_content": "hmm" if thinking else None,
                        },
                    }
                ],
                "usage": {"prompt_tokens": 10, "completion_tokens": 5},
            },
        )

    def _send(self, status: int, payload: dict[str, Any]) -> None:
        data = json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)


POWER_TEXT = """\
*** Sampled system activity (Tue Oct 27 09:00:01 2026 +0000) (1000.00ms elapsed) ***
Combined Power (CPU + GPU + ANE): 10000 mW
*** Sampled system activity (Tue Oct 27 09:00:02 2026 +0000) (1000.00ms elapsed) ***
Combined Power (CPU + GPU + ANE): 30000 mW
*** Sampled system activity (Tue Oct 27 09:00:03 2026 +0000) (1000.00ms elapsed) ***
Combined Power (CPU + GPU + ANE): 50000 mW
"""


class PureFunctionTests(unittest.TestCase):
    """Matrix expansion and parsing helpers."""

    def test_shipped_matrix_expands_with_overrides(self) -> None:
        """The checked-in matrix gives 14 variants; LFM keeps its own thinking."""
        matrix = tomllib.loads(EXP.MATRIX.read_text())
        variants = EXP.expand_matrix(matrix)
        self.assertEqual(len(variants), 14)
        lfm = [v for v in variants if v.model.startswith("LFM")]
        self.assertEqual({v.thinking for v in lfm}, {"asis"})
        self.assertEqual({v.temperature for v in lfm}, {None, 0.2})
        self.assertEqual(len({v.slug for v in variants}), 14)

    def test_expand_rejects_unknown_thinking(self) -> None:
        """A typo in thinking fails at plan time, not mid-run."""
        with self.assertRaises(ValueError):
            EXP.expand_matrix({"models": [{"id": "m"}], "thinking": ["maybe"]})

    def test_production_content_handles_json_and_sse(self) -> None:
        """Recorded JSON and streamed SSE both yield the answer without think."""
        recorded = {"choices": [{"message": {"content": '<think>x</think>{"a": 1}'}}]}
        self.assertEqual(EXP.production_content(recorded), '{"a": 1}')
        sse = (
            'data: {"choices": [{"delta": {"content": "{\\"a\\""}}]}\n\n'
            'data: {"choices": [{"delta": {"content": ": 1}"}}]}\n\n'
            "data: [DONE]\n\n"
        )
        self.assertEqual(EXP.production_content(sse), '{"a": 1}')
        self.assertEqual(EXP.production_content(None), "")

    def test_power_is_attributed_by_window(self) -> None:
        """Only samples inside a variant's windows count toward it."""
        samples = EXP.parse_timed_power(POWER_TEXT)
        self.assertEqual([w for _, _, w in samples], [10.0, 30.0, 50.0])
        tmp = Path(tempfile.mkdtemp())
        (tmp / "powermetrics.txt").write_text(POWER_TEXT)
        first, last = samples[0][0], samples[-1][0]
        windows = [
            # Exactly the second sample's interval: 30 W for 1 s.
            {"variant": "v1", "start": first, "end": first + 1},
            # The third sample's interval: 50 W for 1 s.
            {"variant": "v2", "start": last - 1, "end": last},
            # 0.2 s inside the first sample: 10 W x 0.2 s, not the whole 10 J.
            {"variant": "v3", "start": first - 0.6, "end": first - 0.4},
        ]
        (tmp / "windows.jsonl").write_text(
            "".join(json.dumps(w) + "\n" for w in windows)
        )
        power = EXP.variant_power(tmp)
        self.assertEqual(power["v1"], {"watts": 30.0, "joules": 30.0})
        self.assertEqual(power["v2"], {"watts": 50.0, "joules": 50.0})
        self.assertAlmostEqual(power["v3"]["joules"], 2.0, places=3)
        self.assertAlmostEqual(power["v3"]["watts"], 10.0, places=3)

    def test_transport_error_waits_and_retries_once(self) -> None:
        """A dropped connection is retried after the server answers again."""
        calls: list[int] = []

        def flaky(*_args: Any) -> dict[str, Any]:
            calls.append(1)
            if len(calls) == 1:
                return {"model": "m", "case": "c", "error": "<urlopen error refused>"}
            return {"model": "m", "case": "c", "content": "{}"}

        variant = EXP.Variant("m", None, "off")
        ns = SimpleNamespace(api_key="k")
        with (
            patch.object(EXP.EVAL, "run_case", flaky),
            patch.object(EXP, "wait_for_server", lambda *a: True),
            redirect_stdout(io.StringIO()),
        ):
            result = EXP.run_variant_case(
                "u", {"id": "c"}, variant, ns, {"flag": False}
            )
        self.assertEqual(len(calls), 2)
        self.assertNotIn("error", result)
        self.assertEqual(result["model"], variant.id)

    def test_stop_during_recovery_skips_the_retry(self) -> None:
        """A stop that lands while waiting for oMLX ends without a new call."""
        calls: list[int] = []

        def failing(*_args: Any) -> dict[str, Any]:
            calls.append(1)
            return {"model": "m", "case": "c", "error": "<urlopen error refused>"}

        def stop_while_waiting(_url: str, _key: str, stop: dict[str, bool]) -> bool:
            stop["flag"] = True
            return False

        with (
            patch.object(EXP.EVAL, "run_case", failing),
            patch.object(EXP, "wait_for_server", stop_while_waiting),
            redirect_stdout(io.StringIO()),
        ):
            result = EXP.run_variant_case(
                "u",
                {"id": "c"},
                EXP.Variant("m", None, "off"),
                SimpleNamespace(api_key="k"),
                {"flag": False},
            )
        self.assertEqual(len(calls), 1)
        self.assertIn("error", result)

    def test_http_error_is_not_retried(self) -> None:
        """An answer from the server, even an error, is final."""
        calls: list[int] = []

        def failing(*_args: Any) -> dict[str, Any]:
            calls.append(1)
            return {"model": "m", "case": "c", "error": "HTTP Error 500: boom"}

        with patch.object(EXP.EVAL, "run_case", failing):
            EXP.run_variant_case(
                "u", {"id": "c"}, EXP.Variant("m", None, "off"), SimpleNamespace(), {}
            )
        self.assertEqual(len(calls), 1)


class ExperimentFixture(unittest.TestCase):
    """Fake oMLX, recorded cases, a small matrix and isolated run dirs."""

    def setUp(self) -> None:
        """Serve the fake, write cases and a small matrix, isolate run dirs."""
        FakeOmlx.posts.clear()
        FakeOmlx.auth.clear()
        FakeOmlx.served = ["a", "b", "gone"]
        server = ThreadingHTTPServer(("127.0.0.1", 0), FakeOmlx)
        threading.Thread(target=server.serve_forever, daemon=True).start()
        self.addCleanup(server.server_close)
        self.addCleanup(server.shutdown)
        self.base_url = f"http://127.0.0.1:{server.server_address[1]}/v1"
        self.tmp = Path(tempfile.mkdtemp())
        response = {"choices": [{"message": {"content": '{"summary": "fixed tmux"}'}}]}
        with (self.tmp / "cases.jsonl").open("w") as handle:
            for index in range(5):
                case = {
                    "id": f"c{index}",
                    "request": {
                        "model": "prod",
                        "temperature": 0.7,
                        "messages": [{"role": "user", "content": f"session {index}"}],
                    },
                    "response": response,
                }
                handle.write(json.dumps(case) + "\n")
        (self.tmp / "matrix.toml").write_text(
            'cases = 4\nround_size = 2\ntemperatures = ["asis", 0.2]\n'
            'thinking = ["off"]\n'
            '[[models]]\nid = "a"\n[[models]]\nid = "gone"\n[[models]]\nid = "b"\n'
        )
        runs = patch.object(EXP, "RUNS_DIR", self.tmp / "runs")
        runs.start()
        self.addCleanup(runs.stop)
        # No real macOS notifications from test runs.
        quiet = patch.object(EXP, "notify", lambda *_: None)
        quiet.start()
        self.addCleanup(quiet.stop)
        handlers = {s: signal.getsignal(s) for s in (signal.SIGTERM, signal.SIGINT)}
        self.addCleanup(lambda: [signal.signal(s, h) for s, h in handlers.items()])

    def start(self, *extra: str) -> int:
        """Run ``start --foreground`` against the fake.

        Args:
            *extra: Additional CLI flags.

        Returns:
            Exit code.
        """
        argv = ["start", "--foreground", "--matrix", str(self.tmp / "matrix.toml")]
        argv += ["--cases", str(self.tmp / "cases.jsonl"), "--base-url", self.base_url]
        with redirect_stdout(io.StringIO()), redirect_stderr(io.StringIO()):
            return EXP.main(argv + list(extra))


class EndToEndTests(ExperimentFixture):
    """Start in the foreground against a fake oMLX, stop, resume, report."""

    def test_full_run_writes_report_and_skips_404_model(self) -> None:
        """Every served variant finishes; the 404 model is reported, not fatal."""
        self.assertEqual(self.start(), 0)
        run = EXP.latest_run()
        status = json.loads((run / "status.json").read_text())
        self.assertEqual(status["state"], "done")
        self.assertEqual(status["done"], 16)  # a and b: 2 temps x 4 cases each
        sent = [p for p in FakeOmlx.posts if p["model"] != "gone"]
        self.assertEqual({p.get("temperature") for p in sent}, {0.7, 0.2})
        self.assertTrue(
            all(p["chat_template_kwargs"] == {"enable_thinking": False} for p in sent)
        )
        self.assertEqual(sum(p["model"] == "gone" for p in FakeOmlx.posts), 1)
        report = (run / "report.md").read_text()
        self.assertIn("| a [temp=0.2, think=off] |", report)
        self.assertIn("100.0%", report)
        key = json.loads((run / "blind-key.json").read_text())
        self.assertEqual(len(key), 4)
        self.assertIn("Production (reference)", (run / "blind.md").read_text())
        self.assertEqual((run / "cases.jsonl").stat().st_mode & 0o777, 0o600)

    def test_rounds_keep_variants_balanced(self) -> None:
        """Round 1 runs every variant on cases 0-1 before any sees case 2."""
        self.start()
        order = [
            (p["model"], p["messages"][0]["content"])
            for p in FakeOmlx.posts
            if p["model"] != "gone"
        ]
        first_case2 = next(i for i, (_, msg) in enumerate(order) if msg == "session 2")
        self.assertEqual({m for m, _ in order[:first_case2]}, {"a", "b"})

    def test_stop_then_resume_finishes_without_repeats(self) -> None:
        """SIGTERM stops after the current call; resume skips finished cases."""
        FakeOmlx.served = ["a", "b"]
        FakeOmlx.sigterm_after = 3
        self.assertEqual(self.start("--skip-missing"), 1)
        run = EXP.latest_run()
        self.assertEqual(
            json.loads((run / "status.json").read_text())["state"], "stopped"
        )
        stopped_posts = len(FakeOmlx.posts)
        with redirect_stdout(io.StringIO()), redirect_stderr(io.StringIO()):
            self.assertEqual(EXP.run_worker(run), 0)
        status = json.loads((run / "status.json").read_text())
        self.assertEqual((status["state"], status["done"]), ("done", 16))
        # Resume re-sends only unfinished cases (plus one untimed warm-up per model).
        resent = len(FakeOmlx.posts) - stopped_posts
        self.assertLessEqual(resent, 16 - 2 + 2 * 2)

    def test_missing_model_blocks_start_unless_skipped(self) -> None:
        """A model oMLX does not list fails start while you are still there."""
        FakeOmlx.served = ["a", "b"]
        self.assertEqual(self.start(), 1)
        self.assertIsNone(EXP.latest_run())
        self.assertEqual(self.start("--skip-missing"), 0)
        config = json.loads((EXP.latest_run() / "config.json").read_text())
        self.assertEqual(config["skipped_models"], ["gone"])


class ThirdReviewTests(ExperimentFixture):
    """API key handoff, empty blind samples, and power windows on stop."""

    def test_api_key_reaches_worker_but_not_disk(self) -> None:
        """--api-key is used for every call and never written to the run dir."""
        self.assertEqual(self.start("--api-key", "s3cret-token"), 0)
        self.assertTrue(FakeOmlx.auth)
        self.assertEqual(set(FakeOmlx.auth), {"Bearer s3cret-token"})
        run = EXP.latest_run()
        for path in run.rglob("*"):
            if path.is_file():
                self.assertNotIn("s3cret-token", path.read_text(errors="replace"))

    def test_report_survives_a_run_with_no_successes(self) -> None:
        """Only a 404 model: the report and an empty blind sample still appear."""
        (self.tmp / "matrix.toml").write_text(
            'cases = 2\nround_size = 2\n[[models]]\nid = "gone"\n'
        )
        self.assertEqual(self.start(), 0)
        run = EXP.latest_run()
        self.assertTrue((run / "report.md").exists())
        self.assertEqual(json.loads((run / "blind-key.json").read_text()), {})

    def test_stop_mid_window_still_records_the_window(self) -> None:
        """Cases saved before a stop keep a power window for their variant."""
        FakeOmlx.served = ["a", "b"]
        FakeOmlx.sigterm_after = 2  # warm-up, then case c0, then stop
        self.assertEqual(self.start("--skip-missing"), 1)
        run = EXP.latest_run()
        windows = EXP.EVAL.read_jsonl(run / "windows.jsonl")
        self.assertEqual([w["variant"] for w in windows], ["a [temp=asis, think=off]"])
        self.assertLessEqual(windows[0]["start"], windows[0]["end"])


class PowerResumeTests(ExperimentFixture):
    """A run started with --power keeps sampling after resume."""

    def test_resume_restarts_power_for_a_power_run(self) -> None:
        """Plain resume restarts powermetrics because the run recorded --power."""
        FakeOmlx.served = ["a", "b"]
        FakeOmlx.sigterm_after = 3
        started: list[Path] = []
        sudo: list[list[str]] = []

        def fake_spawn(run_dir: Path, api_key: str) -> int:
            with redirect_stdout(io.StringIO()), redirect_stderr(io.StringIO()):
                EXP.run_worker(run_dir, api_key)
            return 0

        with (
            patch.object(EXP, "start_power", started.append),
            patch.object(EXP.subprocess, "run", lambda cmd, **_: sudo.append(cmd)),
            patch.object(EXP, "spawn_worker", fake_spawn),
        ):
            self.assertEqual(self.start("--skip-missing", "--power"), 1)
            run = EXP.latest_run()
            self.assertTrue(json.loads((run / "config.json").read_text())["power"])
            self.assertFalse((run / "worker.pid").exists())
            with redirect_stdout(io.StringIO()):
                self.assertEqual(EXP.main(["resume", "--run", str(run)]), 0)
        self.assertEqual(started, [run, run])
        # Only sudo calls: on macOS the end-of-run notification also runs here.
        self.assertEqual([c for c in sudo if c[0] == "sudo"], [["sudo", "-v"]] * 2)


class TruncatedModels(BaseHTTPRequestHandler):
    """Promises a /models body it never finishes."""

    def log_message(self, format: str, *args: Any) -> None:
        """Silence access logging."""

    def do_GET(self) -> None:
        """Send 13 of 1000 promised bytes, then close."""
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", "1000")
        self.end_headers()
        self.wfile.write(b'{"data": [{"i')
        self.wfile.flush()
        self.close_connection = True


class FifthReviewTests(ExperimentFixture):
    """Truncated recovery polls and stale or reused worker PIDs."""

    def test_truncated_models_response_reads_as_unreachable(self) -> None:
        """A cut-off /models body is 'not answering', not an exception."""
        server = ThreadingHTTPServer(("127.0.0.1", 0), TruncatedModels)
        threading.Thread(target=server.serve_forever, daemon=True).start()
        self.addCleanup(server.server_close)
        self.addCleanup(server.shutdown)
        url = f"http://127.0.0.1:{server.server_address[1]}/v1"
        self.assertIsNone(EXP.server_models(url, "k"))

    def test_stale_pid_of_another_process_is_ignored(self) -> None:
        """A reused PID is neither signalled by stop nor blocks resume."""
        self.start()
        run = EXP.latest_run()
        self.assertFalse((run / "worker.pid").exists())
        # This test process is alive but is not the experiment worker.
        (run / "worker.pid").write_text(str(os.getpid()))
        with redirect_stdout(io.StringIO()), redirect_stderr(io.StringIO()):
            self.assertEqual(EXP.main(["stop", "--run", str(run)]), 1)
        self.assertIsNone(EXP.worker_pid(run / "worker.pid"))


if __name__ == "__main__":
    unittest.main()
