#!/usr/bin/env python3
"""Prepare the supplied Greg health-frame artwork for Godot.

The source has a light neutral background.  Only neutral, bright pixels connected
to the image edge are removed, so isolated highlights in the artwork are kept.
An additional foreground copy opens a conservative rectangle inside the black
bar window; the runtime cyan fill is drawn underneath that copy.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw


DEFAULT_SOURCE = Path(r"C:\Users\Comp\Downloads\ChatGPT Image 1 сент. 2026 г., 03_46_56.png")
DEFAULT_OUTPUT = Path("assets/ui/hud/greg_health_frame.png")

# Coordinates in the uncropped 1672x941 source.  This is deliberately inset from
# the bevels and blue border so a rectangular fill can never cover the artwork.
SOURCE_FILL_RECT = (540, 493, 1470, 605)


def edge_connected_background(rgb: np.ndarray) -> np.ndarray:
    minimum = rgb.min(axis=2)
    maximum = rgb.max(axis=2)
    luminance = rgb.mean(axis=2)
    candidate = (minimum >= 155) & ((maximum - minimum) <= 34) & (luminance >= 168)

    height, width = candidate.shape
    padded = Image.new("L", (width + 2, height + 2), 255)
    padded.paste(Image.fromarray((candidate * 255).astype(np.uint8), "L"), (1, 1))
    ImageDraw.floodfill(padded, (0, 0), 128)
    flooded = np.asarray(padded, dtype=np.uint8)[1:-1, 1:-1]
    return flooded == 128


def prepare(source: Path, output: Path) -> dict[str, object]:
    source_image = Image.open(source).convert("RGB")
    rgb = np.asarray(source_image, dtype=np.uint8)
    background = edge_connected_background(rgb)

    rgba = np.dstack((rgb, np.where(background, 0, 255).astype(np.uint8)))
    cleaned = Image.fromarray(rgba, "RGBA")
    alpha_bbox = cleaned.getchannel("A").getbbox()
    if alpha_bbox is None:
        raise RuntimeError("Background extraction removed the entire image")

    padding = 4
    left = max(0, alpha_bbox[0] - padding)
    top = max(0, alpha_bbox[1] - padding)
    right = min(cleaned.width, alpha_bbox[2] + padding)
    bottom = min(cleaned.height, alpha_bbox[3] + padding)
    crop_box = (left, top, right, bottom)
    cleaned = cleaned.crop(crop_box)

    output.parent.mkdir(parents=True, exist_ok=True)
    cleaned.save(output, optimize=True)

    fill_left = SOURCE_FILL_RECT[0] - left
    fill_top = SOURCE_FILL_RECT[1] - top
    fill_right = SOURCE_FILL_RECT[2] - left
    fill_bottom = SOURCE_FILL_RECT[3] - top
    fill_rect = (fill_left, fill_top, fill_right, fill_bottom)

    foreground = cleaned.copy()
    foreground_alpha = foreground.getchannel("A")
    ImageDraw.Draw(foreground_alpha).rectangle(fill_rect, fill=0)
    foreground.putalpha(foreground_alpha)
    foreground_path = output.with_name("greg_health_frame_foreground.png")
    foreground.save(foreground_path, optimize=True)

    manifest = {
        "source": str(source),
        "source_size": list(source_image.size),
        "crop_box": list(crop_box),
        "output_size": list(cleaned.size),
        "fill_rect": [fill_left, fill_top, fill_right - fill_left, fill_bottom - fill_top],
        "removed_background_pixels": int(background.sum()),
        "frame": str(output.as_posix()),
        "foreground": str(foreground_path.as_posix()),
    }
    manifest_path = output.with_name("greg_health_frame_manifest.json")
    manifest_path.write_text(json.dumps(manifest, indent=2, ensure_ascii=False), encoding="utf-8")
    return manifest


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, default=DEFAULT_SOURCE)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    args = parser.parse_args()
    print(json.dumps(prepare(args.source, args.output), indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()
