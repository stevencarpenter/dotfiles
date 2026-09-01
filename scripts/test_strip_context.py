#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""Unit tests for the blind-review context stripper.

Both failure directions are silent and both defeat the skill: stripping too
much hands the blind reviewer mangled source, so its findings are noise;
stripping too little leaks the comments the blind arm exists to be blind to.
Neither is visible in the output, so every supported language is pinned here.
"""

from __future__ import annotations

import importlib.util
import subprocess
import tempfile
import unittest
from importlib.machinery import SourceFileLoader
from pathlib import Path
from types import ModuleType

REPO_ROOT = Path(__file__).resolve().parents[1]
SCRIPT = REPO_ROOT / "skills/personal/blind-review/scripts/strip_context.py"


def load_script() -> ModuleType:
    """Load the stripper as a module despite its non-importable filename.

    Returns:
        The imported module.
    """
    loader = SourceFileLoader("strip_context", str(SCRIPT))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    assert spec is not None
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


strip_context = load_script()


class PositionContractTest(unittest.TestCase):
    """Every strip must be a space-mask of its input."""

    def assert_masked(self, name: str, source: str) -> str:
        """Strip a source and assert positions survived.

        Args:
            name: File name used for language dispatch.
            source: Source text to strip.

        Returns:
            The stripped text.
        """
        stripped, action = strip_context.strip_source(name, source)
        self.assertEqual(action, "stripped", f"{name} was not stripped: {action}")
        self.assertEqual(len(stripped), len(source), "byte count changed")
        self.assertEqual(stripped.count("\n"), source.count("\n"), "line count changed")
        for before, after in zip(source, stripped):
            if before != after:
                self.assertEqual(after, " ", "a character was rewritten, not blanked")
        return stripped


class PythonStripTest(PositionContractTest):
    """Python uses tokenize, so strings must never be mistaken for comments."""

    def test_hash_inside_string_survives(self) -> None:
        """A `#` in a string literal is not a comment."""
        out = self.assert_masked("a.py", 's = "# not a comment"  # real\n')
        self.assertIn('"# not a comment"', out)
        self.assertNotIn("real", out)

    def test_hash_inside_triple_quoted_string_survives(self) -> None:
        """Triple-quoted strings that are not docstrings are data."""
        src = 'x = """\n# inside\n"""\n# gone\n'
        out = self.assert_masked("a.py", src)
        self.assertIn("# inside", out)
        self.assertNotIn("gone", out)

    def test_fstring_and_raw_string_survive(self) -> None:
        """Prefixed strings are strings."""
        out = self.assert_masked("a.py", 'a = f"{x}#y"\nb = r"\\#z"\n# bye\n')
        self.assertIn("#y", out)
        self.assertIn("#z", out)
        self.assertNotIn("bye", out)

    def test_docstrings_are_removed(self) -> None:
        """Module, class, and function docstrings all carry claims to hide."""
        src = '"""Mod."""\n\n\nclass C:\n    """Cls."""\n\n    def m(self):\n        """Fn."""\n        return 1\n'
        out = self.assert_masked("a.py", src)
        for claim in ("Mod.", "Cls.", "Fn."):
            self.assertNotIn(claim, out)
        self.assertIn("return 1", out)

    def test_stripped_python_still_compiles(self) -> None:
        """The blind reviewer must receive parseable source."""
        src = '"""Doc."""\n\n\ndef f(x):\n    """Inner."""\n    return x + 1  # add\n'
        compile(self.assert_masked("a.py", src), "a.py", "exec")


