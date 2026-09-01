#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""Unit tests for the guarded 1Password reverse-adoption workflow."""

from __future__ import annotations

import importlib.util
import io
import json
import os
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from importlib.machinery import SourceFileLoader
from pathlib import Path
from types import ModuleType, SimpleNamespace
from unittest.mock import patch

REPO_ROOT = Path(__file__).resolve().parents[1]
SCRIPT = REPO_ROOT / "home/.local/bin/op-adopt"


def load_script() -> ModuleType:
    """Load the extensionless op-adopt script as a Python module.

    Returns:
        Imported script module.

    Raises:
        RuntimeError: If Python cannot construct an import specification.
    """

    loader = SourceFileLoader("op_adopt", str(SCRIPT))
    specification = importlib.util.spec_from_loader("op_adopt", loader)
    if specification is None or specification.loader is None:
        raise RuntimeError("cannot import op-adopt")
    module = importlib.util.module_from_spec(specification)
    specification.loader.exec_module(module)
    return module


OP_ADOPT = load_script()


class TtyInput(io.StringIO):
    """String input that presents itself as an interactive terminal."""

    def isatty(self) -> bool:
        """Report an interactive terminal.

        Returns:
            Always true for confirmation-path tests.
        """

        return True


class OpAdoptTests(unittest.TestCase):
    """Verify structural rejection and value-redaction invariants."""

    def setUp(self) -> None:
        """Create an isolated template, target, and version-1 policy."""

        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.template = self.root / "personal.env.tpl"
        self.target = self.root / ".personal.env"
        self.policy_path = self.root / "adopt-policy.json"
        self.reference = "op://Private/example/credential"
        self.policy = {
            "version": 1,
            "sentinel": str(self.root / ".last-render"),
            "files": {
                "personal-env": {
                    "template": str(self.template),
                    "target": str(self.target),
                    "format": "shell-env",
                    "adopt": True,
                    "items": {
                        "Private/example": {
                            "category": "API_CREDENTIAL",
                            "json_edit": True,
                        }
                    },
                    "variables": {
                        "EXAMPLE_TOKEN": {
                            "reference": self.reference,
                            "item": "Private/example",
                            "field": "credential",
                        }
                    },
                }
            },
        }
        self.template.write_text(
            f'# template\nexport EXAMPLE_TOKEN="{{{{ {self.reference} }}}}"\n',
            encoding="utf-8",
        )
        self.target.write_text('export EXAMPLE_TOKEN="new-secret"\n', encoding="utf-8")
        os.chmod(self.target, 0o600)
        self.policy_path.write_text(json.dumps(self.policy), encoding="utf-8")

    def tearDown(self) -> None:
        """Remove the isolated test directory."""

        self.temporary.cleanup()

    def test_template_rejects_literal_assignment(self) -> None:
        """A tracked shell secret cannot use a literal right-hand side."""

        with self.assertRaises(OP_ADOPT.PolicyError):
            OP_ADOPT.shell_template_assignments('export EXAMPLE_TOKEN="plaintext"\n')

    def test_policy_rejects_reference_that_hides_value_in_path(self) -> None:
        """An op-looking reference must match the separately declared item and field."""

        mapping = self.policy["files"]["personal-env"]["variables"]["EXAMPLE_TOKEN"]
        mapping["reference"] = "op://Private/example/THE_ACTUAL_SECRET_PLAINTEXT"
        with self.assertRaises(OP_ADOPT.PolicyError):
            OP_ADOPT.policy_references(self.policy["files"]["personal-env"])

    def test_live_file_rejects_system_added_assignment(self) -> None:
        """Unexpected exported or non-exported assignments are never adopted."""

        self.target.write_text(
            'export EXAMPLE_TOKEN="new-secret"\nSYSTEM_TOKEN="credential"\n',
            encoding="utf-8",
        )
        with self.assertRaises(OP_ADOPT.AdoptionError):
            OP_ADOPT.parse_live_env(self.target, {"EXAMPLE_TOKEN"})

    def test_apply_passes_secret_only_over_stdin_and_never_prints_it(self) -> None:
        """Approved values reach item edit JSON but never argv or user-facing output."""

        calls: list[tuple[list[str], str | None]] = []

        def fake_run_op(
            _op_binary: str,
            arguments: list[str],
            *,
            input_text: str | None = None,
            capture_stdout: bool = True,
            operation: str,
        ) -> SimpleNamespace:
            """Capture non-secret argv and sensitive stdin separately.

            Args:
                _op_binary: Ignored mock executable.
                arguments: Captured non-secret CLI arguments.
                input_text: Captured edit JSON.
                capture_stdout: Unused output-mode flag.
                operation: Unused operation label.

            Returns:
                Minimal successful subprocess result.
            """

            del capture_stdout, operation
            calls.append((arguments, input_text))
            return SimpleNamespace(stdout="", returncode=0)

        item = {
            "title": "example",
            "category": "API_CREDENTIAL",
            "vault": {"name": "Private"},
            "fields": [
                {
                    "id": "credential",
                    "label": "credential",
                    "type": "CONCEALED",
                    "value": "old-secret",
                }
            ],
        }
        output = io.StringIO()
        errors = io.StringIO()
        with (
            patch.object(OP_ADOPT, "find_op_binary", return_value="mock-op"),
            patch.object(OP_ADOPT, "fetch_item", return_value=item),
            patch.object(OP_ADOPT, "run_op", side_effect=fake_run_op),
            patch.object(OP_ADOPT, "verify_rendered_values"),
            patch("builtins.input", return_value="personal-env"),
            patch("sys.stdin", TtyInput()),
            redirect_stdout(output),
            redirect_stderr(errors),
        ):
            OP_ADOPT.adopt(
                self.policy,
                "personal-env",
                apply=True,
            )

        edit_calls = [call for call in calls if call[0][:2] == ["item", "edit"]]
        self.assertEqual(len(edit_calls), 1)
        edit_arguments, edit_input = edit_calls[0]
        self.assertNotIn("new-secret", " ".join(edit_arguments))
        self.assertIn("new-secret", edit_input or "")
        self.assertNotIn("new-secret", output.getvalue())
        self.assertNotIn("new-secret", errors.getvalue())
        self.assertTrue((self.root / ".last-render").is_file())

    def test_login_item_change_is_manual_only(self) -> None:
        """Passkey-risk Login items block JSON-template adoption."""

        item_policy = self.policy["files"]["personal-env"]["items"]["Private/example"]
        item_policy.update({"category": "LOGIN", "json_edit": False})
        item = {
            "title": "example",
            "category": "LOGIN",
            "vault": {"name": "Private"},
            "fields": [
                {
                    "id": "credential",
                    "label": "credential",
                    "type": "CONCEALED",
                    "value": "old-secret",
                }
            ],
        }
        with (
            patch.object(OP_ADOPT, "find_op_binary", return_value="mock-op"),
            patch.object(OP_ADOPT, "fetch_item", return_value=item),
            patch.object(OP_ADOPT, "run_op", return_value=SimpleNamespace(stdout="")),
            self.assertRaises(OP_ADOPT.AdoptionError),
        ):
            OP_ADOPT.adopt(
                self.policy,
                "personal-env",
                apply=True,
            )


if __name__ == "__main__":
    unittest.main()
