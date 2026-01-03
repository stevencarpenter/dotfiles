# Neovim Hotkey Reference

This single, consolidated reference lists local keymap changes (added or overridden mappings) at the top so you can quickly see what differs from LazyVim's defaults. A summarized reference of the LazyVim defaults follows for quick lookup.

Notes:
- Local mappings and overrides live under `dot_config/nvim/lua/plugins` in this repo (chezmoi source directory).
- The full upstream LazyVim source contains the canonical defaults; this document summarizes those defaults so you don't need snapshot copies in this repo.

## Local overrides & additions (modified from default)

The table below lists mappings that were added or that intentionally change LazyVim's defaults. If a mapping in your local config re-declares a default but does not change its behaviour, it is not listed here.

| Mode | Keys | Action | Diff from default | Location |
| --- | --- | --- | --- | --- |
| Normal | `<leader>cl` | Toggle Trouble LSP view (`:Trouble lsp toggle focus=false win.position=right`) | Overrides LazyVim's default `<leader>cl` (opens LSP info / Snacks LSP picker). |
| Normal | `<leader>fp` | Find plugin files via Telescope — uses `require('lazy.core.config').options.root` as the cwd. | New mapping (not present in LazyVim defaults). |

Note: The local `example.lua` spec also re-declares several Trouble bindings (e.g. `<leader>xx`, `<leader>xX`, `<leader>cs`, `<leader>xL`, `<leader>xQ`). Those are intentionally kept to ensure Trouble is used for those actions but they are identical to LazyVim defaults, so they are not included above.

## Defaults (summarized)

The remainder of this document summarizes the default keymaps provided by the LazyVim starter configuration and commonly used extras. Use this as a reference — the full upstream source is available from the LazyVim project.

