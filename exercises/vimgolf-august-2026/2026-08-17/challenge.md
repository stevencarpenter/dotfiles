# Undo is navigation too

The file has three deliberate mistakes stacked on one line history: fix them, but if an edit goes wrong, treat `u` as a
precise tool, not a panic button. Change `debug` to `info`,
`0.0.0.0` to `127.0.0.1`, and delete the duplicate `workers` line (keep the first).

Practice: `u` undoes one change, `<C-r>` redoes, `g-`/`g+` move through undo history by time, and `:earlier 30s` rewinds
half a minute. Make an edit, deliberately undo it, redo it.

Golf target: solve it, then `u` all the way back to the start and replay with `<C-r>` — the validator only sees the
final buffer, so ending redone-forward still passes.

## Key reference

| Keys           | Action                                          |
|----------------|-------------------------------------------------|
| `u` / `<C-r>`  | undo / redo one change                          |
| `g-` / `g+`    | step back / forward through undo states by time |
| `:earlier 30s` | rewind the buffer thirty seconds                |
| `:later 1m`    | replay forward one minute                       |
