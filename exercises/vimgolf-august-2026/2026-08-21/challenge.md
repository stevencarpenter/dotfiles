# Search as a motion

Replace every `old.internal` with `edge.internal`. Change only the first three occurrences of
`retry = false` to `retry = true`; the health-check value stays false.

Practice: `/`, `n`, `N`, `*`, `#`, `cgn`, and `.`. A strong route is to search once, change the next match with `cgn`,
then repeat with `.`. Counts are allowed.

Golf target: no `:%s` today. The point is repeatable interactive editing.

## Key reference

| Keys      | Action                                                          |
|-----------|-----------------------------------------------------------------|
| `/text`   | search forward for `text`                                       |
| `n` / `N` | next / previous match                                           |
| `*` / `#` | search forward / backward for the word under the cursor         |
| `cgn`     | change the next match of the last search, stays repeatable      |
| `.`       | repeat the last change (after `cgn`: change the next match too) |
