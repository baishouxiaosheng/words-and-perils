#!/usr/bin/env python3
"""Restore the current verified public source version, completely offline."""
from pathlib import Path
import runpy
runpy.run_path(str(Path(__file__).with_name("restore_v29.py")), run_name="__main__")
