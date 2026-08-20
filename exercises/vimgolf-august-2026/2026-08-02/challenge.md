# Lines are the unit

Duplicate the `home` backup line directly below itself and change the copy's target to `etc`. Delete the `temp-cleanup`
line entirely.

Practice: `yy`, `p`, `P`, `dd`, `o`, `O`, and `$`. Your `dd` discards into the black-hole register, so deleting the
cleanup line cannot disturb the line you yanked.

Golf target: one `yy`, one `p`, one word change, one `dd`.

## Key reference

| Keys      | Action                                           |
|-----------|--------------------------------------------------|
| `yy`      | yank the current line                            |
| `p` / `P` | put the yanked line below / above                |
| `dd`      | delete the line (discards to `"_` in your setup) |
| `o` / `O` | open a new line below / above and insert         |
| `$`       | end of line                                      |
| `ciw`     | change inner word                                |
