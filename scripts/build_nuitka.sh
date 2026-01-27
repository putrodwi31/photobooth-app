#!/usr/bin/env bash
set -euo pipefail

# Build a standalone executable with Nuitka.
# Usage:
#   scripts/build_nuitka.sh            # builds into ./build/nuitka
#   scripts/build_nuitka.sh --onefile  # builds a single-file binary

OS_NAME="${OS_NAME:-$(uname -s 2>/dev/null || echo unknown)}"
case "$OS_NAME" in
  MINGW*|MSYS*|CYGWIN*|Windows_NT)
    DEFAULT_PYTHON_BIN=".venv/Scripts/python.exe"
    ;;
  *)
    DEFAULT_PYTHON_BIN=".venv/bin/python"
    ;;
esac

PYTHON_BIN="${PYTHON_BIN:-$DEFAULT_PYTHON_BIN}"
OUT_DIR="${OUT_DIR:-build/nuitka}"
ONEFILE="${ONEFILE:-0}"

if [[ ! -x "$PYTHON_BIN" ]]; then
  echo "Python interpreter not found at: $PYTHON_BIN" >&2
  echo "Set PYTHON_BIN to your virtualenv python, e.g.:" >&2
  echo "  PYTHON_BIN=.venv/bin/python scripts/build_nuitka.sh" >&2
  exit 1
fi

mkdir -p "$OUT_DIR"

NUITKA_FLAGS=(
  --assume-yes-for-downloads
  --standalone
  --follow-imports
  --output-dir="$OUT_DIR"
  --output-filename=photobooth
  --enable-plugin=numpy
  --enable-plugin=multiprocessing
  --include-package=photobooth
  --include-package=web
  --include-package-data=photobooth
  --include-package-data=web
  --include-data-dir=assets=assets
  --include-data-files=src/photobooth/database/alembic/env.py=photobooth/database/alembic/env.py
  --include-data-files=src/photobooth/database/alembic/script.py.mako=photobooth/database/alembic/script.py.mako
  --include-data-dir=src/photobooth/database/alembic/versions=photobooth/database/alembic/versions
)

if [[ "$ONEFILE" == "1" ]] || [[ "${1:-}" == "--onefile" ]]; then
  NUITKA_FLAGS+=(--onefile)
fi

# Use a small runner that imports the package explicitly so relative imports work.
exec "$PYTHON_BIN" -m nuitka "${NUITKA_FLAGS[@]}" src/photobooth_runner.py
