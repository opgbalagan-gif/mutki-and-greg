#!/usr/bin/env python3
"""Prepare transparent, baseline-aligned game frames from the concept sheets.

The source art is deliberately not treated as a regular grid.  Every usable pose
has an explicit crop box.  Background removal fits the local paper/gradient from
the crop border and flood-fills only pixels connected to an outer edge, so black
clothing and internal shadows survive.

Usage:
  python tools/prepare_character_sprites.py --all
  python tools/prepare_character_sprites.py --character mutki
  python tools/prepare_character_sprites.py --character greg
  python tools/prepare_character_sprites.py --enemies
  python tools/prepare_character_sprites.py --validate
"""

from __future__ import annotations

import argparse
import json
from collections import deque
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable

import numpy as np
from PIL import Image, ImageFilter


ROOT = Path(__file__).resolve().parents[1]
CANVAS = (512, 512)
BASELINE_Y = 458
EDGE_MARGIN = 14


@dataclass(frozen=True)
class Frame:
    animation: str
    box: tuple[int, int, int, int]
    name: str
    # A stable group scale is intentional.  Individual poses are never fit-to-box.
    scale: float = 1.55
    x_offset: int = 0


# Explicit boxes keep headings and neighbouring poses out of the resulting PNGs.
# The punch sequence favours readable anticipation/contact/recovery over frame count.
CHARACTERS: dict[str, dict] = {
    "mutki": {
        "source": ROOT / "source_art" / "mutki_animation_source.png",
        "output": ROOT / "assets" / "characters" / "mutki",
        "frames": [
            Frame("idle", (42, 28, 205, 230), "mutki_idle_01"),
            # Keep generous source-space padding around every pose.  The feet on
            # these two idle drawings extend farther left than the torso, so the
            # previous tight boxes visibly sliced the left sneaker in-game.
            Frame("idle", (225, 28, 412, 230), "mutki_idle_02"),
            Frame("idle", (430, 28, 616, 230), "mutki_idle_03"),
            Frame("punch", (430, 28, 616, 230), "mutki_punch_01"),
            Frame("punch", (625, 24, 815, 232), "mutki_punch_02"),
            Frame("punch", (812, 24, 1045, 232), "mutki_punch_03"),
            Frame("punch", (1050, 22, 1325, 236), "mutki_punch_04", x_offset=-57),
            Frame("punch", (1310, 26, 1518, 232), "mutki_punch_05"),
            Frame("heavy_punch", (225, 252, 430, 440), "mutki_heavy_punch_01"),
            Frame("heavy_punch", (445, 246, 750, 442), "mutki_heavy_punch_02", x_offset=-49),
            Frame("heavy_punch", (745, 246, 1015, 442), "mutki_heavy_punch_03", x_offset=-46),
            Frame("heavy_punch", (1020, 244, 1310, 444), "mutki_heavy_punch_04", x_offset=18),
            Frame("kick", (200, 650, 390, 842), "mutki_kick_01"),
            Frame("kick", (395, 642, 610, 842), "mutki_kick_02"),
            Frame("kick", (600, 638, 820, 842), "mutki_kick_03"),
            Frame("hit", (1310, 458, 1518, 640), "mutki_hit_01"),
        ],
    },
    "greg": {
        "source": ROOT / "source_art" / "greg_animation_source.png",
        "output": ROOT / "assets" / "characters" / "greg",
        "frames": [
            Frame("idle", (42, 28, 205, 242), "greg_idle_01"),
            Frame("idle", (252, 28, 412, 242), "greg_idle_02"),
            Frame("idle", (452, 28, 616, 242), "greg_idle_03"),
            Frame("punch", (625, 24, 815, 244), "greg_punch_01"),
            Frame("punch", (812, 24, 1040, 244), "greg_punch_02"),
            Frame("punch", (1030, 22, 1298, 248), "greg_punch_03"),
            Frame("combo", (252, 252, 430, 448), "greg_combo_01"),
            Frame("combo", (442, 246, 710, 448), "greg_combo_02", x_offset=-14),
            Frame("combo", (700, 246, 945, 448), "greg_combo_03", x_offset=-18),
            Frame("combo", (925, 244, 1195, 450), "greg_combo_04"),
            Frame("kick", (222, 650, 410, 848), "greg_kick_01"),
            Frame("kick", (395, 642, 620, 848), "greg_kick_02"),
            Frame("kick", (610, 638, 835, 848), "greg_kick_03"),
            Frame("hit", (1310, 458, 1518, 650), "greg_hit_01"),
            Frame("super", (40, 846, 265, 1012), "greg_super_01"),
            Frame("super", (245, 840, 490, 1012), "greg_super_02"),
            Frame("super", (505, 836, 735, 1012), "greg_super_03", x_offset=-3),
            Frame("super", (1110, 838, 1320, 1012), "greg_super_05"),
            Frame("super", (1300, 838, 1520, 1012), "greg_super_06"),
        ],
    },
}


