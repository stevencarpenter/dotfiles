# The paragraph is a text object

Delete the entire `[experimental]` block, including its trailing blank line. Then swap the order of the two remaining
feature lines inside `[stable]`.

Practice: `dap` takes the whole blank-line-delimited paragraph in one motion. `dip` leaves the surrounding blanks. Swap
adjacent lines with `dd` then `p` — but your `dd` is black-hole, so use `yy` `j` `Vp` or move the other line instead.

Golf target: one `dap` for the block. Notice how the black-hole `dd` changes the classic swap.

## Key reference

| Keys           | Action                                                              |
|----------------|---------------------------------------------------------------------|
| `dap`          | delete around the paragraph (block plus its blank line)             |
| `dip`          | delete inside the paragraph (block only)                            |
| `{` / `}`      | jump to the previous / next blank line                              |
| `yy` then `Vp` | yank a line, then overwrite another line with it                    |
| `ddp`          | classic line swap — broken by your black-hole `dd`; route around it |
