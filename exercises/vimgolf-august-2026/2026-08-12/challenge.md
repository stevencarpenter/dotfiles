# Around versus inside

Three edits with opposite scopes: empty the `tags` value but keep its quotes, remove the
`labels` value including its quotes, and replace `enabled` and its value with `active = true`.

Practice: `i` objects select contents; `a` objects include the delimiters. `ci"` empties quotes, `da"` removes the
quoted thing and trailing space, `daw` takes the word plus a space.

Golf target: choose the right scope first try — no fixing up leftover quotes or spaces.

## Key reference

| Keys          | Action                                                  |
|---------------|---------------------------------------------------------|
| `ci"`         | change inside quotes (quotes survive)                   |
| `da"`         | delete around quotes (quotes and one adjacent space go) |
| `diw` / `daw` | delete inner word / word plus surrounding space         |
| `ct=`         | change up to (not including) the `=`                    |
