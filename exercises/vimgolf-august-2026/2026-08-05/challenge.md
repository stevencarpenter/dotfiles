# Indent as a block decision

Every line under `services:` is one level too shallow, and the port list item needs one level more than that. Shift the
whole block once, then give the list item its extra level.

Practice: `>>`, `<<`, visual `V` plus `>`, and `.`. A shift repeated with `.` costs one key.

Golf target: one visual shift for the block, one extra shift for the list item.

## Key reference

| Keys          | Action                                                        |
|---------------|---------------------------------------------------------------|
| `>>` / `<<`   | indent / dedent the current line by one shiftwidth            |
| `V}` then `>` | select to the blank line, indent the whole selection          |
| `.`           | repeat the last shift                                         |
| `=`           | reindent by the filetype's rules (over a motion or selection) |
