# Encode the edit as a macro

For every worker, change `enabled` to `true` and `timeout` to `30`. Preserve names and concurrency.

Practice: `qa` starts recording into register `a`, `q` stops, `@a` replays, and `@@` repeats the last macro. Build a
macro that edits one whole worker line and lands on the next line. Replay it with a count.

Golf target: one recorded edit followed by `5@a` or an equivalent counted replay.

## Key reference

| Keys                 | Action                                                      |
|----------------------|-------------------------------------------------------------|
| `qa`                 | start recording keystrokes into register `a`                |
| `q`                  | stop recording                                              |
| `@a`                 | replay register `a`                                         |
| `@@`                 | replay the last-replayed macro                              |
| `5@a`                | replay register `a` five times                              |
| `0` / `j` in a macro | start-of-line / next-line, keeps the replay position-stable |
