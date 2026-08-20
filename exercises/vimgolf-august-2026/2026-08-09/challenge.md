# Insert mode has its own keys

The three `env` lines are missing their `export ` prefix and the last one has a typo'd value. Add the prefixes and fix
`produciton` to `production` without leaving insert mode for the typo.

Practice: `I` inserts at the first non-blank, `A` appends at end of line, and inside insert mode `<C-w>` deletes the
word before the cursor — often faster than escaping to fix a slip.

Golf target: fix the typo with a single `<C-w>` inside insert mode.

## Key reference

| Keys             | Action                                            |
|------------------|---------------------------------------------------|
| `I` / `A`        | insert at first non-blank / append at end of line |
| `<C-w>` (insert) | delete the word before the cursor                 |
| `<C-u>` (insert) | delete everything typed on the line               |
| `j.`             | next line, repeat the same insertion              |
