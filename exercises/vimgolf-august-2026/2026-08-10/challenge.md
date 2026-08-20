# Substitute on a range

Every `http://` in the mirrors block becomes `https://`, but the `legacy` mirror keeps plain http. Use a ranged
substitute, not a global one.

Practice: `:.,+2s/pat/rep/` on explicit lines, or select the lines with `V` and type `:s//`
(the range fills in as '<,'>). `&` repeats the last substitute on the current line.

Golf target: one `:s` invocation. Aug 21 will forbid `:%s` — learn the ranged form now.

## Key reference

| Keys                      | Action                                  |
|---------------------------|-----------------------------------------|
| `:s/pat/rep/`             | substitute on the current line          |
| `V` (lines) `:s/pat/rep/` | substitute across the visual selection  |
| `:.,+2s/…/`               | this line and the next two              |
| `&`                       | repeat the last substitute on this line |
| `:s//rep/`                | empty pattern reuses the last search    |
