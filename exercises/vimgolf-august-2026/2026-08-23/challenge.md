# Move by structure and destination

Change `ripgrep` to `ripgrep-all`, change `python313` to `python314`, and change the final `bat` to
`btop`. The targets are intentionally far apart.

Practice: `gg`, `G`, a line-number jump such as `17G`, `{`, `}`, `m{letter}`, `'{letter}`, `<C-o>`,
and `<C-i>`. Set a mark before the first long jump, then use the jump list to revisit it.

Golf target: do not hold `j` or `k`. A count or structural jump is one decision.

## Key reference

| Keys | Action |
| --- | --- |
| `gg` / `G` | first / last line of the file |
| `17G` | jump to line 17 |
| `{` / `}` | previous / next blank-line-separated block |
| `ma` | set mark `a` at the cursor |
| `'a` | jump to the line of mark `a` |
| `<C-o>` / `<C-i>` | back / forward through the jump list |