| Modes | Keys | Action | Notes |
| --- | --- | --- | --- |
| Normal | ' ' (space) | **LEADER** | The nvim leader key referenced as <leader> below. |
| Normal/Visual | `j`, `<Down>` | Move cursor down, respecting wrapped lines when no count is given. | Wrap-aware vertical motion. |
| Normal/Visual | `k`, `<Up>` | Move cursor up, respecting wrapped lines when no count is given. | Wrap-aware vertical motion. |
| Normal | `<C-h>` / `<C-j>` / `<C-k>` / `<C-l>` | Focus the left, lower, upper, or right window. | Remaps the standard window movement keys. |
| Normal | `<C-Up>` / `<C-Down>` | Increase or decrease the current window height by 2 lines. | Works with any split. |
| Normal | `<C-Left>` / `<C-Right>` | Decrease or increase the current window width by 2 columns. | Works with any split. |
| Normal | `<A-j>` / `<A-k>` | Move the current line (or selection count) down or up. | Uses `:move` for stable reindentation. |
| Insert | `<A-j>` / `<A-k>` | Move the current line down or up while staying in insert mode. | Temporarily leaves insert to move the line. |
| Visual | `<A-j>` / `<A-k>` | Move the visual selection down or up, then reselect it. | Preserves indentation after moving. |
| Normal | `<S-h>` / `<S-l>` or `[b` / `]b` | Switch to the previous or next buffer. | Provides both Shift+direction and bracket variants. |
| Normal | `<leader>bb` or `<leader>\`` | Jump to the alternate buffer. | Uses `:e #`. |
| Normal | `<leader>bd` | Delete the current buffer. | Uses Snacks buffer deletion helper. |
| Normal | `<leader>bo` | Close all other buffers. | Snacks buffer deletion helper. |
| Normal | `<leader>bD` | Delete the current buffer and its window. | Uses bare `:bd`. |
| Insert/Normal/Select | `<Esc>` | Exit to normal mode, stop active snippets, and clear search highlight. | Replaces default escape behavior. |
| Normal | `<leader>ur` | Clear search highlight, refresh diffs, and redraw the screen. | Mirrors `:nohlsearch` + refresh helpers. |
| Normal/Visual/Operator | `n` / `N` | Jump to the next or previous search result and unfold the match. | Provides saner search navigation. |
| Insert | `,`, `.`, `;` | Insert character and create an undo break point. | Improves undo granularity while typing. |
| Insert/Visual/Normal/Select | `<C-s>` | Save the current file and return to normal mode. | Works in insert and visual modes. |
| Normal | `<leader>K` | Trigger the keyword program (`:help K`). | Runs `K` without leaving normal mode. |
| Visual | `<` / `>` | Shift indentation left or right while keeping the selection. | Applies `gv` to reselect. |
| Normal | `gco` / `gcO` | Add a commented line below or above the current line. | Builds on `Comment.nvim` mappings. |
| Normal | `<leader>l` | Open Lazy's plugin manager UI. | Runs `:Lazy`. |
| Normal | `<leader>fn` | Create a new empty buffer. | Runs `:enew`. |
| Normal | `<leader>xl` | Toggle the location list window. | Falls back to opening on errors. |
| Normal | `<leader>xq` | Toggle the quickfix list window. | Falls back to opening on errors. |
| Normal | `[q` / `]q` | Jump to the previous or next quickfix entry. | Works even when Trouble is open. |
| Normal/Visual | `<leader>cf` | Format the current buffer or selection. | Forces formatting through LazyVim's helper. |
| Normal | `<leader>cd` | Show diagnostics for the current line. | Opens a floating diagnostic window. |
| Normal | `[d` / `]d` | Jump to the previous or next diagnostic. | Opens floats on arrival. |
| Normal | `[e` / `]e` | Jump to the previous or next error-level diagnostic. | Filters severity to `ERROR`. |
| Normal | `[w` / `]w` | Jump to the previous or next warning-level diagnostic. | Filters severity to `WARN`. |
| Normal | `<leader>uf` / `<leader>uF` | Toggle automatic formatting (buffer only or globally). | Provided by Snacks toggles. |
| Normal | `<leader>us` | Toggle spelling for the current buffer. | Snacks option toggle. |
| Normal | `<leader>uw` | Toggle soft line wrapping. | Snacks option toggle. |
| Normal | `<leader>uL` / `<leader>ul` | Toggle relative line numbers or the absolute/relative hybrid display. | Snacks line-number helpers. |
| Normal | `<leader>ud` | Enable or disable diagnostics display. | Snacks diagnostic toggle. |
| Normal | `<leader>uc` | Toggle conceal level between 0 and the configured default. | Snacks option toggle. |
| Normal | `<leader>uA` | Toggle the tabline visibility. | Snacks option toggle. |
| Normal | `<leader>uT` | Toggle Tree-sitter highlighting. | Snacks toggle helper. |
| Normal | `<leader>ub` | Toggle between light and dark background. | Snacks option toggle. |
| Normal | `<leader>uD` | Toggle dimming of inactive portions of the buffer. | Snacks visual toggle. |
| Normal | `<leader>ua` | Toggle animated UI effects. | Snacks toggle helper. |
| Normal | `<leader>ug` | Toggle indentation guides. | Snacks indent toggle. |
| Normal | `<leader>uS` | Toggle smooth scrolling enhancements. | Snacks scroll toggle. |
| Normal | `<leader>dpp` / `<leader>dph` | Toggle the Snacks profiler and its highlight overlay. | Performance diagnostics. |
| Normal | `<leader>uh` | Toggle LSP inlay hints (when supported). | Uses Snacks helper gated on server support. |
| Normal | `<leader>gg` / `<leader>gG` | Launch Lazygit in the project root or current working directory. | Requires `lazygit` executable. |
| Normal | `<leader>gL` | Open the Snacks git log picker for the current directory. | Git history helper. |
| Normal | `<leader>gb` | Show line blame history in a picker. | Git log for the current line. |
| Normal | `<leader>gf` | Show git history for the current file. | File-focused log picker. |
| Normal | `<leader>gl` | Show git history rooted at the project git directory. | Project git log. |
| Normal/Visual | `<leader>gB` | Open the current selection in the default git remote viewer. | Snacks gitbrowse helper. |
| Normal/Visual | `<leader>gY` | Copy the remote URL for the selection to the clipboard. | Git browse helper without opening. |
| Normal | `<leader>qq` | Quit all Neovim windows. | Issues `:qa`. |
| Normal | `<leader>ui` | Inspect highlight groups under the cursor. | Calls `vim.show_pos()`. |
| Normal | `<leader>uI` | Inspect the syntax tree at the cursor and enter insert mode. | Uses Tree-sitter inspector. |
| Normal | `<leader>L` | Open the LazyVim changelog browser. | Uses Snacks news helper. |
| Normal | `<leader>fT` / `<leader>ft` | Open a floating terminal in the CWD or project root. | Snacks terminal helper. |
| Normal/Terminal | `<C-/>` or `<C-_>` | Toggle the floating terminal scoped to the project root. | Snacks terminal helper. |
| Normal | `<leader>-` / `<leader>|` | Split the window horizontally or vertically. | Remaps to `:split`/`:vsplit`. |
| Normal | `<leader>wd` | Close the current window. | Remaps `<C-W>c`. |
| Normal | `<leader>wm` / `<leader>uZ` | Toggle window zoom (maximize) and its UI toggle alias. | Snacks zoom helper. |
| Normal | `<leader>uz` | Toggle Zen mode for distraction-free editing. | Snacks zen helper. |
| Normal | `<leader><tab>l` / `<leader><tab>f` | Jump to the last or first tab. | Tab management helpers. |
| Normal | `<leader><tab><tab>` | Open a new tab. | Creates a fresh tabpage. |
| Normal | `<leader><tab>]` / `<leader><tab>[` | Move to the next or previous tab. | Tab cycling helpers. |
| Normal | `<leader><tab>o` | Close all other tabs. | Runs `:tabonly`. |
| Normal | `<leader><tab>d` | Close the current tab. | Runs `:tabclose`. |

