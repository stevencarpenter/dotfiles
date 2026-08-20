# Registers survive your black-hole maps

Yank the good cipher list once. Replace both weak cipher lists with it, then delete the
`# reference` line. The deletions between the puts must not cost you the yank.

Practice: this is the payoff of your `d`/`c` black-hole remaps — in stock vim the first replacement would clobber the
unnamed register and the second put would paste garbage. Here
`yiw`/`y$` stays live across every delete. `"0p` is the belt-and-suspenders form.

Golf target: one yank, two puts, zero re-yanks.

## Key reference

| Keys           | Action                                                           |
|----------------|------------------------------------------------------------------|
| `y$`           | yank to end of line                                              |
| `viwp` / `v$p` | select then overwrite with the last yank                         |
| `"0p`          | put from the yank register explicitly                            |
| `dd`           | delete the line (black-hole in your setup, so the yank survives) |
