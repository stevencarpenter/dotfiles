"""Logging utilities used by the token-auditor command-line interface."""

import logging
import sys

LOG_FORMAT = "%(levelname)s %(name)s: %(message)s"


def configure(level: str = "WARNING") -> None:
    """Configure application logging with a consistent stderr-oriented format.

    Args:
        level (str): Logging threshold name (for example ``"INFO"`` or
            ``"WARNING"``) that determines which log records are emitted.

    Returns:
        None: This function mutates global logging state and returns nothing.
    """
    logging.basicConfig(
        level=level,
        format=LOG_FORMAT,
        stream=sys.stderr,
    )
