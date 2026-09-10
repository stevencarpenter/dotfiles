#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""Offline regression checks for shared Railway analysis and SQL transport."""

from __future__ import annotations

import base64
import importlib.util
import io
import shlex
import sys
import unittest
from argparse import Namespace
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path
from types import ModuleType
from unittest.mock import call, patch

SCRIPT_DIR = Path(__file__).resolve().parents[1] / "skills/personal/use-railway/scripts"
sys.path.insert(0, str(SCRIPT_DIR))

import dal  # noqa: E402


def load_script(name: str) -> ModuleType:
    """Load a standalone skill script without executing its CLI.

    Args:
        name: Script filename without the suffix.

    Returns:
        Loaded script module.
    """
    spec = importlib.util.spec_from_file_location(name, SCRIPT_DIR / f"{name}.py")
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


class RailwayAnalysisTest(unittest.TestCase):
    """Preserve context, retry, output, and quoting contracts without a network."""

    def test_context_uses_explicit_ids_or_linked_config(self) -> None:
        """Explicit IDs win; incomplete IDs use the existing linked context."""
        explicit = dal.RailwayContext("project", "environment", "service")
        linked = {"projectId": "p", "environmentId": "e", "serviceId": "s"}
        with patch.object(dal, "_ctx", dal.RailwayContext()):
            with patch.object(dal, "get_railway_status", return_value=linked) as read:
                self.assertEqual(dal._init_context(explicit), explicit)
                read.assert_not_called()
                args = Namespace(environment_id="partial", service_id=None)
                self.assertEqual(
                    dal._init_context(args), dal.RailwayContext("p", "e", "s")
                )
            with patch.object(dal, "get_railway_status", return_value=None):
                self.assertEqual(
                    dal._init_context(args), dal.RailwayContext("p", "e", "s")
                )

    def test_ssh_preflight_retries_reports_key_and_retains_failure(self) -> None:
        """Probe timeouts, diagnostic text, and quiet behavior survive extraction."""
        key = "Using SSH key: local\n"
        output = io.StringIO()
        with patch.object(
            dal, "run_ssh_query", side_effect=[(1, "", "retry"), (0, "ok", key)]
        ) as ssh:
            with redirect_stderr(output):
                self.assertEqual(dal.check_ssh("db"), (True, key))
            self.assertEqual(
                [item.kwargs["timeout"] for item in ssh.call_args_list], [30, 60]
            )
        self.assertEqual(
            output.getvalue(),
            "        SSH attempt 1/3 failed (retry), retrying with 60s timeout...\n        Using SSH key: local\n",
        )
        for quiet in (False, True):
            with (
                self.subTest(quiet=quiet),
                patch.object(
                    dal, "run_ssh_query", return_value=(1, "", "offline")
                ) as ssh,
            ):
                output = io.StringIO()
                with redirect_stderr(output):
                    self.assertEqual(
                        dal.check_ssh("db", quiet=quiet), (False, "offline")
                    )
                self.assertEqual(
                    [item.kwargs["timeout"] for item in ssh.call_args_list],
                    [30, 60, 90],
                )
                if quiet:
                    self.assertEqual(output.getvalue(), "")
                else:
                    self.assertIn(
                        "SSH attempt 3/3 failed (offline), giving up", output.getvalue()
                    )

    def test_each_report_keeps_its_infrastructure_layout(self) -> None:
        """Both report layouts retain labels, units, zero changes, and spikes."""
        metric = {"current": 2, "min": 1, "max": 3, "avg": 2, "unit": "GB"}
        metrics = {
            "disk": dict(metric, trend={"direction": "stable", "change_pct": 0}),
            "network_rx": dict(
                metric,
                trend={"direction": "decreasing", "change_pct": -20},
                spikes={"count": 2},
            ),
        }
        classes = {
            "postgres": "AnalysisResult",
            "mysql": "MySQLAnalysisResult",
            "redis": "RedisAnalysisResult",
            "mongo": "MongoAnalysisResult",
        }
        for engine, class_name in classes.items():
            with self.subTest(engine=engine):
                module = load_script(f"analyze-{engine}")
                result = getattr(module, class_name)(
                    service="db", db_type=engine, timestamp="now"
                )
                self.assertNotIn("## Infrastructure", module.format_report(result))
                result.metrics_history = {
                    "windows": {"empty": {"metrics": {}}, "7d": {"metrics": metrics}}
                }
                report = module.format_report(result)
                self.assertNotIn("(empty)", report)
                if engine in ("mysql", "redis"):
                    self.assertIn("| Disk | 2GB | 1GB | 3GB | 2GB | stable |", report)
                    self.assertIn(
                        "| Network Rx | 2GB | 1GB | 3GB | 2GB | decreasing (-20.0%) |",
                        report,
                    )
                else:
                    self.assertIn(
                        "| Disk | 2 GB | 1 | 3 | 2 | ~ stable | +0.0% |", report
                    )
                    self.assertIn(
                        "| Network RX | 2 GB | 1 | 3 | 2 | v decreasing | -20.0% (2 spikes) |",
                        report,
                    )

    def test_index_size_uses_numeric_bytes(self) -> None:
        """Recommendation totals use unrounded numeric values, including TB sizes."""
        postgres = load_script("analyze-postgres")
        self.assertEqual(postgres.sum_index_sizes([]), "0 bytes")
        self.assertEqual(
            postgres.sum_index_sizes([{"size": "1 MB", "size_bytes": "1536"}]), "1.5 KB"
        )
        self.assertEqual(
            postgres.sum_index_sizes([{"size": "1 TB", "size_bytes": 1024**4}]),
            "1024.0 GB",
        )

    def test_psql_encodes_queries_and_preserves_result_shapes(self) -> None:
        """Shell metacharacters stay encoded and SQL failures reach every caller."""
        query = "SELECT '$HOME', '$(id)', '`id`', 'quote\"', 'a\\b';\nSELECT 2"
        with patch.object(
            dal, "run_ssh_query", return_value=(3, "partial", "SQL error")
        ) as ssh:
            self.assertEqual(
                dal.run_psql_query_safe("db", query), (3, "partial", "SQL error")
            )
            command = ssh.call_args.args[1]
            encoded = shlex.split(command)[2]
            self.assertEqual(base64.b64decode(encoded).decode(), query)
            self.assertIn("-v ON_ERROR_STOP=1", command)
            self.assertNotIn("2>/dev/null", command)
            self.assertEqual(dal.run_psql_query("db", query), (3, "SQL error"))
        with patch.object(dal, "run_ssh_query", return_value=(0, "result", "warning")):
            self.assertEqual(dal.run_psql_query("db", query), (0, "result"))

    def test_extension_queries_quote_identifiers_and_literals(self) -> None:
        """Extension lookup and mutation escape their different SQL contexts."""
        extensions = load_script("pg-extensions")
        self.assertEqual(extensions.quote_sql_identifier('a"b'), '"a""b"')
        self.assertEqual(extensions.quote_sql_literal("a'b"), "E'a''b'")
        for quote in (extensions.quote_sql_identifier, extensions.quote_sql_literal):
            with self.assertRaises(ValueError):
                quote("bad\x00name")
        with patch.object(extensions, "run_psql_query", return_value=(0, "1")) as query:
            extensions.is_extension_available("db", "x'; SELECT 1; --")
            self.assertIn("E'x''; SELECT 1; --'", query.call_args.args[1])

    def test_extension_literal_escapes_backslashes_before_quotes(self) -> None:
        """Escape strings keep a backslash and quote payload inside one literal."""
        extensions = load_script("pg-extensions")
        payload = r"x\'; SELECT 1; --"
        expected = r"E'x\\''; SELECT 1; --'"
        self.assertEqual(extensions.quote_sql_literal(payload), expected)
        self.assertEqual(extensions.quote_sql_literal(r"\n"), r"E'\\n'")
        with patch.object(extensions, "run_psql_query", return_value=(0, "1")) as query:
            extensions.is_extension_available("db", payload)
            self.assertEqual(
                query.call_args.args[1],
                f"SELECT 1 FROM pg_available_extensions WHERE name = {expected}",
            )

    def test_pg_stats_restart_uses_imported_command(self) -> None:
        """The confirmed preload change reaches the Railway restart command."""
        stats = load_script("enable-pg-stats")
        with patch.object(sys, "argv", ["enable-pg-stats", "--service", "db"]):
            with (
                patch.object(stats, "run_psql_query", return_value=(0, "")),
                patch.object(stats, "confirm_with_user", return_value=True),
            ):
                with (
                    patch.object(
                        stats, "run_railway_command", return_value=(0, "", "")
                    ) as command,
                    redirect_stdout(io.StringIO()),
                ):
                    self.assertEqual(stats.main(), 0)
                self.assertEqual(
                    command.call_args, call(["restart", "--service", "db", "--yes"])
                )

    def test_log_api_rejects_ids_that_break_graphql_literals(self) -> None:
        """Invalid IDs take the CLI fallback without entering the API query."""
        response = Namespace(
            returncode=0,
            stdout='{"data":{"environmentLogs":[{"timestamp":"now","message":"log"}]}}',
        )
        for environment, service, valid in (
            ("abc-def", "123-456", True),
            ('abc"}', "123-456", False),
            ("abc-def", '123"}', False),
            (None, "123-456", False),
        ):
            with self.subTest(environment=environment, service=service):
                with (
                    patch.object(dal.os.path, "exists", return_value=True),
                    patch.object(dal.subprocess, "run", return_value=response) as api,
                    patch.object(
                        dal, "run_railway_command", return_value=(0, "fallback", "")
                    ),
                ):
                    logs = dal.get_recent_logs(
                        "db", environment_id=environment, service_id=service
                    )
                    self.assertEqual(logs, ["now log"] if valid else ["fallback"])
                    self.assertEqual(api.call_count, int(valid))


if __name__ == "__main__":
    unittest.main()
