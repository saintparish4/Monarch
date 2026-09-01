"""Slither detectors for ERC-4337 / ERC-7562 validation rules."""

from .detectors import ValidationPhaseOpcodes

__version__ = "0.1.0"


def make_plugin():
    """Entry point for `slither_analyzer.plugin`."""
    return [ValidationPhaseOpcodes], []
