# Named registers are small variables

Yank `edge.internal` into register `h` and `8443` into register `p`. Delete the entire seed block, including its heading
and blank line. Fill both targets from those named registers.

Practice: `"hyiw`, `"pyiw`, `"hp`, and Insert-mode `<C-r>h`. Your bare `d` discards into `"_`, so deleting the seed
block will not disturb the named registers.

Golf target: type neither stored value after the initial yanks.

## Key reference

| Keys         | Action                                            |
|--------------|---------------------------------------------------|
| `"hyiw`      | yank the inner word into register `h`             |
| `"hp`        | put the contents of register `h` after the cursor |
| `<C-r>h`     | insert register `h` while in Insert mode          |
| `dap` / `dj` | delete a paragraph / this line and the next       |
| `:reg h p`   | inspect what registers `h` and `p` hold           |
