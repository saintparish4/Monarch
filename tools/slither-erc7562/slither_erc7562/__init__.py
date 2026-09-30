"""Slither detectors for ERC-4337 / ERC-7562 validation rules."""

from importlib.metadata import PackageNotFoundError, version

from .detectors import ValidationPhaseOpcodes

# One version, in pyproject.toml. Read back from the installed metadata so the
# two can't drift.
try:
    __version__ = version("slither-erc7562")
except PackageNotFoundError:  # imported from a checkout without installing
    __version__ = "0+unknown"


def make_plugin():
    """Entry point for `slither_analyzer.plugin`."""
    return [ValidationPhaseOpcodes], []