## Built-in Plugin Keymaps

These bindings come from LazyVim's default plugin specifications that ship with the starter configuration. They are grouped by plugin for quick scanning.

### Grug Far (multi-file search)

Keymaps defined in `lazyvim/plugins/editor.lua` launch search-and-replace workflows.

| Modes | Keys | Action |
| --- | --- | --- |
| Normal/Visual | `<leader>sr` | Open the Grug Far search UI, pre-filtered to the current file extension when applicable. |

### Flash (enhanced jump/search)

LazyVim wires Flash for rapid navigation across multiple modes.

| Modes | Keys | Action |
| --- | --- | --- |
| Normal/Visual/Operator | `s` | Invoke Flash jump targeting with label hints. |
| Normal/Operator/Visual | `S` | Start Flash using Treesitter scopes to jump semantically. |
| Operator-pending | `r` | Remote Flash—jump from one window to another while targeting. |
| Operator/Visual | `R` | Treesitter-powered search selection. |
| Command-line | `<C-s>` | Toggle Flash assistance inside searches. |
| Normal/Operator/Visual | `<C-Space>` | Simulate Treesitter incremental selection via Flash. |

### which-key (keymap discovery)

which-key adds helper chords for revealing mappings.

| Modes | Keys | Action |
| --- | --- | --- |
| Normal | `<leader>?` | Show buffer-local keymaps in which-key. |
| Normal | `<C-w><Space>` | Enter the window-management which-key hydra. |

### Snacks Toolkit (utility helpers)

The Snacks utility plugin exposes scratch buffers, profiler tools, and terminal navigation aids.

