import locale
import os
import sys
from pathlib import Path
from shutil import copytree, rmtree

# set locale to systems default
locale.setlocale(locale.LC_ALL, "")

# gphoto2: help libgphoto2 find iolibs/camlibs in frozen/onefile builds.
_PKG_ROOT = Path(__file__).resolve().parents[1]
_PORT_DIR = _PKG_ROOT.joinpath("libgphoto2_port")
_CAMLIB_DIR = _PKG_ROOT.joinpath("libgphoto2")
if _PORT_DIR.exists() and "GP_PORT_INFO_DIR" not in os.environ:
    os.environ["GP_PORT_INFO_DIR"] = os.fsdecode(_PORT_DIR)
if _CAMLIB_DIR.exists() and "GP_CAMLIB_DIR" not in os.environ:
    os.environ["GP_CAMLIB_DIR"] = os.fsdecode(_CAMLIB_DIR)

# database
DATABASE_PATH = "./database/"
# mediaitems cache for resized versions
CACHE_PATH = "./cache/"
# media collection files
MEDIA_PATH = "./media/"
PATH_CAMERA_ORIGINAL = "".join([MEDIA_PATH, "camera_original/"])
PATH_UNPROCESSED = "".join([MEDIA_PATH, "unprocessed_original/"])
PATH_PROCESSED = "".join([MEDIA_PATH, "processed_full/"])
# folder not touched, used by user
USERDATA_PATH = "./userdata/"
# logfiles
LOG_PATH = "./log/"
# configuration
CONFIG_PATH = "./config/"
# all other stuff that is used temporarily
TMP_PATH = "./tmp/"
# recycle dir if delete moves to recycle instead actual removing
RECYCLE_PATH = "./recycle/"


def _create_basic_folders():
    os.makedirs(DATABASE_PATH, exist_ok=True)
    os.makedirs(CACHE_PATH, exist_ok=True)
    os.makedirs(MEDIA_PATH, exist_ok=True)
    os.makedirs(PATH_CAMERA_ORIGINAL, exist_ok=True)
    os.makedirs(PATH_UNPROCESSED, exist_ok=True)
    os.makedirs(PATH_PROCESSED, exist_ok=True)
    os.makedirs(USERDATA_PATH, exist_ok=True)
    os.makedirs(LOG_PATH, exist_ok=True)
    os.makedirs(CONFIG_PATH, exist_ok=True)
    os.makedirs(TMP_PATH, exist_ok=True)
    os.makedirs(RECYCLE_PATH, exist_ok=True)


def _copy_demo_assets_to_userdata():
    src_path = Path(__file__).parent.resolve().joinpath("demoassets/userdata").absolute()
    dst_path = Path(USERDATA_PATH, "demoassets").absolute()

    def is_frozen_build() -> bool:
        return bool(getattr(sys, "frozen", False) or globals().get("__compiled__", False))

    # In Nuitka onefile mode, the source lives in a temp dir that changes each run.
    # A previous link may become broken. If so, remove and recreate it.
    is_junction = os.name == "nt" and hasattr(dst_path, "is_junction") and dst_path.is_junction()

    if is_frozen_build():
        if dst_path.is_symlink():
            dst_path.unlink(missing_ok=True)
        elif is_junction:
            try:
                os.rmdir(dst_path)
            except OSError:
                rmtree(dst_path, ignore_errors=True)
        if dst_path.exists():
            return
        if not src_path.exists():
            raise RuntimeError(f"error setup demoassets, {src_path} does not exist!")
        copytree(src_path, dst_path)
        return

    if dst_path.is_symlink() or is_junction:
        # replace links with a real directory copy
        try:
            if dst_path.is_symlink():
                dst_path.unlink(missing_ok=True)
            else:
                os.rmdir(dst_path)
        except OSError:
            rmtree(dst_path, ignore_errors=True)

    if dst_path.exists():
        if dst_path.is_dir():
            return
        raise RuntimeError(f"error setup demoassets, {dst_path} exists but is not a directory!")

    copytree(src_path, dst_path)


try:
    _create_basic_folders()
    _copy_demo_assets_to_userdata()
except Exception as exc:
    raise RuntimeError(f"cannot initialize data folders, error: {exc}") from exc
