# One search, many precise landings

Rename the `metrics` listener to `telemetry` in all four places it appears, but leave the word `metrics` inside the
comment untouched.

Practice: `*` on the word under the cursor searches for it as a whole word, `n` walks matches, and `ciw` + `n` + `.`
converts each landing into one repeat. Skip a match by pressing `n` again.

Golf target: type `telemetry` once. The comment match is skipped, not fixed afterward.

## Key reference

| Keys           | Action                                                          |
|----------------|-----------------------------------------------------------------|
| `*`            | search forward for the whole word under the cursor              |
| `n` / `N`      | next / previous match                                           |
| `ciw` then `.` | change the word once, repeat the identical change per landing   |
| `cgn`          | alternative: change-next-match, repeatable without moving first |
