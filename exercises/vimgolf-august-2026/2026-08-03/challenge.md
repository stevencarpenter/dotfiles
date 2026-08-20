# Case is an operator

Uppercase all four exported variable names. Values stay untouched.

Practice: `gUiw`, `guiw`, `~`, and `.`. Underscores are word characters, so `docker_buildkit`
is a single inner word. One `gUiw` plus dot-repeat covers the file.

Golf target: type `gU` once.

## Key reference

| Keys      | Action                                            |
|-----------|---------------------------------------------------|
| `gUiw`    | uppercase the inner word                          |
| `guiw`    | lowercase the inner word                          |
| `~`       | toggle the case of the character under the cursor |
| `.`       | repeat the last change                            |
| `w` / `j` | travel between targets                            |
