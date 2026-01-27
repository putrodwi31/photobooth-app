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
    IS_WINDOWS=1
    ;;
  *)
    DEFAULT_PYTHON_BIN=".venv/bin/python"
    IS_WINDOWS=0
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

if command -v getconf >/dev/null 2>&1; then
  CPU_JOBS="$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)"
else
  CPU_JOBS="${CPU_JOBS:-4}"
fi

RCLONE_BIN_DIR="$($PYTHON_BIN - <<'PY'
from pathlib import Path

try:
    import rclone_api
except Exception:
    print("")
    raise SystemExit(0)

print(Path(rclone_api.__file__).resolve().parent.joinpath("bin"))
PY
)"

GPHOTO2_PORT_DIR="$($PYTHON_BIN - <<'PY'
from pathlib import Path

try:
    import gphoto2 as gp  # type: ignore
except Exception:
    print("")
    raise SystemExit(0)

root = Path(gp.__file__).resolve().parent
candidates = sorted(root.rglob("libgphoto2_port"))
if not candidates:
    print("")
    raise SystemExit(0)

# Use the first matching libgphoto2_port directory.
print(candidates[0])
PY
)"

NUITKA_FLAGS=(
  --assume-yes-for-downloads
  --standalone
  --output-dir="$OUT_DIR"
  --output-filename=photobooth
  --jobs="$CPU_JOBS"
  --include-package=photobooth
  --include-package=web
  --include-package=photobooth.plugins
  --include-module=photobooth.plugins.commander.commander
  --include-module=photobooth.plugins.gpio_lights.gpio_lights
  --include-module=photobooth.plugins.wled.wled
  --include-module=photobooth.plugins.filter_pilgram2.filter_pilgram2
  --include-module=photobooth.plugins.synchronizer_legacy.synchronizer_legacy
  --include-module=photobooth.plugins.synchronizer_rclone.synchronizer_rclone
  --include-package=urllib3.contrib.resolver
  --include-module=urllib3.contrib.resolver.system
  --include-package=urllib3.contrib.hface.protocols
  --include-module=urllib3.contrib.hface.protocols.http1
  --include-module=urllib3.contrib.hface.protocols.http2
  --include-module=av.sidedata.encparams
  --include-package-data=photobooth
  --include-package-data=web
  --include-data-dir=assets=assets
  --include-data-dir=src/web/frontend=web/frontend
  --include-data-dir=src/web/sharepage=web/sharepage
  --include-data-dir=src/photobooth/demoassets=photobooth/demoassets
  --include-data-files=src/photobooth/database/alembic/env.py=photobooth/database/alembic/env.py
  --include-data-files=src/photobooth/database/alembic/script.py.mako=photobooth/database/alembic/script.py.mako
  --include-data-files=src/photobooth/database/alembic/versions/*.py=photobooth/database/alembic/versions/
)

if [[ "$IS_WINDOWS" == "1" ]]; then
  # Stay on GCC/MinGW to avoid requiring MSVC Build Tools.
  NUITKA_FLAGS+=(--mingw64)
fi

if [[ -n "$RCLONE_BIN_DIR" ]] && [[ -d "$RCLONE_BIN_DIR" ]]; then
  if [[ "$IS_WINDOWS" == "1" ]] && [[ -f "$RCLONE_BIN_DIR/rclone.exe" ]]; then
    NUITKA_FLAGS+=(--include-data-files="$RCLONE_BIN_DIR/rclone.exe"=rclone_api/bin/rclone.exe)
  else
    NUITKA_FLAGS+=(--include-data-dir="$RCLONE_BIN_DIR"=rclone_api/bin)
  fi
else
  echo "WARNING: rclone_api bin directory not found; rclone-based sync will fail." >&2
fi

if [[ -n "$GPHOTO2_PORT_DIR" ]] && [[ -d "$GPHOTO2_PORT_DIR" ]]; then
  NUITKA_FLAGS+=(--include-data-dir="$GPHOTO2_PORT_DIR"=libgphoto2_port)
else
  echo "WARNING: libgphoto2_port (iolibs) directory not found; gphoto2 may fail." >&2
fi

if [[ "$ONEFILE" == "1" ]] || [[ "${1:-}" == "--onefile" ]]; then
  NUITKA_FLAGS+=(--onefile)
fi

# Use a small runner that imports the package explicitly so relative imports work.
exec "$PYTHON_BIN" -m nuitka "${NUITKA_FLAGS[@]}" src/photobooth_runner.py
