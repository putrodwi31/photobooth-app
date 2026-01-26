FROM python:3.12-slim

# System dependencies (sesuai halaman Installation)
RUN apt-get update && apt-get install -y --no-install-recommends \
    ffmpeg \
    libturbojpeg0 \
    libgl1 \
    libgphoto2-dev \
    fonts-noto-color-emoji \
    libexif12 \
    libgphoto2-6 \
    libgphoto2-port12 \
    libltdl7 \
    python3-dev \
  && rm -rf /var/lib/apt/lists/*

RUN pip install uv

WORKDIR /opt/photobooth-app
COPY . /opt/photobooth-app

RUN uv venv --system-site-packages # allow acces to system packages for libcamera/picamera2
RUN uv sync

EXPOSE 8000

ENTRYPOINT ["uv","run","photobooth"]