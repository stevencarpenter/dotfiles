# Pasteboard input without register accidents

Run `scripts/vim-golf-august copy 26` before `play 26`. Replace both `TODO` values with the exact pasteboard payload. Do
not type the payload.

Practice: `ci"<C-r>+` inserts the `+` register while remaining in Insert mode. `"+p` puts it from Normal mode. Because
your `c` mapping uses the black-hole register, changing either placeholder does not overwrite the pasteboard.

Golf target: use the pasteboard twice, with no re-copy and no raw payload input.

## Key reference

| Keys     | Action                                                    |
|----------|-----------------------------------------------------------|
| `"+`     | the register wired to the macOS pasteboard                |
| `"+p`    | put the pasteboard contents after the cursor              |
| `<C-r>+` | insert the pasteboard while in Insert mode                |
| `ci"`    | change inside the quotes (discards to `"_` in your setup) |