class SlashStripTest(PositionContractTest):
    """C-family stripping must survive regex literals and template strings."""

    def test_regex_literal_is_not_a_comment_opener(self) -> None:
        """A regex body must survive; only the trailing comment goes."""
        out = self.assert_masked("a.js", "const re = /ab+/;\n// gone\n")
        self.assertIn("/ab+/", out)
        self.assertNotIn("gone", out)

    def test_regex_with_escaped_slashes_survives(self) -> None:
        """The already-working escaped form must not regress."""
        out = self.assert_masked("a.js", "const re = /foo\\/\\/bar/;\n")
        self.assertIn("foo\\/\\/bar", out)

    def test_regex_character_class_with_slash_survives(self) -> None:
        """A `/` inside `[...]` does not close the literal."""
        out = self.assert_masked("a.js", "const re = /[/]x/g;\nlet y = 1; // gone\n")
        self.assertIn("[/]x", out)
        self.assertNotIn("gone", out)

    def test_division_is_not_treated_as_regex(self) -> None:
        """`a / b / c` is arithmetic; misreading it would swallow real code."""
        out = self.assert_masked("a.js", "const q = a / b / c;\nconst z = 2; // gone\n")
        self.assertIn("a / b / c", out)
        self.assertIn("const z = 2;", out)
        self.assertNotIn("gone", out)

    def test_comment_inside_template_substitution_is_stripped(self) -> None:
        """Inside `${...}` the language is code again, so comments must go."""
        out = self.assert_masked("a.js", "const t = `v ${a /* gone */ + b} w`;\n")
        self.assertNotIn("gone", out)
        self.assertIn("` v ", out.replace("`v ", "` v "))

    def test_double_slash_inside_string_survives(self) -> None:
        """A URL in a string literal is not a comment."""
        out = self.assert_masked("a.ts", 'const u = "http://x/y";\n// gone\n')
        self.assertIn("http://x/y", out)
        self.assertNotIn("gone", out)

    def test_block_comment_marker_inside_string_survives(self) -> None:
        """`/*` in a string must not open a block comment."""
        out = self.assert_masked("a.c", 'char *s = "/* not */";\nint x = 1;\n')
        self.assertIn("/* not */", out)
        self.assertIn("int x = 1;", out)

    def test_rust_nested_block_comments(self) -> None:
        """Rust allows nesting, so the depth counter must be exercised."""
        out = self.assert_masked("a.rs", "let x = 1; /* a /* b */ c */\nlet y = 2;\n")
        for claim in ("a", "b", "c"):
            self.assertNotIn(claim, out.replace("let", ""))
        self.assertIn("let y = 2;", out)

    def test_template_substitution_tracks_nested_object_braces(self) -> None:
        """A `}` inside `${{...}}` must not close the interpolation."""
        out = self.assert_masked("a.js", "const value = `${{key: 1} /* hidden */}`;\n")
        self.assertNotIn("hidden", out)
        self.assertIn("{key: 1}", out)