def _enemy_frames(row: int, prefix: str, scale: float = 2.0) -> list[Frame]:
    """Return hand-authored boxes for one enemy row (not a uniform grid)."""
    bands = [
        (82, 225),
        (284, 427),
        (484, 633),
        (686, 827),
        (886, 1023),
    ]
    top, bottom = bands[row]
    walk_boxes = (
        [(414, top, 516, bottom), (535, top, 635, bottom)]
        if row == 2
        else [(316, top, 412, bottom), (518, top, 635, bottom)]
    )
    active_left = 760 if row == 2 else 795
    active_right = 914 if row == 2 else 925
    boxes = {
        "idle": [(12, top, 105, bottom), (105, top, 205, bottom)],
        "walk": walk_boxes,
        "attack": [(active_left, top, active_right, bottom)],
        "hit": [(928, top, 1008, bottom)],
        "death": [(1380, top, 1535, bottom)],
    }
    result: list[Frame] = []
    for animation, crops in boxes.items():
        for index, box in enumerate(crops, start=1):
            result.append(
                Frame(
                    animation,
                    box,
                    f"{prefix}_{animation}_{index:02d}",
                    scale=scale,
                )
            )
    return result


ENEMIES: list[dict] = [
    {"id": "enemy_01_thug", "prefix": "enemy_01", "row": 0, "scale": 2.00},
    {"id": "enemy_02_hoodie", "prefix": "enemy_02", "row": 1, "scale": 2.00},
    {"id": "enemy_03_big_guy", "prefix": "enemy_03", "row": 2, "scale": 1.78},
    {"id": "enemy_04_knife", "prefix": "enemy_04", "row": 3, "scale": 2.00},
    {"id": "enemy_05_bandana", "prefix": "enemy_05", "row": 4, "scale": 2.00},
]


