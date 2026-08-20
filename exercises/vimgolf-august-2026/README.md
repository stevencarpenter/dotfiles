# Vim Golf, August 2026

Each challenge starts from a small config tree and has one exact target. `play` creates a persistent
worktree outside the repo, opens it with your Neovim config, validates it on exit, and records the
raw bytes Neovim wrote to its input log. The byte count is a personal trend, not a portable VimGolf
score. Special keys can occupy more than one byte.

```bash
scripts/vim-golf-august list
scripts/vim-golf-august play 19
scripts/vim-golf-august check 19
scripts/vim-golf-august diff 19
scripts/vim-golf-august reset 19
```

Use `play` without a day to select the current date. Run `show DAY` to reread the task. Day 26 has
an explicit `copy 26` step that puts its payload on the macOS pasteboard.

The target files are committed under each day's `expected/` directory for deterministic validation.
Looking at them before solving the task defeats the exercise.

## Setup-specific rules

- `d`, `c`, `x`, `s`, and their uppercase forms use the black-hole register in your mappings.
- `y`, `p`, and `P` are provided by Yanky. `<leader>p` opens yank history, and `[y` or `]y` cycles
  the most recent put through that history.
- `clipboard=unnamedplus` makes the unnamed register share the macOS pasteboard.
- `s` and `S` replace LazyVim's default Flash bindings after `VeryLazy`. The course does not claim
  Flash is available on those keys.
- LazyVim remaps bare `j` and `k` to display-line movement. Counts such as `8j` still move by file
  lines.

## Curriculum

Start each session with five minutes in `:VimBeBetter`, using the named game, then run the dated
challenge.

Days 1 through 18 are the ramp: core mechanics one at a time, each day one tool. Days 19 through 31 assume the ramp and
combine tools. Grinding several ramp days in one sitting works; they are sized at three to five edits each.

| Date   | Focus                                                      | VimBeBetter warm-up  |
|--------|------------------------------------------------------------|----------------------|
| Aug 1  | survival keys, counts, insert, replace-char, undo          | `hjkl`               |
| Aug 2  | linewise yank, put, delete, open                           | `words`              |
| Aug 3  | case operators and dot repeat                              | `case-converter`     |
| Aug 4  | joining lines                                              | `join-lines`         |
| Aug 5  | indent operators                                           | `indent-master`      |
| Aug 6  | increment and decrement                                    | `increment-game`     |
| Aug 7  | paragraph text objects                                     | `text-objects-basic` |
| Aug 8  | comment toggling as an operator                            | `comment-toggle`     |
| Aug 9  | insert-mode editing keys                                   | `speed-editing`      |
| Aug 10 | ranged `:s` substitute                                     | `substitute-basic`   |
| Aug 11 | replace mode, column-preserving edits                      | `visual-precision`   |
| Aug 12 | inside vs around text objects                              | `ci`                 |
| Aug 13 | whole-word search with selective landings                  | `word-boundaries`    |
| Aug 14 | yanking blocks across the file                             | `relative`           |
| Aug 15 | reusing the last insertion                                 | `dot-repeat`         |
| Aug 16 | yank register vs black-hole deletes                        | `refactor-race`      |
| Aug 17 | undo tree as navigation                                    | `whackamole`         |
| Aug 18 | ramp capstone, tool choice per edit                        | `vim-golf`           |
| Aug 19 | word and line motions, operator plus motion                | `word-boundaries`    |
| Aug 20 | `f`, `F`, `t`, `T`, `;`, `,`, quote text objects           | `find-char`          |
| Aug 21 | `/`, `n`, `N`, `*`, `cgn`, dot repeat                      | `dot-repeat`         |
| Aug 22 | delimiter text objects and `%`                             | `text-objects-basic` |
| Aug 23 | `gg`, `G`, counts, `{`, `}`, marks, jump list              | `relative`           |
| Aug 24 | counts, dot repeat, linewise operations                    | `dot-repeat`         |
| Aug 25 | visual block edits for aligned config                      | `visual-precision`   |
| Aug 26 | macOS pasteboard and unnamed register                      | `speed-editing`      |
| Aug 27 | named registers and black-hole changes                     | `text-objects-basic` |
| Aug 28 | Yanky history and cycling puts                             | `speed-editing`      |
| Aug 29 | replacing selections without losing yanked text            | `refactor-race`      |
| Aug 30 | recording and replaying macros                             | `macro-recorder`     |
| Aug 31 | multi-file capstone with search, Harpoon, and file pickers | `vim-golf`           |
