# Treat Yanky as edit history

Yank the inner text of `alpha`, then `beta`, then `gamma`. Set the three deployment rings to alpha,
beta, and gamma in that order. Remove the seed block afterward.

Practice: `yi"`, visual put, `<leader>p` for Yanky history, and `[y` or `]y` immediately after a put
to cycle the inserted value. The picker is valid, but cycling is faster when the desired yank is
near the top of the ring.

Golf target: type none of the ring names into a target.

## Key reference

| Keys | Action |
| --- | --- |
| `yi"` | yank the text inside the quotes |
| `viwp` | select the inner word, replace it with the last yank |
| `<leader>p` | open the Yanky yank-history picker |
| `[y` / `]y` | right after a put: swap it for an older / newer yank |
