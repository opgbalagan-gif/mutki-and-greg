"""Prepare the supplied purple-wave assist with a fixed floor pivot and scale."""
from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

from extract_mutki_combo import key

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "source_art/animations/mutki/mutki_assist_super_20260907.mp4"
REVIEW = ROOT / "artifacts/greg_super_arena"
RAW = REVIEW / "raw"
OUTPUT = ROOT / "assets/characters/mutki/assist_super"
# Retain the entire 16:9 frame and match Greg's 290px body height.
# The runtime fits only the outer wave regions into the centered 720px arena.
CANVAS = (1024, 576)
SOURCE_PIVOT = (960, 906)
SCALE = CANVAS[0] / 1920
GAME_SCALE = 290 / (636 * SCALE)
PIVOT = (SOURCE_PIVOT[0] * SCALE, SOURCE_PIVOT[1] * SCALE)
IMPACT_FRAME = 22  # Source frame 44: both palms release the wave.


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--reuse-decoded", action="store_true")
    args = parser.parse_args()
    RAW.mkdir(parents=True, exist_ok=True)
    OUTPUT.mkdir(parents=True, exist_ok=True)
    if not args.reuse_decoded:
        subprocess.run([str(ROOT / ".tools/ffmpeg.exe"), "-v", "error", "-i", str(SOURCE),
                        "-vf", r"select=not(mod(n\,2))", "-fps_mode", "vfr", "-y",
                        str(RAW / "%03d.png")], check=True)
    raw_paths = sorted(RAW.glob("*.png"))
    assert len(raw_paths) == 49, "Expected 98 source frames at 24 FPS"
    frames, previews, records = [], [], []
    for index, path in enumerate(raw_paths):
        with Image.open(path) as raw:
            frame = key(raw).resize(CANVAS, Image.Resampling.LANCZOS)
        alpha = np.asarray(frame.getchannel("A")).copy()
        alpha[alpha < 5] = 0
        frame.putalpha(Image.fromarray(alpha))
        assert frame.getbbox(), (index, "empty frame")
        rgba = np.asarray(frame)
        opaque = rgba[:, :, 3] > 220
        green = rgba[:, :, 1].astype(float) - np.maximum(rgba[:, :, 0], rgba[:, :, 2])
        assert not np.any(opaque & (green > 25)), (index, "green spill")
        destination = OUTPUT / f"mutki_assist_super_{index + 1:03d}.png"
        frame.save(destination, optimize=True)
        records.append({"file": destination.relative_to(ROOT).as_posix(),
                        "source_frame": index * 2, "alpha_bbox": frame.getbbox()})
        frames.append(frame)
        preview = Image.new("RGBA", CANVAS, "#39454e")
        preview.alpha_composite(frame)
        previews.append(preview.convert("RGB").resize((512, 288)))
    manifest = {
        "source": SOURCE.relative_to(ROOT).as_posix(),
        "source_sha256": hashlib.sha256(SOURCE.read_bytes()).hexdigest(),
        "source_fps": 24, "source_frame_count": 98, "game_fps": 12,
        "duration_seconds": len(frames) / 12, "active_frame": IMPACT_FRAME,
        "canvas": CANVAS, "source_pivot": SOURCE_PIVOT, "canvas_pivot": PIVOT,
        "extraction_scale": SCALE, "game_scale": GAME_SCALE,
        "sprite_position": [0, -(PIVOT[1] - CANVAS[1] / 2) * GAME_SCALE],
        "wave_width": 672, "uncompressed_body_region": [256, 0, 512, 576],
        "frames": records,
    }
    (OUTPUT.parent / "assist_super_manifest.json").write_text(
        json.dumps(manifest, indent=2, ensure_ascii=False), encoding="utf-8")
    previews[0].save(REVIEW / "mutki_assist_preview.webp", save_all=True,
                     append_images=previews[1:], duration=83, loop=0, quality=85)
    sheet = Image.new("RGB", (4 * 512, 3 * 316), "#202830")
    draw = ImageDraw.Draw(sheet)
    for cell, index in enumerate([0, 8, 16, 18, 20, 22, 24, 28, 32, 36, 42, 48]):
        x, y = cell % 4 * 512, cell // 4 * 316
        sheet.paste(previews[index], (x, y + 28))
        draw.text((x + 12, y + 8), f"source {index * 2} / {index / 12:.2f}s", fill="white")
    sheet.save(REVIEW / "keyed_contact.jpg", quality=93)
    print(f"ASSIST_ASSETS_PASS: {len(frames)} RGBA frames / 12 FPS / fixed pivot / no green spill")
    print(f"scale={GAME_SCALE:.8f} position={manifest['sprite_position']} impact={IMPACT_FRAME}")


if __name__ == "__main__":
    main()
