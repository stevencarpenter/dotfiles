# Visual block where columns are the object

Change the third octet in all five aligned addresses from `10` through `14` to `42`. Then append
` # migrated` to all five lines at the same column.

Practice: `<C-v>`, vertical movement, `c`, `I`, `A`, and `<Esc>`. This is the case where visual block mode is more
expressive than five operator-motion edits.

Golf target: one block change for the octets and one block append for the comments.

## Key reference

| Keys         | Action                                                      |
|--------------|-------------------------------------------------------------|
| `<C-v>`      | start visual block (column) selection                       |
| `j` / `k`    | extend the block down / up                                  |
| `c`          | change the block; typing applies to all lines on `<Esc>`    |
| `I`          | insert at the left edge of the block, all lines on `<Esc>`  |
| `A`          | append at the right edge of the block, all lines on `<Esc>` |
| `$` in block | extend the block to each line's end (ragged right edge)     |
