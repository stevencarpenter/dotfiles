# Worktrunk shortcuts. Sourced from ~/.config/zsh/.zshrc via the profile.d loop.
#
# `wt switch -x` expands template vars in its argument before exec
# (see `wt switch --help` → "Supports hook template variables"), which is what
# makes the `{{ worktree_path }}` in `wsi` resolve to the just-created path.

# wsc <branch> [-- <prompt>]: create worktree and replace shell with
# `claude <prompt>` running in it. No IDE side effect.
alias wsc='wt switch --create -x claude'

# wsi <branch>: create worktree and open IntelliJ at it. (Use this when you
# want the IDE; wsc deliberately does not auto-open one.)
alias wsi='wt switch --create -x "idea {{ worktree_path }}"'

# Generic shortcuts.
alias ws='wt switch'
alias wl='wt list'
alias wm='wt merge'
