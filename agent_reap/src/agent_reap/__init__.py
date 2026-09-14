"""Socket-aware reaper for idle Claude Code teammate panes.

Idle teammate panes remain attached after work completes and consume the
subagent budget. Discovery enumerates all sockets because z4h can run multiple
tmux servers. ``tmux kill-pane`` sends SIGHUP to the pane leader and its
non-disowned children; separate process cleanup handles descendants without panes.
"""

__all__ = ["__version__"]

__version__ = "0.1.0"
