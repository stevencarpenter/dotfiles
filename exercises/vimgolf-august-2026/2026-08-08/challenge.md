# Comment toggling is a motion

Comment out the whole `[canary]` block. Uncomment the `strict_host_checking` line. Your comment mappings come from
LazyVim's mini.comment-style bindings.

Practice: `gcc` toggles the current line, `gc` plus a motion toggles a range (`gcap` for the paragraph, `gc}` to the
blank line), and `.` repeats a toggle.

Golf target: one ranged toggle for the block, one line toggle for the uncomment.

## Key reference

| Keys   | Action                                            |
|--------|---------------------------------------------------|
| `gcc`  | toggle comment on the current line                |
| `gcap` | toggle comment across the paragraph               |
| `gc}`  | toggle comment from cursor to the next blank line |
| `.`    | repeat the last toggle                            |