| Modes | Keys | Action |
| --- | --- | --- |
| Normal | `<leader>.` | Toggle the ephemeral scratch buffer picker. |
| Normal | `<leader>S` | Select from existing scratch buffers. |
| Normal | `<leader>dps` | Open the Snacks profiler scratch buffer. |
| Terminal | `<C-h>` / `<C-j>` / `<C-k>` / `<C-l>` | Navigate between windows from a Snacks terminal. |
| Terminal/Normal | `<C-/>` / `<C-_>` | Hide the focused Snacks terminal window. |

### Session Persistence

Persistence adds session management shortcuts.

| Modes | Keys | Action |
| --- | --- | --- |
| Normal | `<leader>qs` | Restore the last saved session in the current directory. |
| Normal | `<leader>qS` | Pick a session to restore. |
| Normal | `<leader>ql` | Reload the most recent session. |
| Normal | `<leader>qd` | Stop auto-saving the current session. |

### Bufferline (tab-like buffers)

Bufferline introduces additional buffer navigation and management commands.

| Modes | Keys | Action |
| --- | --- | --- |
| Normal | `<leader>bp` | Pin or unpin the current buffer. |
| Normal | `<leader>bP` | Close all unpinned buffers. |
| Normal | `<leader>br` / `<leader>bl` | Close buffers to the right or left of the current buffer. |
| Normal | `<S-h>` / `<S-l>` | Cycle to the previous or next buffer. |
| Normal | `[b` / `]b` | Cycle to the previous or next buffer (alternate mapping). |
| Normal | `[B` / `]B` | Move the current buffer left or right. |

### Noice (UI enhancements)

Noice remaps several UI-focused commands, including message history access and scrollback in floating LSP popups.

| Modes | Keys | Action |
| --- | --- | --- |
| Normal | `<leader>sn?` prefix | Group label for Noice commands under `<leader>s`. |
| Command-line | `<S-Enter>` | Redirect the current command-line contents through Noice for richer display. |
| Normal | `<leader>snl` / `<leader>snh` / `<leader>sna` / `<leader>snd` / `<leader>snt` | Show the last message, history, all messages, dismiss notifications, or open the Noice picker. |
| Insert/Normal/Select | `<C-f>` / `<C-b>` | Scroll forward or backward inside LSP documentation popups. |

### Snacks Notifications & Dashboard

Snacks' UI module adds shortcuts for viewing notification history and clearing alerts.

| Modes | Keys | Action |
| --- | --- | --- |
| Normal | `<leader>n` | Open the Snacks notification picker (or fallback history viewer). |
| Normal | `<leader>un` | Dismiss all current notifications. |
| Normal (dashboard) | `f`, `n`, `g`, `r`, `c`, `s`, `x`, `l`, `q` | Dashboard quick actions for finding files, new files, grep, recent files, config browsing, restoring sessions, toggling extras, opening Lazy, or quitting. |

### Gitsigns

LazyVim configures Gitsigns with a rich set of buffer-local mappings when a Git buffer attaches.

| Modes | Keys | Action |
| --- | --- | --- |
| Normal | `]h` / `[h` | Jump to the next or previous hunk (respects diff mode). |
| Normal | `]H` / `[H` | Jump to the last or first hunk. |
| Normal/Visual | `<leader>ghs` / `<leader>ghr` | Stage or reset the selected hunk. |
| Normal | `<leader>ghS` / `<leader>ghu` | Stage the entire buffer or undo the last stage. |
| Normal | `<leader>ghR` | Reset the entire buffer. |
| Normal | `<leader>ghp` | Preview the current hunk inline. |
| Normal | `<leader>ghb` / `<leader>ghB` | Show blame information for the line or entire buffer. |
| Normal | `<leader>ghd` / `<leader>ghD` | Diff the current buffer against HEAD or against the saved version. |
| Operator/Visual | `ih` | Select the current hunk as a text object. |

### Trouble (diagnostics list)

Trouble binds quick toggles for diagnostics, symbols, and list navigation.

