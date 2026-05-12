#!/usr/bin/env python3
from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_SOURCE = ROOT / "scripts" / "app-icon-source.png"
ICONSET = ROOT / "import" / "BUF" / "Assets.xcassets" / "AppIcon.appiconset"
SIZES = {
    "icon_16x16.png": 16,
    "icon_16x16@2x.png": 32,
    "icon_32x32.png": 32,
    "icon_32x32@2x.png": 64,
    "icon_128x128.png": 128,
    "icon_128x128@2x.png": 256,
    "icon_256x256.png": 256,
    "icon_256x256@2x.png": 512,
    "icon_512x512.png": 512,
    "icon_512x512@2x.png": 1024,
}


def square_crop(image: Image.Image) -> Image.Image:
    width, height = image.size
    side = min(width, height)
    left = (width - side) // 2
    top = (height - side) // 2
    return image.crop((left, top, left + side, top + side))


def main() -> None:
    source = Path(sys.argv[1]).expanduser() if len(sys.argv) > 1 else DEFAULT_SOURCE
    if not source.exists():
        raise SystemExit(f"Missing app icon source: {source}")

    ICONSET.mkdir(parents=True, exist_ok=True)
    image = square_crop(Image.open(source).convert("RGBA"))
    for filename, size in SIZES.items():
        resized = image.resize((size, size), Image.Resampling.LANCZOS)
        resized.save(ICONSET / filename)


if __name__ == "__main__":
    main()
