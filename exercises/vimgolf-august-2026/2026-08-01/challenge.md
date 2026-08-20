# Survival keys

Fix three things: `welcom` becomes `welcome`, `retries` becomes `5`, and the shell becomes
`/bin/zsh`. Preserve every other byte.

Practice: `h`, `j`, `k`, `l`, counts like `3j`, `i`, `a`, `ea`, `r`, `<Esc>`, `u`, and `<C-r>`. Navigate with counted
line jumps, not held keys.

Target: three edits. Golf target: never press the same movement key twice in a row.

## Key reference

| Keys          | Action                                          |
|---------------|-------------------------------------------------|
| `h j k l`     | left, down, up, right                           |
| `3j`          | three lines down (counts work on any motion)    |
| `i` / `a`     | insert before / after the cursor                |
| `ea`          | jump to the end of the word, then append        |
| `r5`          | replace the character under the cursor with `5` |
| `u` / `<C-r>` | undo / redo                                     |
