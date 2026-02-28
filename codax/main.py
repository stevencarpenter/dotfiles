import argparse
import logging
from collections.abc import Sequence

from _logging import configure

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

PROJECT_NAME = "codax"

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------

log = logging.getLogger(__name__)


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="TODO")
    parser.add_argument(
        "--log-level",
        default="WARNING",
        choices=("DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL"),
        help="Logging level (default: WARNING).",
    )
    return parser


def parse_args(argv: Sequence[str] | None = None) -> argparse.Namespace:
    return build_parser().parse_args(argv)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_args(argv)
    configure(args.log_level)
    log.debug("Starting %s", PROJECT_NAME)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