def _fit_background_plane(rgb: np.ndarray) -> np.ndarray:
    """Predict a smooth local background from pixels on the four crop edges."""
    h, w, _ = rgb.shape
    yy, xx = np.mgrid[0:h, 0:w]
    edge = np.zeros((h, w), dtype=bool)
    width = max(3, min(h, w) // 24)
    edge[:width] = True
    edge[-width:] = True
    edge[:, :width] = True
    edge[:, -width:] = True
    x = xx[edge].astype(np.float64) / max(w - 1, 1)
    y = yy[edge].astype(np.float64) / max(h - 1, 1)
    design = np.column_stack([x, y, np.ones_like(x)])
    full = np.column_stack(
        [
            xx.ravel().astype(np.float64) / max(w - 1, 1),
            yy.ravel().astype(np.float64) / max(h - 1, 1),
            np.ones(h * w),
        ]
    )
    predicted = np.empty((h * w, 3), dtype=np.float64)
    for channel in range(3):
        coeff, *_ = np.linalg.lstsq(design, rgb[:, :, channel][edge], rcond=None)
        predicted[:, channel] = full @ coeff
    return predicted.reshape(h, w, 3)


def remove_connected_background(image: Image.Image, tolerance: float = 42.0) -> Image.Image:
    """Remove only background-like pixels reachable from a crop boundary."""
    rgba = np.asarray(image.convert("RGBA")).copy()
    rgb = rgba[:, :, :3].astype(np.float64)
    expected = _fit_background_plane(rgb)
    distance = np.linalg.norm(rgb - expected, axis=2)
    candidate = distance < tolerance
    h, w = candidate.shape
    visited = np.zeros((h, w), dtype=np.uint8)
    queue: deque[tuple[int, int]] = deque()

    for x in range(w):
        if candidate[0, x]:
            queue.append((0, x))
        if candidate[h - 1, x]:
            queue.append((h - 1, x))
    for y in range(h):
        if candidate[y, 0]:
            queue.append((y, 0))
        if candidate[y, w - 1]:
            queue.append((y, w - 1))

    while queue:
        y, x = queue.popleft()
        if visited[y, x] or not candidate[y, x]:
            continue
        visited[y, x] = 1
        if y:
            queue.append((y - 1, x))
        if y + 1 < h:
            queue.append((y + 1, x))
        if x:
            queue.append((y, x - 1))
        if x + 1 < w:
            queue.append((y, x + 1))

    # A one-pixel feather avoids a hard halo without eating black outlines.
    background = Image.fromarray((visited * 255).astype(np.uint8), "L")
    soft_background = background.filter(ImageFilter.GaussianBlur(radius=0.8))
    alpha = 255 - np.asarray(soft_background, dtype=np.uint8)
    rgba[:, :, 3] = np.minimum(rgba[:, :, 3], alpha)
    return _remove_distant_components(Image.fromarray(rgba, "RGBA"))


def _remove_distant_components(image: Image.Image) -> Image.Image:
    """Drop disconnected fragments from adjacent concept-sheet poses or labels."""
    rgba = np.asarray(image).copy()
    mask = rgba[:, :, 3] > 32
    h, w = mask.shape
    # Concept-sheet ground shadows sometimes bridge two neighbouring poses.  Cut
    # that thin bridge only for component analysis; nearby sole pixels are grown
    # back after the wanted silhouette is selected.
    connectivity_mask = mask.copy()
    connectivity_mask[max(0, h - 7) :, :] = False
    seen = np.zeros((h, w), dtype=np.uint8)
    components: list[tuple[list[tuple[int, int]], tuple[int, int, int, int]]] = []
    for start_y, start_x in zip(*np.nonzero(connectivity_mask & (seen == 0))):
        if seen[start_y, start_x]:
            continue
        queue: deque[tuple[int, int]] = deque([(int(start_y), int(start_x))])
        seen[start_y, start_x] = 1
        pixels: list[tuple[int, int]] = []
        min_x = max_x = int(start_x)
        min_y = max_y = int(start_y)
        while queue:
            y, x = queue.popleft()
            pixels.append((y, x))
            min_x, max_x = min(min_x, x), max(max_x, x)
            min_y, max_y = min(min_y, y), max(max_y, y)
            for ny, nx in ((y - 1, x), (y + 1, x), (y, x - 1), (y, x + 1)):
                if 0 <= ny < h and 0 <= nx < w and connectivity_mask[ny, nx] and not seen[ny, nx]:
                    seen[ny, nx] = 1
                    queue.append((ny, nx))
        components.append((pixels, (min_x, min_y, max_x + 1, max_y + 1)))

    if not components:
        return image
    main_pixels, main_box = max(components, key=lambda item: len(item[0]))
    keep = np.zeros((h, w), dtype=bool)
    for y, x in main_pixels:
        keep[y, x] = True
    ml, mt, mr, mb = main_box
    for pixels, box in components:
        if pixels is main_pixels:
            continue
        left, top, right, bottom = box
        touches_crop_edge = left <= 1 or top <= 1 or right >= w - 1 or bottom >= h - 1
        gap_x = max(0, ml - right, left - mr)
        gap_y = max(0, mt - bottom, top - mb)
        # Keep only pieces effectively touching/inside the main silhouette.  The
        # game adds its own impact streaks, while neighbouring poses must vanish.
        inside_main_span = left >= ml - 6 and right <= mr + 6 and top >= mt - 6 and bottom <= mb + 6
        if not touches_crop_edge and len(pixels) >= 18 and (inside_main_span or (gap_x <= 5 and gap_y <= 5)):
            for y, x in pixels:
                keep[y, x] = True
    # Reattach up to six pixels of anti-aliased soles around the chosen body.
    for _ in range(6):
        grown = keep.copy()
        grown[1:, :] |= keep[:-1, :]
        grown[:-1, :] |= keep[1:, :]
        grown[:, 1:] |= keep[:, :-1]
        grown[:, :-1] |= keep[:, 1:]
        keep = grown & mask
    rgba[:, :, 3] = np.where(keep, rgba[:, :, 3], 0)
    return Image.fromarray(rgba, "RGBA")


def _content_bbox(image: Image.Image) -> tuple[int, int, int, int] | None:
    alpha = np.asarray(image.getchannel("A"))
    ys, xs = np.nonzero(alpha > 24)
    if not len(xs):
        return None
    return int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1


def _foot_anchor(image: Image.Image, bbox: tuple[int, int, int, int]) -> tuple[float, float]:
    """Estimate the body anchor from the lower body, not the extended fist."""
    alpha = np.asarray(image.getchannel("A"))
    left, top, right, bottom = bbox
    height = bottom - top
    band_top = top + int(height * 0.62)
    band_bottom = top + int(height * 0.92)
    ys, xs = np.nonzero(alpha[band_top:band_bottom, left:right] > 96)
    if len(xs):
        anchor_x = float(np.median(xs + left))
    else:
        anchor_x = (left + right) * 0.5
    return anchor_x, float(bottom)


def normalize_frame(frame: Image.Image, scale: float, x_offset: int = 0) -> Image.Image:
    bbox = _content_bbox(frame)
    if bbox is None:
        raise ValueError("No foreground found in crop")
    anchor_x, anchor_y = _foot_anchor(frame, bbox)
    resized = frame.resize(
        (max(1, round(frame.width * scale)), max(1, round(frame.height * scale))),
        Image.Resampling.LANCZOS,
    )
    canvas = Image.new("RGBA", CANVAS, (0, 0, 0, 0))
    paste_x = round(CANVAS[0] * 0.5 + x_offset - anchor_x * scale)
    paste_y = round(BASELINE_Y - anchor_y * scale)
    canvas.alpha_composite(resized, (paste_x, paste_y))
    return canvas


def prepare_frames(source_path: Path, output_root: Path, frames: Iterable[Frame]) -> list[dict]:
    source = Image.open(source_path).convert("RGB")
    # Only remove files produced by this tool, inside its narrowly-scoped output.
    for animation_dir in output_root.iterdir() if output_root.exists() else ():
        if animation_dir.is_dir():
            for old_frame in animation_dir.glob("*.png"):
                old_frame.unlink()
    manifest: list[dict] = []
    for frame in frames:
        crop = source.crop(frame.box)
        cutout = remove_connected_background(crop)
        normalized = normalize_frame(cutout, frame.scale, frame.x_offset)
        destination = output_root / frame.animation / f"{frame.name}.png"
        destination.parent.mkdir(parents=True, exist_ok=True)
        normalized.save(destination, optimize=True)
        bbox = _content_bbox(normalized)
        manifest.append(
            {
                "animation": frame.animation,
                "name": frame.name,
                "source_box": list(frame.box),
                "file": destination.relative_to(ROOT).as_posix(),
                "canvas": list(CANVAS),
                "baseline": BASELINE_Y,
                "content_bbox": list(bbox) if bbox else None,
            }
        )
    output_root.mkdir(parents=True, exist_ok=True)
    (output_root / "frames_manifest.json").write_text(
        json.dumps(manifest, indent=2, ensure_ascii=False), encoding="utf-8"
    )
    return manifest


def prepare_character(name: str) -> list[dict]:
    config = CHARACTERS[name]
    for animation in ("idle", "punch", "heavy_punch", "kick", "hit", "combo", "super"):
        (config["output"] / animation).mkdir(parents=True, exist_ok=True)
    return prepare_frames(config["source"], config["output"], config["frames"])


def prepare_enemies() -> dict[str, list[dict]]:
    source = ROOT / "source_art" / "enemies_animation_source.png"
    result: dict[str, list[dict]] = {}
    for enemy in ENEMIES:
        output = ROOT / "assets" / "enemies" / enemy["id"]
        frames = _enemy_frames(enemy["row"], enemy["prefix"], enemy["scale"])
        result[enemy["id"]] = prepare_frames(source, output, frames)
    return result


def validate_outputs() -> list[str]:
    problems: list[str] = []
    roots = [
        ROOT / "assets" / "characters" / "mutki",
        ROOT / "assets" / "characters" / "greg",
        *[ROOT / "assets" / "enemies" / enemy["id"] for enemy in ENEMIES],
    ]
    for root in roots:
        manifest_path = root / "frames_manifest.json"
        if not manifest_path.exists():
            problems.append(f"missing manifest: {manifest_path.relative_to(ROOT)}")
            continue
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        for record in manifest:
            path = ROOT / record["file"]
            if not path.exists():
                problems.append(f"missing frame: {record['file']}")
                continue
            with Image.open(path) as image:
                if image.mode != "RGBA":
                    problems.append(f"no alpha: {record['file']}")
                if image.size != CANVAS:
                    problems.append(f"wrong canvas: {record['file']} = {image.size}")
                bbox = image.getchannel("A").getbbox()
                if bbox is None:
                    problems.append(f"empty frame: {record['file']}")
                else:
                    if bbox[3] > BASELINE_Y + 5:
                        problems.append(f"baseline overflow: {record['file']} = {bbox[3]}")
                    if bbox[0] < EDGE_MARGIN or bbox[1] < EDGE_MARGIN or bbox[2] > CANVAS[0] - EDGE_MARGIN:
                        problems.append(f"edge crop: {record['file']} = {bbox}")
    return problems


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--all", action="store_true")
    parser.add_argument("--character", choices=sorted(CHARACTERS))
    parser.add_argument("--enemies", action="store_true")
    parser.add_argument("--validate", action="store_true")
    args = parser.parse_args()

    if not any((args.all, args.character, args.enemies, args.validate)):
        parser.error("choose --all, --character, --enemies, or --validate")

    if args.all or args.character:
        names = sorted(CHARACTERS) if args.all else [args.character]
        for name in names:
            records = prepare_character(name)
            print(f"prepared {name}: {len(records)} frames")
    if args.all or args.enemies:
        records = prepare_enemies()
        print("prepared enemies: " + ", ".join(f"{k}={len(v)}" for k, v in records.items()))
    if args.all or args.validate:
        problems = validate_outputs()
        if problems:
            print("validation failed:")
            for problem in problems:
                print(f"  - {problem}")
            return 1
        print("validation passed: RGBA, 512x512, baseline and manifests OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
