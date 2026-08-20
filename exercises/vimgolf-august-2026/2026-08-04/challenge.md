# Join, do not retype

Both wrapped values must become single lines: the description and the command each join into one line with a single
space at the seam.

Practice: `J` and `gJ`. `J` joins the next line up, replacing the line break and leading whitespace with one space,
which is exactly the seam these values need.

Golf target: two keystrokes of `J` total, plus travel.

## Key reference

| Keys | Action                                                             |
|------|--------------------------------------------------------------------|
| `J`  | join the next line, collapsing its leading whitespace to one space |
| `gJ` | join with no inserted space                                        |
| `3J` | join three lines into one                                          |
| `}`  | jump to the next blank line                                        |
