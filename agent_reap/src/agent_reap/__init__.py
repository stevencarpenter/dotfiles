"""Socket-aware reaper for idle Claude Code teammate panes.

The problem this solves: Claude Code agent teams in tmux mode leave one pane per
teammate alive after the work is done. Nothing in the team lifecycle closes them,
so they accumulate until they exhaust the subagent budget. They are not orphans —
they are healthy, attached panes whose leader never receives EOF or SIGHUP,
because nothing ever closes the pane.

Two design facts drive the implementation:

1. ``tmux kill-server`` is socket-scoped, and a machine running z4h has several
   tmux servers on separate sockets. Anything that reads only ``$TMUX`` will miss
   teams living on another socket. Discovery therefore enumerates every socket.
2. Destroying a pane is a complete teardown (``remain-on-exit off`` SIGHUPs the
   pane leader and its non-disowned children), so ``tmux kill-pane`` is the only
   kill primitive needed. Signal escalation exists solely for processes that have
   no pane at all.
"""

__all__ = ["__version__"]

__version__ = "0.1.0"
