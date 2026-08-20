# Ramp capstone

Everything from the first two weeks in one file: bump the `revision` number, uppercase the
`env` value, join the wrapped `args` line, comment out the `[debug]` block, and append
` # reviewed` to the three `allow` lines.

Practice: pick the cheapest tool per edit — `<C-a>`, `gUiw`, `J`, `gcap`, and `A…<Esc>` with
`j.`. Five edits, five different mechanics, no visual mode required anywhere.

Golf target: no edit uses more than four keystrokes of travel.

## Key reference

| Keys                | Action                                         |
|---------------------|------------------------------------------------|
| `<C-a>`             | increment the number under or after the cursor |
| `gUiw`              | uppercase the inner word                       |
| `J`                 | join the wrapped line up with one space        |
| `gcap`              | toggle comment across the paragraph            |
| `A…<Esc>` then `j.` | append once, repeat down the aligned lines     |
