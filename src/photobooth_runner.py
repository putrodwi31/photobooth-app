#!/usr/bin/env python3
"""Nuitka-friendly entrypoint that imports the package explicitly."""

from __future__ import annotations

import sys

from photobooth.__main__ import main


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
