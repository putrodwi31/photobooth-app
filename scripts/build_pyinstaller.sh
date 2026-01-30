#!/usr/bin/env bash
set -euo pipefail

# Build a standalone executable with PyInstaller (faster dev builds).
# Usage:
#   scripts/build_pyinstaller.sh            # builds into ./build/pyinstaller
#   scripts/build_pyinstaller.sh --onefile  # builds a single-file binary

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
OUT_DIR="${OUT_DIR:-build/pyinstaller}"
ONEFILE="${ONEFILE:-0}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd -P)"

if [[ ! -x "$PYTHON_BIN" ]]; then
  echo "Python interpreter not found at: $PYTHON_BIN" >&2
  echo "Set PYTHON_BIN to your virtualenv python, e.g.:" >&2
  echo "  PYTHON_BIN=.venv/bin/python scripts/build_pyinstaller.sh" >&2
  exit 1
fi

mkdir -p "$OUT_DIR"

DATA_SEP=":"
if [[ "$IS_WINDOWS" == "1" ]]; then
  DATA_SEP=";"
fi

add_data_arg() {
  local src="$1"
  local dst="$2"
  local abs_src="$src"
  if [[ "$src" != /* ]] && [[ ! "$src" =~ ^[A-Za-z]: ]]; then
    abs_src="${PROJECT_ROOT}/${src}"
  fi
  PYI_ARGS+=(--add-data "${abs_src}${DATA_SEP}${dst}")
}

add_binary_arg() {
  local src="$1"
  local dst="$2"
  local abs_src="$src"
  if [[ "$src" != /* ]] && [[ ! "$src" =~ ^[A-Za-z]: ]]; then
    abs_src="${PROJECT_ROOT}/${src}"
  fi
  PYI_ARGS+=(--add-binary "${abs_src}${DATA_SEP}${dst}")
}

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

GPHOTO2_DIRS="$($PYTHON_BIN - <<'PY'
from pathlib import Path

try:
    import gphoto2 as gp  # type: ignore
except Exception:
    print("")
    raise SystemExit(0)

root = Path(gp.__file__).resolve().parent
port_candidates = sorted(root.rglob("libgphoto2_port"))
camlib_candidates = sorted(root.rglob("libgphoto2"))

# Print up to two lines: port dir then camlib dir.
print(port_candidates[0] if port_candidates else "")
print(camlib_candidates[0] if camlib_candidates else "")
PY
)"
GPHOTO2_PORT_DIR="$(printf '%s\n' "$GPHOTO2_DIRS" | sed -n '1p')"
GPHOTO2_CAMLIB_DIR="$(printf '%s\n' "$GPHOTO2_DIRS" | sed -n '2p')"

PYI_ARGS=(
  --clean
  --name photobooth
  --distpath "$OUT_DIR/dist"
  --workpath "$OUT_DIR/build"
  --specpath "$OUT_DIR/spec"
)

if [[ "$ONEFILE" == "1" ]] || [[ "${1:-}" == "--onefile" ]]; then
  PYI_ARGS+=(--onefile)
else
  PYI_ARGS+=(--onedir)
fi

PYI_ARGS+=(
  --hidden-import photobooth.plugins.commander.commander
  --hidden-import photobooth.plugins.gpio_lights.gpio_lights
  --hidden-import photobooth.plugins.wled.wled
  --hidden-import photobooth.plugins.filter_pilgram2.filter_pilgram2
  --hidden-import photobooth.plugins.synchronizer_legacy.synchronizer_legacy
  --hidden-import photobooth.plugins.synchronizer_rclone.synchronizer_rclone
  --hidden-import urllib3.contrib.resolver
  --hidden-import urllib3.contrib.resolver.system
)

add_data_arg "assets" "assets"
add_data_arg "src/web/frontend" "web/frontend"
add_data_arg "src/web/sharepage" "web/sharepage"
add_data_arg "src/photobooth/demoassets" "photobooth/demoassets"
add_data_arg "src/photobooth/database/alembic/env.py" "photobooth/database/alembic"
add_data_arg "src/photobooth/database/alembic/script.py.mako" "photobooth/database/alembic"
add_data_arg "src/photobooth/database/alembic/versions" "photobooth/database/alembic/versions"

if [[ -n "$RCLONE_BIN_DIR" ]] && [[ -d "$RCLONE_BIN_DIR" ]]; then
  if [[ "$IS_WINDOWS" == "1" ]] && [[ -f "$RCLONE_BIN_DIR/rclone.exe" ]]; then
    add_binary_arg "${RCLONE_BIN_DIR}/rclone.exe" "rclone_api/bin"
  else
    add_binary_arg "${RCLONE_BIN_DIR}" "rclone_api/bin"
  fi
else
  echo "WARNING: rclone_api bin directory not found; rclone-based sync will fail." >&2
fi

if [[ -n "$GPHOTO2_PORT_DIR" ]] && [[ -d "$GPHOTO2_PORT_DIR" ]]; then
  add_data_arg "${GPHOTO2_PORT_DIR}" "libgphoto2_port"
else
  echo "WARNING: libgphoto2_port (iolibs) directory not found; gphoto2 may fail." >&2
fi
if [[ -n "$GPHOTO2_CAMLIB_DIR" ]] && [[ -d "$GPHOTO2_CAMLIB_DIR" ]]; then
  add_data_arg "${GPHOTO2_CAMLIB_DIR}" "libgphoto2"
fi

# Use a small runner that imports the package explicitly so relative imports work.
exec "$PYTHON_BIN" -m PyInstaller "${PYI_ARGS[@]}" src/photobooth_runner.py
