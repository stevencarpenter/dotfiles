# Yank travels, delete does not

Copy the whole `[postgres]` block to the bottom of the file, rename the copy `[postgres_replica]`, and change its port
to `5433`. The original stays untouched.

Practice: `yap` yanks the paragraph, `G` jumps to the end, `p` puts. Because your setup shares the unnamed register with
the pasteboard, the block is also now on your system clipboard.

Golf target: one yank, one jump, one put, two small edits.

## Key reference

| Keys       | Action                                            |
|------------|---------------------------------------------------|
| `yap`      | yank around the paragraph (block plus blank line) |
| `G` / `gg` | last / first line                                 |
| `p`        | put below the cursor line                         |
| `ciw`      | rename a word in place                            |
| `<C-a>`    | increment the port instead of retyping it         |
