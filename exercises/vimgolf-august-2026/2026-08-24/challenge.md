# Make one edit repeatable

Turn the first six feature flags on. Leave `dangerous_cleanup` off. Then duplicate the final
`telemetry_sample_rate` line twice so it appears three times.

Practice: counts, `c`, `.`, `yy`, `2p`, and `6G`. Search once and repeat the same change rather than
retyping it. Your `c` mapping discards replaced text, so the new value remains safe to repeat.

Golf target: type `true` once and use a count for the duplicated lines.

## Key reference

| Keys | Action |
| --- | --- |
| `cw` / `ciw` | change to word end / change inner word |
| `.` | repeat the last change at the cursor |
| `yy` | yank the current line |
| `2p` | put the yanked line(s) twice below the cursor |
| `6G` | jump to line 6 |