| Modes | Keys | Action |
| --- | --- | --- |
| Normal | `<leader>xx` / `<leader>xX` | Toggle workspace or buffer diagnostics. |
| Normal | `<leader>cs` / `<leader>cS` | Open symbol outlines or LSP references in Trouble. |
| Normal | `<leader>xL` / `<leader>xQ` | Toggle the location list or quickfix list views. |
| Normal | `[q` / `]q` | Move to the previous or next Trouble entry, falling back to quickfix navigation. |

### todo-comments

todo-comments adds project-wide TODO management commands.

| Modes | Keys | Action |
| --- | --- | --- |
| Normal | `]t` / `[t` | Jump to the next or previous TODO comment. |
| Normal | `<leader>xt` / `<leader>xT` | Open TODO items in Trouble (all or limited to TODO/FIX/FIXME). |
| Normal | `<leader>st` / `<leader>sT` | Search TODOs via Telescope with optional keyword filters. |

### Conform (formatters)

Conform adds a dedicated shortcut for formatting injected code blocks separately.

| Modes | Keys | Action |
| --- | --- | --- |
| Normal/Visual | `<leader>cF` | Format embedded languages (e.g., code fences) using Conform. |

### Treesitter Textobjects

Motion keys for Treesitter textobjects support jumping between functions, classes, and parameters.

| Modes | Keys | Action |
| --- | --- | --- |
| Normal/Visual/Operator | `]f` / `[f` | Jump to the next or previous function start. |
| Normal/Visual/Operator | `]F` / `[F` | Jump to the next or previous function end. |
| Normal/Visual/Operator | `]c` / `[c` | Jump to the next or previous class start. |
| Normal/Visual/Operator | `]C` / `[C` | Jump to the next or previous class end. |
| Normal/Visual/Operator | `]a` / `[a` | Jump to the next or previous parameter start. |
| Normal/Visual/Operator | `]A` / `[A` | Jump to the next or previous parameter end. |

### LSP Core Mappings

These LSP-centric bindings attach buffer-locally when a server connects. The mappings below are available when an LSP attaches and the server reports capability support for the respective actions.

| Modes | Keys | Action |
| --- | --- | --- |
| Normal | `<leader>cl` | Open the LSP configuration picker. |
| Normal | `gd` / `gr` / `gI` / `gy` / `gD` | Go to definition, list references, open implementation, jump to type definition, or declaration. |
| Normal | `K` / `gK` | Show hover or signature help. |
| Insert | `<C-k>` | Show signature help while editing. |
| Normal/Visual | `<leader>ca` | Trigger code actions for the cursor or selection. |
| Normal/Visual | `<leader>cc` / `<leader>cC` | Run or refresh code lenses. |
| Normal | `<leader>cR` / `<leader>cr` | Rename the file (Snacks) or symbol (LSP). |
| Normal | `<leader>cA` | Run source-level LSP code actions. |
| Normal | `]]` / `[[` | Move to next/previous document highlight (requires LSP support). |
| Normal | `<A-n>` / `<A-p>` | Move to next/previous highlight without jumping the cursor (Snacks words). |

## LazyVim Extras

The optional extras enabled in `dot_config/nvim/lazyvim.json` contribute the following additional keymaps.

### Copilot Chat

Copilot Chat adds AI-assisted commands under the `<leader>a` prefix and remaps `<C-s>` inside the chat buffer.

| Modes | Keys | Action |
| --- | --- | --- |
| Insert (Copilot Chat) | `<C-s>` | Submit the current chat prompt. |
| Normal/Visual | `<leader>aa` | Toggle the Copilot Chat sidebar. |
| Normal/Visual | `<leader>ax` | Clear the active chat session. |
| Normal/Visual | `<leader>aq` | Prompt for a quick ad-hoc Copilot question. |
| Normal/Visual | `<leader>ap` | Pick from saved Copilot prompt templates. |

### Yanky

Yanky replaces the default yank/paste motions with a history-aware implementation.

