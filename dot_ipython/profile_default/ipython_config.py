# IPython configuration — managed by chezmoi

c = get_config()  # noqa: F821

# Show all expression results, not just the last one
c.InteractiveShell.ast_node_interactivity = "all"

# Dark-terminal-friendly color scheme
c.InteractiveShell.colors = "Linux"

# Exit without confirmation prompt
c.TerminalInteractiveShell.confirm_exit = False

# Disable autocall to avoid unexpected function invocations
c.InteractiveShell.autocall = 0
