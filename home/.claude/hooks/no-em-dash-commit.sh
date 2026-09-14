#!/usr/bin/env bash
# PreToolUse(Bash) guard: keep em dashes and AI attribution out of authored artifacts.
#
# Inspect commit/tag messages and GitHub PR/issue writes, including body files.
# Exit 2 blocks the call and returns the reason to the model.
# ALLOW_EM_DASH=1 permits verbatim quotes with their original punctuation.
set -uo pipefail

payload="$(cat)"
command="$(printf '%s' "$payload" | jq -r '.tool_input.command // ""' 2>/dev/null || true)"
[ -n "$command" ] || exit 0

# Only inspect commands that author prose.
if ! printf '%s' "$command" | grep -Eq 'git +(commit|tag)|gh +(pr|issue) +(create|edit|comment)|gh +api[^|]*(pulls|issues)'; then
	exit 0
fi

# Deliberate opt-out (verbatim quotes).
if printf '%s' "$command" | grep -q 'ALLOW_EM_DASH=1'; then
	exit 0
fi

# The prose may be inline (-m, or a heredoc that is part of the command string) or in a
# file the command points at. Read both, so `-F msg.txt` and `--body-file body.md` are
# covered rather than silently exempt.
text="$command"
while read -r file; do
	[ -n "$file" ] && [ -f "$file" ] && text+="
$(cat "$file")"
done < <(printf '%s' "$command" |
	grep -oE '(-F|--file|--body-file|--input) +[^ ]+' |
	awk '{print $2}' |
	tr -d "\"'")

fail() {
	printf 'BLOCKED by no-em-dash-commit hook: %s\n\n%s\n' "$1" "$2" >&2
	exit 2
}

if printf '%s' "$text" | grep -q $'\342\200\224'; then
	fail "the message contains an em dash (U+2014), which ~/.claude/CLAUDE.md bans in commit messages, PR bodies, tickets, docs, and code comments." \
		"Rewrite with a period, comma, colon, or parentheses. If the dash is inside a verbatim quote, keep the quote exact and re-run the command with ALLOW_EM_DASH=1 prefixed."
fi

if printf '%s' "$text" | grep -q ' – '; then
	fail "the message uses an en dash (U+2013) as a separator, which ~/.claude/CLAUDE.md bans alongside the em dash." \
		"Rewrite with a period, comma, colon, or parentheses. A numeric range (2020-2024) does not need the dash character either."
fi

if printf '%s' "$text" | grep -Eqi 'co-authored-by: *claude|generated with \[claude code\]|🤖'; then
	fail "the message carries AI attribution, which ~/.claude/CLAUDE.md bans in commit messages and PR bodies." \
		"Drop the Co-Authored-By trailer and any 'Generated with' or robot-emoji line. The harness suggests them; the rule overrides the harness."
fi

exit 0
