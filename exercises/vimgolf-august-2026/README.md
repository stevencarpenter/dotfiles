# Vim Golf, August 19 to 31, 2026

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

| Date | Focus | VimBeBetter warm-up |
| --- | --- | --- |
| Aug 19 | word and line motions, operator plus motion | `word-boundaries` |
| Aug 20 | `f`, `F`, `t`, `T`, `;`, `,`, quote text objects | `find-char` |
| Aug 21 | `/`, `n`, `N`, `*`, `cgn`, dot repeat | `dot-repeat` |
| Aug 22 | delimiter text objects and `%` | `text-objects-basic` |
| Aug 23 | `gg`, `G`, counts, `{`, `}`, marks, jump list | `relative` |
| Aug 24 | counts, dot repeat, linewise operations | `dot-repeat` |
| Aug 25 | visual block edits for aligned config | `visual-precision` |
| Aug 26 | macOS pasteboard and unnamed register | `speed-editing` |
| Aug 27 | named registers and black-hole changes | `text-objects-basic` |
| Aug 28 | Yanky history and cycling puts | `speed-editing` |
| Aug 29 | replacing selections without losing yanked text | `refactor-race` |
| Aug 30 | recording and replaying macros | `macro-recorder` |
| Aug 31 | multi-file capstone with search, Harpoon, and file pickers | `vim-golf` |
