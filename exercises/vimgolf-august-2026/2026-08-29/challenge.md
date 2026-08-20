# Replace repeatedly without losing the source

Yank the canonical value `30` once. Replace every timeout value with that yank, then remove the canonical line and its
comment.

Practice: `yiw` writes the yank to register `0` and, through `unnamedplus`, the pasteboard. Use
`ciw<C-r>0` or a visual put for each replacement. Your black-hole `c` mapping prevents the old timeouts from replacing
the source value.

Golf target: type `30` once at most. Prefer register `0` when you mean the last yank specifically.

## Key reference

| Keys        | Action                                                   |
|-------------|----------------------------------------------------------|
| `yiw`       | yank the inner word (also lands in register `0`)         |
| `"0`        | the yank register: last yank, never clobbered by deletes |
| `ciw<C-r>0` | change the word, insert the last yank in its place       |
| `viwp`      | select the inner word, replace it with a put             |
| `dd`        | delete the line (discards to `"_` in your setup)         |