| Modes | Keys | Action |
| --- | --- | --- |
| Normal/Visual | `<leader>p` | Open the yank history via the active picker backend. |
| Normal/Visual | `y` | Yank text through Yanky. |
| Normal/Visual | `p` / `P` | Paste after or before using Yanky's registers. |
| Normal/Visual | `gp` / `gP` | Paste after/before the selection area. |
| Normal/Visual | `[y` / `]y` | Cycle through earlier or later yank entries. |
| Normal | `[p` / `]p` / `[P` / `]P` | Paste with automatic indentation adjustments. |
| Normal | `<p` / `>p` / `<P` / `>P` | Paste and shift indentation left/right. |
| Normal | `=p` / `=P` | Paste after or before while running the configured filter. |

### Dial

Dial enables smart increment/decrement operations across data types.

| Modes | Keys | Action |
| --- | --- | --- |
| Normal/Visual | `<C-a>` / `<C-x>` | Increment or decrement the value under the cursor. |
| Normal/Visual | `g<C-a>` / `g<C-x>` | Increment or decrement using the alternate Dial group (e.g., for g-prefixed sequences). |

### Harpoon 2

Harpoon bookmarks files and jumps between them quickly.

| Modes | Keys | Action |
| --- | --- | --- |
| Normal | `<leader>H` | Add the current file to the Harpoon list. |
| Normal | `<leader>h` | Toggle the Harpoon quick menu. |
| Normal | `<leader>1` … `<leader>9` | Jump to Harpoon slot 1–9. |

### Incremental Rename

inc-rename augments the LSP rename workflow with a preview-capable command.

| Modes | Keys | Action |
| --- | --- | --- |
| Normal | `<leader>cr` | Start an incremental rename using `:IncRename` seeded with the symbol under the cursor. |

### Markdown Enhancements

Markdown extras add preview and rendering toggles.

| Modes | Keys | Action |
| --- | --- | --- |
| Normal (Markdown) | `<leader>cp` | Toggle the Markdown preview browser. |
| Normal | `<leader>um` | Toggle rendered Markdown highlighting. |

### Python Tooling

Python-specific servers and tooling expose additional actions.

| Modes | Keys | Action |
| --- | --- | --- |
| Normal | `<leader>co` | Organize Python imports (Pyright or Ruff LSP). |
| Normal (Python) | `<leader>dPt` / `<leader>dPc` | Debug the current test method or class via `nvim-dap-python`. |
| Normal (Python) | `<leader>cv` | Pick a virtual environment with `venv-selector`. |

### Scala Metals

Metals integrations add Telescope and Metals-specific commands.

| Modes | Keys | Action |
| --- | --- | --- |
| Normal | `<leader>me` | Open the Metals command palette. |
| Normal | `<leader>mc` | Trigger Metals cascade compilation. |
| Normal | `<leader>mh` | Show the Metals worksheet hover UI. |

### SQL / Database UI

The SQL extra enables Dadbod UI toggles.

| Modes | Keys | Action |
| --- | --- | --- |
| Normal | `<leader>D` | Toggle the vim-dadbod UI window. |

### Testing (neotest core)

neotest provides a cohesive test runner experience with DAP integration.

| Modes | Keys | Action |
| --- | --- | --- |
| Normal | `<leader>tt` / `<leader>tT` | Run the current file or the entire project test suite. |
| Normal | `<leader>tr` / `<leader>tl` | Run the nearest test or rerun the last test. |
| Normal | `<leader>ts` / `<leader>to` / `<leader>tO` | Toggle the summary view, show output, or toggle the output panel. |
| Normal | `<leader>tS` / `<leader>tw` | Stop the active test run or toggle watching the current file. |
| Normal | `<leader>td` | Debug the nearest test via DAP. |

## Local plugin specs

Local plugin specs continue to live under `dot_config/nvim/lua/plugins`. See that directory for the exact code that applies these overrides and additions.

If you want to add or change mappings, edit the plugin specs in that directory; the short list of local modifications is shown at the top of this document for quick reference.