class HashStripTest(PositionContractTest):
    """Shell-family `#` handling is position-sensitive."""

    def test_shell_parameter_expansion_survives(self) -> None:
        """`${#arr[@]}` is a length expansion, not a comment."""
        out = self.assert_masked("a.sh", "n=${#arr[@]}  # gone\n")
        self.assertIn("${#arr[@]}", out)
        self.assertNotIn("gone", out)

    def test_hash_inside_quotes_survives(self) -> None:
        """A quoted `#` is data."""
        out = self.assert_masked("a.sh", 's="a#b"  # gone\n')
        self.assertIn("a#b", out)
        self.assertNotIn("gone", out)

    def test_url_fragment_survives(self) -> None:
        """A `#` with no preceding whitespace does not open a comment."""
        out = self.assert_masked("a.sh", "url=http://x#frag\n# gone\n")
        self.assertIn("http://x#frag", out)
        self.assertNotIn("gone", out)

    def test_nix_files_are_stripped(self) -> None:
        """A Nix dotfiles repo's diffs are mostly .nix files."""
        out = self.assert_masked("a.nix", "{ x = 1; # gone\n}\n")
        self.assertNotIn("gone", out)
        self.assertIn("x = 1;", out)

    def test_comment_after_semicolon_is_stripped(self) -> None:
        """`;#` ends a command and opens a comment; it used to leak."""
        out = self.assert_masked("a.sh", "echo hi;# gone\n")
        self.assertNotIn("gone", out)
        self.assertIn("echo hi;", out)

    def test_nix_comment_after_brace_is_stripped(self) -> None:
        """In Nix a `}` closes a value, so `}#` is a comment."""
        out = self.assert_masked("a.nix", "a = {};#gone\nb = 1;\n")
        self.assertNotIn("gone", out)
        self.assertIn("a = {};", out)

    def test_shell_brace_expansion_suffix_survives(self) -> None:
        """`${v}#tag` is one shell word, not a comment. Guards the `;#` fix."""
        out = self.assert_masked("a.sh", "echo ${v}#tag\n# gone\n")
        self.assertIn("${v}#tag", out)
        self.assertNotIn("gone", out)

    def test_heredoc_body_is_data_not_comment(self) -> None:
        """A heredoc body is a payload; blanking its `#` corrupts it."""
        out = self.assert_masked(
            "a.sh", "cat <<EOF\n# data not a comment\nEOF\necho x # gone\n"
        )
        self.assertIn("# data not a comment", out)
        self.assertNotIn("gone", out)

    def test_quoted_and_tab_stripped_heredocs(self) -> None:
        """`<<'EOF'` and `<<-EOF` open heredocs too."""
        quoted = self.assert_masked("a.sh", "cat <<'EOF'\n# kept\nEOF\n")
        self.assertIn("# kept", quoted)
        tabbed = self.assert_masked("a.sh", "cat <<-EOF\n\t# kept\n\tEOF\n")
        self.assertIn("# kept", tabbed)

    def test_here_string_is_not_a_heredoc(self) -> None:
        """`<<<` is a here-string; treating it as a heredoc would eat the file."""
        out = self.assert_masked("a.sh", 'cat <<<"$x" # gone\necho done\n')
        self.assertNotIn("gone", out)
        self.assertIn("echo done", out)

    def test_yaml_merge_key_is_not_a_heredoc(self) -> None:
        """YAML's `<<:` merge key must not open a heredoc."""
        out = self.assert_masked("a.yaml", "merged:\n  <<: *base\n# gone\n")
        self.assertNotIn("gone", out)
        self.assertIn("<<: *base", out)

    def test_nix_interpolation_inside_double_quotes(self) -> None:
        """A quote inside `"${ ... }"` must not desync the string state."""
        out = self.assert_masked("a.nix", 'x = "${ f "lit" }";\n# gone\ny = 1;\n')
        self.assertNotIn("gone", out)
        self.assertIn('"${ f "lit" }"', out)

    def test_crlf_comment_keeps_its_carriage_return(self) -> None:
        """Blanking a CRLF comment must not shorten the line by one byte."""
        source = "a\r\n# gone\r\nb\r\n"
        out = self.assert_masked("a.sh", source)
        self.assertNotIn("gone", out)
        self.assertEqual(out.count("\r"), source.count("\r"))

    def test_nix_indented_string_preserves_hashes(self) -> None:
        """`#` inside `''...''` is data, including a quoted shell comment."""
        src = "let\n  script = ''\n    echo \"# keep\"\n  '';\n# remove\n"
        out = self.assert_masked("example.nix", src)
        self.assertIn('echo "# keep"', out)
        self.assertNotIn("remove", out)

    def test_nix_escaped_indent_delimiters_stay_inside_string(self) -> None:
        """`'''`, `''$`, and `''\\` do not close an indented string."""
        src = "''\n  echo '''\n  echo ''$\n  echo ''\\\n'';\n# gone\n"
        out = self.assert_masked("a.nix", src)
        self.assertIn("echo '''", out)
        self.assertNotIn("gone", out)

    def test_nix_nested_indented_string_in_interpolation(self) -> None:
        """`${ '' ... '' }` is a nested string; an unquoted `#` in it is data."""
        src = "''\n  ${\n    ''\n      echo # keep\n    ''\n  }\n'';\n# gone\n"
        out = self.assert_masked("a.nix", src)
        self.assertIn("echo # keep", out)
        self.assertNotIn("gone", out)

    def test_nix_interpolation_comments_are_stripped(self) -> None:
        """Inside `${...}` the language is Nix again, so `#` is a comment."""
        src = "''\n  ${foo # gone\n  }\n'';\n"
        out = self.assert_masked("a.nix", src)
        self.assertNotIn("gone", out)
        self.assertIn("${foo", out)

    def test_extensionless_known_stems_are_stripped(self) -> None:
        """A Justfile has comment syntax even with no suffix."""
        out = self.assert_masked("Justfile", "# gone\nbuild:\n    echo hi\n")
        self.assertNotIn("gone", out)
        self.assertIn("echo hi", out)


class SqlAndXmlStripTest(PositionContractTest):
    """The remaining supported families."""

    def test_sql_escaped_quote_does_not_desync(self) -> None:
        """`''` is an escaped quote, not an empty string ending the literal."""
        out = self.assert_masked("a.sql", "SELECT 'it''s -- fine';\n-- gone\n")
        self.assertIn("it''s -- fine", out)
        self.assertNotIn("gone", out)

    def test_xml_comment_is_stripped(self) -> None:
        """HTML/XML comments carry the same claims as code comments."""
        out = self.assert_masked("a.html", "<p>keep</p><!-- gone -->\n")
        self.assertIn("keep", out)
        self.assertNotIn("gone", out)


