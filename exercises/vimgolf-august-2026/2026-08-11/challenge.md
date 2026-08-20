# Replace mode and single characters

Fix the drifted column: the three version numbers must read `2.14.0`, `2.14.1`, and `2.15.0`
without disturbing alignment. Overwrite in place instead of delete-then-insert.

Practice: `r` replaces one character, `R` enters Replace mode and overtypes until `<Esc>`. Overwriting preserves column
alignment for free — nothing shifts.

Golf target: no `i`, `a`, or `c` today.

## Key reference

| Keys     | Action                                          |
|----------|-------------------------------------------------|
| `rx`     | replace the character under the cursor with `x` |
| `R`      | Replace mode: overtype until `<Esc>`            |
| `3rx`    | replace three characters with `xxx`             |
| `f.` `;` | hop dot to dot along a version string           |
