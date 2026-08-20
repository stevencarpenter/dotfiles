# Let delimiters select

Replace the contents of `allowedOwners` with `"stevencarpenter", "platform"`. Replace the entire
`timeouts` object with `{"connect": 5, "read": 30}`. Preserve the compact formatting.

Practice: `%`, `ci[`, `ca[`, `ci{`, `ca{`, `di(`, and quote text objects. Jump between matching delimiters with `%`
before editing.

Golf target: no character-by-character deletion and no visual mode.

## Key reference

| Keys          | Action                                          |
|---------------|-------------------------------------------------|
| `%`           | jump between matching `()`, `[]`, `{}`          |
| `ci[` / `ci{` | change inside the brackets / braces             |
| `ca[` / `ca{` | change the brackets / braces and their contents |
| `di(`         | delete inside the parentheses                   |
| `ci"`         | change the text inside the surrounding quotes   |