class DispatchTest(unittest.TestCase):
    """Unsupported input must degrade loudly, never silently."""

    def test_unknown_language_is_flagged(self) -> None:
        """An unstripped file must say so in its manifest action."""
        _, action = strip_context.strip_source("a.weird", "# whatever\n")
        self.assertEqual(action, "copied-verbatim (unknown language)")

    def test_unparseable_python_is_flagged(self) -> None:
        """A tokenize failure degrades rather than raising."""
        _, action = strip_context.strip_source("a.py", "def (:\n")
        self.assertTrue(action.startswith("copied-verbatim"), action)

    def test_validation_rejects_a_stripper_that_deletes_code(self) -> None:
        """The mask check is the safety net for every stripper bug."""
        reason = strip_context.validate_strip("a.js", "const x = 1;\n", "const x\n")
        self.assertIsNotNone(reason)

    def test_validation_accepts_a_faithful_mask(self) -> None:
        """A correct strip must not be rejected."""
        self.assertIsNone(
            strip_context.validate_strip(
                "a.js", "let x = 1; // c\n", "let x = 1;     \n"
            )
        )


class DiffOutputTest(unittest.TestCase):
    """The stripped diff is the artifact the blind reviewer consumes."""

    def test_file_without_trailing_newline_yields_applicable_patch(self) -> None:
        """A missing final newline must not glue lines or file headers together."""
        with tempfile.TemporaryDirectory() as tmp:
            repo = Path(tmp)

            def run(*a: str) -> None:
                """Run a git command in the fixture repo."""
                subprocess.run(
                    ["git", "-C", str(repo), *a], check=True, capture_output=True
                )

            run("init", "-q", "-b", "main")
            run("config", "user.email", "t@example.com")
            run("config", "user.name", "t")
            (repo / "one.py").write_text("a = 1\nb = 2")  # no trailing newline
            (repo / "two.py").write_text("c = 3\n")
            run("add", "-A")
            run("commit", "-qm", "base")
            base = subprocess.run(
                ["git", "-C", str(repo), "rev-parse", "HEAD"],
                check=True,
                capture_output=True,
                text=True,
            ).stdout.strip()
            (repo / "one.py").write_text("a = 9\nb = 3")
            (repo / "two.py").write_text("c = 4\n")
            out = repo / "_out"
            rc = strip_context.main(
                ["diff", "--repo", str(repo), "--base", base, "--out", str(out)]
            )
            self.assertEqual(rc, 0)
            patch = (out / "stripped.diff").read_text()
            self.assertNotIn("b = 2+a = 9", patch)
            for line in patch.splitlines():
                self.assertFalse(
                    line.startswith("-") and "+" in line[1:] and "---" not in line,
                    f"glued diff line: {line!r}",
                )
            # --numstat parses the patch without consulting the worktree,
            # which the stripped text deliberately no longer matches.
            check = subprocess.run(
                [
                    "git",
                    "-C",
                    str(repo),
                    "apply",
                    "--numstat",
                    str(out / "stripped.diff"),
                ],
                capture_output=True,
                text=True,
                check=False,
            )
            self.assertEqual(check.returncode, 0, check.stderr)

    def test_untracked_file_is_included(self) -> None:
        """A newly added file is part of the change under review."""
        with tempfile.TemporaryDirectory() as tmp:
            repo = Path(tmp)

            def run(*a: str) -> None:
                """Run a git command in the fixture repo."""
                subprocess.run(
                    ["git", "-C", str(repo), *a], check=True, capture_output=True
                )

            run("init", "-q", "-b", "main")
            run("config", "user.email", "t@example.com")
            run("config", "user.name", "t")
            (repo / "one.py").write_text("a = 1\n")
            run("add", "-A")
            run("commit", "-qm", "base")
            base = subprocess.run(
                ["git", "-C", str(repo), "rev-parse", "HEAD"],
                check=True,
                capture_output=True,
                text=True,
            ).stdout.strip()
            (repo / "one.py").write_text("a = 2\n")
            (repo / "new.py").write_text('"""Doc."""\nb = 3\n')
            out = repo / "_out"
            strip_context.main(
                ["diff", "--repo", str(repo), "--base", base, "--out", str(out)]
            )
            import json

            manifest = json.loads((out / "manifest.json").read_text())
            paths = {entry["path"] for entry in manifest["files"]}
            self.assertIn("new.py", paths)
            self.assertNotIn("Doc.", (out / "head" / "new.py").read_text())


if __name__ == "__main__":
    unittest.main()
