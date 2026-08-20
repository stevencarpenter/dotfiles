# Precision before speed

Change `cursor_shape` to `block`, change `tab_width` to `4`, and change the backup directory to
`~/.local/state/editor/backups`. Preserve every other byte.

Practice: `w`, `b`, `e`, `ge`, `0`, `^`, `$`, `ciw`, `ci"`, and `C`. Prefer an operator plus a motion or text object
over entering visual mode.

Target: three edits. Golf target: no arrow keys and no repeated `h` or `l` runs.

## Key reference

| Keys       | Action                                          |
|------------|-------------------------------------------------|
| `w` / `b`  | forward / back to the next word start           |
| `e` / `ge` | forward / back to the nearest word end          |
| `0` / `^`  | column zero / first non-blank on the line       |
| `$`        | end of line                                     |
| `ciw`      | change inner word (cursor anywhere in the word) |
| `ci"`      | change the text inside the surrounding quotes   |
| `C`        | change from cursor to end of line               |
