# Numbers move themselves

Bump the port to `9001`, the pool size to `12`, and drop the debug verbosity to `0`. Do not retype any number.

Practice: `<C-a>` increments the number under or after the cursor, `<C-x>` decrements, and both take counts. Dial
extends these to dates and booleans, but today is plain integers.

Golf target: no digit typed anywhere.

## Key reference

| Keys              | Action                                               |
|-------------------|------------------------------------------------------|
| `<C-a>` / `<C-x>` | increment / decrement the next number on the line    |
| `4<C-a>`          | add four                                             |
| `10<C-x>`         | subtract ten                                         |
| `f9`              | jump onto the next `9` when two numbers share a line |
