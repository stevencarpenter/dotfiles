# Find characters, do not crawl

On each service line, change only the quoted port: `8080` to `8088`, `5432` to `5433`, and `6379`
to `6380`.

Practice: `f`, `F`, `t`, `T`, `;`, `,`, and `ci"`. Use character-find motions to reach delimiters,
then let the quote text object define the edit.

Golf target: do not use `/`, arrow keys, or visual mode.

## Key reference

| Keys | Action |
| --- | --- |
| `fx` / `Fx` | jump onto the next / previous `x` on the line |
| `tx` / `Tx` | jump to just before the next / after the previous `x` |
| `;` / `,` | repeat the last f/F/t/T in the same / opposite direction |
| `ci"` | change the text inside the surrounding quotes |
