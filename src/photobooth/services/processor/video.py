import logging
from pathlib import Path
from uuid import uuid4
import shutil
import time
import os

from statemachine import Event

from ... import PATH_CAMERA_ORIGINAL, PATH_PROCESSED, PATH_UNPROCESSED
from ...database.models import Mediaitem, MediaitemTypes
from ...utils.helper import filename_str_time
from ..acquisition import AcquisitionService
from ..config.groups.actions import VideoConfigurationSet
from ..mediaprocessing.processes import process_video
from .base import Capture, CaptureSet, JobModelBase

logger = logging.getLogger(__name__)

def _wait_until_file_stable(path: Path, timeout_s: float = 10.0, interval_s: float = 0.2) -> None:
    """
    Wait until file exists and its size stops changing (useful for SMB/CIFS / slow writers).
    """
    deadline = time.time() + timeout_s
    last_size = -1

    while time.time() < deadline:
        if path.is_file():
            try:
                size = path.stat().st_size
            except FileNotFoundError:
                size = -1

            if size > 0 and size == last_size:
                return

            last_size = size

        time.sleep(interval_s)

    # Don’t hard fail here; caller can still attempt move and raise proper error.
    # If you prefer to fail fast:
    # raise TimeoutError(f"File not stable after {timeout_s}s: {path}")


def move_capture_with_fallback(
    src: Path,
    dst: Path,
    *,
    wait_stable: bool = True,
    stable_timeout_s: float = 10.0,
    retries: int = 5,
    retry_delay_s: float = 0.2,
) -> Path:
    """
    Callback/helper to move a capture file reliably on CIFS/SMB:
    - Optionally wait until src is stable (size stops changing)
    - Try atomic rename first
    - Fallback to shutil.move (copy+delete) if rename fails
    """
    dst.parent.mkdir(parents=True, exist_ok=True)

    if wait_stable:
        _wait_until_file_stable(src, timeout_s=stable_timeout_s)

    last_exc: Exception | None = None

    # copy+delete via shutil.move (CIFS/Windows friendly)
    for attempt in range(retries):
        try:
            moved = shutil.move(str(src), str(dst))
            return Path(moved)
        except Exception as exc:
            last_exc = exc
            if attempt < retries - 1:
                time.sleep(retry_delay_s)

    raise RuntimeError(f"failed to move capture from {src} to {dst}") from last_exc


class JobModelVideo(JobModelBase[VideoConfigurationSet]):
    _media_type = MediaitemTypes.video

    def __init__(self, configuration_set: VideoConfigurationSet, acquisition_service: AcquisitionService):
        super().__init__(configuration_set, acquisition_service=acquisition_service)

        # self._validate_job()

    @property
    def total_captures_to_take(self) -> int:
        return 1

    def on_enter_counting(self):
        self._acquisition_service.signalbackend_configure_optimized_for_video()

        super().on_enter_counting()

    def on_exit_counting(self):
        super().on_exit_counting()

    def on_enter_capture(self):
        video_file = self._acquisition_service.start_recording(video_framerate=self._configuration_set.processing.video_framerate)
        captureset = CaptureSet([Capture(video_file)])

        # add to tmp collection
        # update model so it knows the latest number of captures and the machine can react accordingly if finished
        self._capture_sets.append(captureset)

    def on_exit_capture(self):
        self._acquisition_service.stop_recording()  # blocks until video is written...

        logger.info(f"captureset {self._capture_sets} successful")

    def on_enter_approval(self): ...

    def on_exit_approval(self, event: Event): ...

    def on_enter_completed(self):
        super().on_enter_completed()

        # postprocess each video
        capture_to_process = self._capture_sets[0].captures[0].filepath
        logger.debug(f"recorded to {capture_to_process=}")

        original_filenamepath = Path(filename_str_time()).with_suffix(".mp4")

        # very first, move the capture_to_process to originals. if anything later fails, at least we got the file in safe place.
        target_original = Path(PATH_CAMERA_ORIGINAL, original_filenamepath)
        captured_original = move_capture_with_fallback(
            capture_to_process,
            target_original,
            wait_stable=True,
            stable_timeout_s=30.0,  # video biasanya lebih lama finish write
        )

        mediaitem = Mediaitem(
            id=uuid4(),
            job_identifier=self._job_identifier,
            media_type=self._media_type,
            unprocessed=Path(PATH_UNPROCESSED, original_filenamepath),
            processed=Path(PATH_PROCESSED, original_filenamepath),
            captured_original=captured_original,
            pipeline_config=self._configuration_set.processing.model_dump(mode="json"),
        )

        # apply video pipeline:
        process_video(captured_original, mediaitem)

        assert mediaitem.unprocessed.is_file()
        assert mediaitem.processed.is_file()
        assert mediaitem.captured_original and mediaitem.captured_original.is_file()

        # out to db/ui
        self.set_results(mediaitem, mediaitem.id)

        logger.info(f"capture {mediaitem=} successful")

    def on_exit_completed(self): ...

    def on_enter_finished(self): ...
