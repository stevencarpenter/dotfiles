# The last insert is reusable

Every host needs the same suffix `.lab.internal` appended, and the last line needs the same text inserted mid-line after
`bastion`. Type the suffix once.

Practice: an `A…<Esc>` insertion becomes the dot-repeatable unit; `j.` walks it down the aligned lines. For the mid-line
case, `f `, then `i`, then `<C-a>` (insert mode) re-inserts the last inserted text.

Golf target: the suffix crosses your fingers exactly once.

## Key reference

| Keys             | Action                                                 |
|------------------|--------------------------------------------------------|
| `A…<Esc>`        | append at line end; the insertion becomes the `.` unit |
| `j.`             | next line, repeat the same append                      |
| `<C-a>` (insert) | re-insert the text of the last insertion               |
| `f<Space>`       | land just before the space, mid-line                   |
| `".p`            | the `.` register also holds the last inserted text     |
