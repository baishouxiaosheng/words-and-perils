#!/usr/bin/env python3
"""Restore the current verified source version, completely offline."""
from pathlib import Path
import runpy
runpy.run_path(str(Path(__file__).with_name("restore_v28_ui_safety.py")), run_name="__main__")
