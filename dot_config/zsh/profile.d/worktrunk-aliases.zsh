# Worktrunk shortcuts. Sourced from ~/.config/zsh/.zshrc via the profile.d loop.

# wsc <branch> [-- <prompt>]: create worktree, fire hooks (IntelliJ opens),
# replace shell with `claude <prompt>` running in the new worktree.
alias wsc='wt switch --create -x claude'

# wsi <branch>: create worktree and explicitly open IntelliJ on it.
alias wsi='wt switch --create -x "idea {{ worktree_path }}"'

# Generic shortcuts.
alias ws='wt switch'
alias wl='wt list'
alias wm='wt merge'
