#!/usr/bin/env python3
"""Extract game-ready transparent Mutki animations from green-screen MP4 files.

The tool decodes with a local/system FFmpeg but performs chroma recovery,
alignment, shared-canvas normalization and validation itself.  It intentionally
keeps a small curated frame set instead of importing every source frame.

Usage:
  python tools/extract_video_animation.py --all
  python tools/extract_video_animation.py --attack attack_01
  python tools/extract_video_animation.py --validate
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import tempfile
from dataclasses import dataclass
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter


ROOT = Path(__file__).resolve().parents[1]
SOURCE_ROOT = ROOT / "source_art" / "animations" / "mutki"
OUTPUT_ROOT = ROOT / "assets" / "characters" / "mutki"
MANIFEST_PATH = OUTPUT_ROOT / "video_attacks_manifest.json"
CANVAS = (1024, 1024)
SAFE_PADDING_RATIO = 0.16
DESIRED_GAME_HEIGHT = 290.0


@dataclass(frozen=True)
class AttackSpec:
    source_name: str
    selected_frames: tuple[int, ...]
    fps: float
    active_frame: int


ATTACKS: dict[str, AttackSpec] = {
    "attack_01": AttackSpec(
        "mutki_attack_01_source.mp4",
        (0, 3, 6, 9, 12, 15, 18, 21, 25),
        12.0,
        3,
    ),
    "attack_02": AttackSpec(
        "mutki_attack_02_source.mp4",
        (0, 3, 6, 9, 12, 15, 18, 21, 24, 27, 30, 32),
        12.0,
        4,
    ),
    "attack_03": AttackSpec(
        "mutki_attack_03_source.mp4",
        (0, 3, 6, 9, 12, 15, 18, 21, 24, 27, 30),
        12.0,
        5,
    ),
}


def find_ffmpeg() -> Path:
    candidates = [ROOT / ".tools" / "ffmpeg.exe"]
    from_path = shutil.which("ffmpeg")
    if from_path:
        candidates.append(Path(from_path))
    for candidate in candidates:
        if candidate.exists():
            return candidate
    raise FileNotFoundError(
        "FFmpeg not found. Put ffmpeg.exe in .tools/ or add ffmpeg to PATH."
    )


def probe_video(ffmpeg: Path, source: Path) -> tuple[int, int, float, float]:
    result = subprocess.run(
        [str(ffmpeg), "-hide_banner", "-i", str(source)],
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        check=False,
    )
    text = result.stderr + result.stdout
    stream = next((line for line in text.splitlines() if "Video:" in line), "")
    size_match = re.search(r"(?<!\d)(\d{2,5})x(\d{2,5})(?!\d)", stream)
    fps_match = re.search(r"([\d.]+)\s+fps", stream)
    duration_match = re.search(r"Duration:\s*(\d+):(\d+):([\d.]+)", text)
    if not size_match or not fps_match:
        raise RuntimeError(f"Could not probe video stream: {source}")
    width, height = int(size_match.group(1)), int(size_match.group(2))
    fps = float(fps_match.group(1))
    duration = 0.0
    if duration_match:
        duration = (
            int(duration_match.group(1)) * 3600
            + int(duration_match.group(2)) * 60
            + float(duration_match.group(3))
        )
    return width, height, fps, duration


def _read_exact(stream, size: int) -> bytes:
    chunks: list[bytes] = []
    remaining = size
    while remaining:
        chunk = stream.read(remaining)
        if not chunk:
            break
        chunks.append(chunk)
        remaining -= len(chunk)
    return b"".join(chunks)


def decode_selected_frames(
    ffmpeg: Path,
    source: Path,
    width: int,
    height: int,
    wanted: tuple[int, ...],
) -> tuple[int, dict[int, np.ndarray]]:
    del width, height  # PNG pipe keeps FFmpeg's decoded dimensions explicitly.
    null_device = "NUL" if os.name == "nt" else "/dev/null"
    count_result = subprocess.run(
        [
            str(ffmpeg),
            "-v",
            "error",
            "-i",
            str(source),
            "-map",
            "0:v:0",
            "-f",
            "null",
            "-progress",
            "pipe:1",
            "-nostats",
            null_device,
        ],
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        check=True,
    )
    frame_values = re.findall(r"(?m)^frame=(\d+)$", count_result.stdout)
    if not frame_values:
        raise RuntimeError(f"Could not count frames in {source}")
    frame_count = int(frame_values[-1])

    select_expression = "+".join(f"eq(n\\,{index})" for index in wanted)
    video_filter = f"select={select_expression},format=rgb24"
    with tempfile.TemporaryDirectory(prefix="mutki-key-") as temporary:
        pattern = Path(temporary) / "frame_%03d.png"
        result = subprocess.run(
            [
                str(ffmpeg),
                "-y",
                "-v",
                "error",
                "-i",
                str(source),
                "-vf",
                video_filter,
                "-vsync",
                "0",
                str(pattern),
            ],
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            check=False,
        )
        if result.returncode:
            raise RuntimeError(f"FFmpeg PNG extraction failed for {source}: {result.stderr}")
        files = sorted(Path(temporary).glob("frame_*.png"))
        if len(files) != len(wanted):
            raise ValueError(
                f"Expected {len(wanted)} selected frames from {source.name}, got {len(files)}"
            )
        selected = {
            source_index: np.asarray(Image.open(path).convert("RGB")).copy()
            for source_index, path in zip(wanted, files)
        }
    return frame_count, selected


def clean_keyed_frame(rgba: np.ndarray) -> Image.Image:
    """Remove isolated codec/key noise while preserving nearby impact flecks."""
    alpha = rgba[:, :, 3]
    mask = alpha > 16
    height, width = mask.shape
    seen = np.zeros(mask.shape, dtype=np.uint8)
    components: list[tuple[list[tuple[int, int]], tuple[int, int, int, int]]] = []
    for start_y, start_x in zip(*np.nonzero(mask)):
        if seen[start_y, start_x]:
            continue
        queue = [(int(start_y), int(start_x))]
        seen[start_y, start_x] = 1
        pixels: list[tuple[int, int]] = []
        left = right = int(start_x)
        top = bottom = int(start_y)
        while queue:
            y, x = queue.pop()
            pixels.append((y, x))
            left, right = min(left, x), max(right, x)
            top, bottom = min(top, y), max(bottom, y)
            for ny, nx in ((y - 1, x), (y + 1, x), (y, x - 1), (y, x + 1)):
                if (
                    0 <= ny < height
                    and 0 <= nx < width
                    and mask[ny, nx]
                    and not seen[ny, nx]
                ):
                    seen[ny, nx] = 1
                    queue.append((ny, nx))
        components.append((pixels, (left, top, right + 1, bottom + 1)))

    if not components:
        raise ValueError("Chroma key produced an empty frame")
    main_pixels, main_box = max(components, key=lambda item: len(item[0]))
    keep = np.zeros(mask.shape, dtype=bool)
    for y, x in main_pixels:
        keep[y, x] = True
    main_left, main_top, main_right, main_bottom = main_box
    for pixels, box in components:
        if pixels is main_pixels:
            continue
        left, top, right, bottom = box
        touches_edge = left <= 1 or top <= 1 or right >= width - 1 or bottom >= height - 1
        gap_x = max(0, main_left - right, left - main_right)
        gap_y = max(0, main_top - bottom, top - main_bottom)
        if not touches_edge and len(pixels) >= 18 and gap_x <= 70 and gap_y <= 70:
            for y, x in pixels:
                keep[y, x] = True

    original = alpha > 0
    for _ in range(3):
        grown = keep.copy()
        grown[1:] |= keep[:-1]
        grown[:-1] |= keep[1:]
        grown[:, 1:] |= keep[:, :-1]
        grown[:, :-1] |= keep[:, 1:]
        keep = grown & original
    result = rgba.copy()
    result[:, :, 3] = np.where(keep, alpha, 0)
    return Image.fromarray(result, "RGBA")


def _border_background(rgb: np.ndarray) -> np.ndarray:
    border = max(8, min(rgb.shape[:2]) // 40)
    samples = np.concatenate(
        [
            rgb[:border].reshape(-1, 3),
            rgb[-border:].reshape(-1, 3),
            rgb[:, :border].reshape(-1, 3),
            rgb[:, -border:].reshape(-1, 3),
        ],
        axis=0,
    )
    return np.median(samples, axis=0).astype(np.float32)


def chroma_key(rgb: np.ndarray) -> Image.Image:
    """Recover foreground alpha and color from compositing over green.

    Estimating alpha from green dominance retains semi-transparent white air
    trails: a 50% white trail over green becomes 50% white rather than being
    mistaken for green background.  Dark pixels are protected so black clothes,
    hair and beard stay opaque.
    """
    work = rgb.astype(np.float32)
    background = _border_background(work)
    bg_dominance = float(background[1] - max(background[0], background[2]))
    if bg_dominance < 30.0:
        raise ValueError(f"Source does not look green-screened: background={background}")

    dominance = work[:, :, 1] - np.maximum(work[:, :, 0], work[:, :, 2])
    background_mix = np.clip((dominance - 5.0) / (bg_dominance - 5.0), 0.0, 1.0)
    alpha = 1.0 - background_mix
    dark_foreground = np.max(work, axis=2) < 68.0
    alpha[dark_foreground] = np.maximum(alpha[dark_foreground], 0.98)
    alpha[alpha < 0.035] = 0.0
    alpha[alpha > 0.985] = 1.0

    safe_alpha = np.maximum(alpha[:, :, None], 0.045)
    recovered = (work - (1.0 - alpha[:, :, None]) * background) / safe_alpha
    recovered = np.clip(recovered, 0.0, 255.0)

    alpha_image = Image.fromarray(np.uint8(np.clip(alpha * 255.0, 0, 255)), "L")
    alpha_image = alpha_image.filter(ImageFilter.GaussianBlur(radius=0.65))
    alpha_array = np.asarray(alpha_image, dtype=np.uint8).copy()
    alpha_array[alpha_array < 7] = 0
    alpha_array[alpha_array > 249] = 255

    rgba = np.empty((*rgb.shape[:2], 4), dtype=np.uint8)
    rgba[:, :, :3] = recovered.astype(np.uint8)
    rgba[:, :, 3] = alpha_array
    return Image.fromarray(rgba, "RGBA")


def content_bbox(image: Image.Image, threshold: int = 10) -> tuple[int, int, int, int]:
    alpha = np.asarray(image.getchannel("A"))
    ys, xs = np.nonzero(alpha > threshold)
    if not len(xs):
        raise ValueError("Empty keyed frame")
    return int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1


def reference_anchor(image: Image.Image) -> tuple[float, float, float]:
    left, top, right, bottom = content_bbox(image, 40)
    alpha = np.asarray(image.getchannel("A"))
    band_top = max(top, bottom - max(18, int((bottom - top) * 0.12)))
    ys, xs = np.nonzero(alpha[band_top:bottom, left:right] > 96)
    anchor_x = float(np.median(xs + left)) if len(xs) else (left + right) * 0.5
    return anchor_x, float(bottom), float(bottom - top)


def render_frame(
    frame: Image.Image,
    source_anchor: tuple[float, float],
    canvas_anchor: tuple[float, float],
    scale: float,
) -> Image.Image:
    resized = frame.resize(
        (round(frame.width * scale), round(frame.height * scale)),
        Image.Resampling.LANCZOS,
    )
    paste_x = round(canvas_anchor[0] - source_anchor[0] * scale)
    paste_y = round(canvas_anchor[1] - source_anchor[1] * scale)
    canvas = Image.new("RGBA", CANVAS, (0, 0, 0, 0))
    canvas.alpha_composite(resized, (paste_x, paste_y))
    return canvas


def prepare_all() -> dict:
    ffmpeg = find_ffmpeg()
    decoded: dict[str, dict] = {}
    first_anchors: list[tuple[float, float, float]] = []

    for attack_name, spec in ATTACKS.items():
        source = SOURCE_ROOT / spec.source_name
        if not source.exists():
            raise FileNotFoundError(source)
        width, height, source_fps, duration = probe_video(ffmpeg, source)
        frame_count, raw_frames = decode_selected_frames(
            ffmpeg, source, width, height, spec.selected_frames
        )
        keyed = {
            index: clean_keyed_frame(np.asarray(chroma_key(raw_frames[index])))
            for index in spec.selected_frames
        }
        first_anchors.append(reference_anchor(keyed[spec.selected_frames[0]]))
        decoded[attack_name] = {
            "spec": spec,
            "source": source,
            "source_size": (width, height),
            "source_fps": source_fps,
            "duration": duration,
            "source_frame_count": frame_count,
            "frames": keyed,
        }

    source_anchor = (
        float(np.median([item[0] for item in first_anchors])),
        float(np.median([item[1] for item in first_anchors])),
    )
    reference_height = float(np.median([item[2] for item in first_anchors]))

    relative_boxes: list[tuple[float, float, float, float]] = []
    for attack in decoded.values():
        for frame in attack["frames"].values():
            left, top, right, bottom = content_bbox(frame)
            relative_boxes.append(
                (
                    left - source_anchor[0],
                    top - source_anchor[1],
                    right - source_anchor[0],
                    bottom - source_anchor[1],
                )
            )
    min_x = min(box[0] for box in relative_boxes)
    min_y = min(box[1] for box in relative_boxes)
    max_x = max(box[2] for box in relative_boxes)
    max_y = max(box[3] for box in relative_boxes)
    safe_w = CANVAS[0] * (1.0 - 2.0 * SAFE_PADDING_RATIO)
    safe_h = CANVAS[1] * (1.0 - 2.0 * SAFE_PADDING_RATIO)
    fit_scale = min(safe_w / (max_x - min_x), safe_h / (max_y - min_y))
    detail_scale = 400.0 / reference_height
    extraction_scale = min(fit_scale, detail_scale)
    scaled_w = (max_x - min_x) * extraction_scale
    scaled_h = (max_y - min_y) * extraction_scale
    canvas_anchor = (
        (CANVAS[0] - scaled_w) * 0.5 - min_x * extraction_scale,
        (CANVAS[1] - scaled_h) * 0.5 - min_y * extraction_scale,
    )
    rendered_body_height = reference_height * extraction_scale
    godot_scale = DESIRED_GAME_HEIGHT / rendered_body_height
    sprite_position = (
        -(canvas_anchor[0] - CANVAS[0] * 0.5) * godot_scale,
        -(canvas_anchor[1] - CANVAS[1] * 0.5) * godot_scale,
    )

    manifest: dict = {
        "canvas": list(CANVAS),
        "safe_padding_ratio": SAFE_PADDING_RATIO,
        "source_anchor": [round(source_anchor[0], 3), round(source_anchor[1], 3)],
        "canvas_anchor": [round(canvas_anchor[0], 3), round(canvas_anchor[1], 3)],
        "extraction_scale": round(extraction_scale, 6),
        "reference_body_height": round(reference_height, 3),
        "rendered_body_height": round(rendered_body_height, 3),
        "godot_scale": round(godot_scale, 6),
        "sprite_position": [round(sprite_position[0], 3), round(sprite_position[1], 3)],
        "attacks": {},
    }

    for attack_name, attack in decoded.items():
        spec: AttackSpec = attack["spec"]
        destination = OUTPUT_ROOT / attack_name
        destination.mkdir(parents=True, exist_ok=True)
        for old in destination.glob("*.png"):
            old.unlink()
        records: list[dict] = []
        for output_index, source_index in enumerate(spec.selected_frames, start=1):
            rendered = render_frame(
                attack["frames"][source_index], source_anchor, canvas_anchor, extraction_scale
            )
            file_name = f"mutki_{attack_name}_{output_index:03d}.png"
            output = destination / file_name
            rendered.save(output, optimize=True)
            records.append(
                {
                    "file": output.relative_to(ROOT).as_posix(),
                    "source_frame": source_index,
                    "content_bbox": list(content_bbox(rendered)),
                }
            )
        manifest["attacks"][attack_name] = {
            "source": attack["source"].relative_to(ROOT).as_posix(),
            "source_size": list(attack["source_size"]),
            "source_fps": attack["source_fps"],
            "source_duration": attack["duration"],
            "source_frame_count": attack["source_frame_count"],
            "game_fps": spec.fps,
            "active_frame": spec.active_frame,
            "selected_source_frames": list(spec.selected_frames),
            "frames": records,
        }

    OUTPUT_ROOT.mkdir(parents=True, exist_ok=True)
    MANIFEST_PATH.write_text(
        json.dumps(manifest, indent=2, ensure_ascii=False), encoding="utf-8"
    )
    return manifest


def validate() -> list[str]:
    problems: list[str] = []
    if not MANIFEST_PATH.exists():
        return [f"missing manifest: {MANIFEST_PATH.relative_to(ROOT)}"]
    manifest = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
    expected_canvas = tuple(manifest["canvas"])
    minimum_margin = round(min(expected_canvas) * 0.12)
    for attack_name, attack in manifest["attacks"].items():
        if not (6 <= len(attack["frames"]) <= 15):
            problems.append(f"{attack_name}: unsuitable frame count")
        if not (0 <= attack["active_frame"] < len(attack["frames"])):
            problems.append(f"{attack_name}: active frame outside sequence")
        for record in attack["frames"]:
            path = ROOT / record["file"]
            if not path.exists():
                problems.append(f"missing: {record['file']}")
                continue
            with Image.open(path) as image:
                if image.mode != "RGBA":
                    problems.append(f"no RGBA: {record['file']}")
                if image.size != expected_canvas:
                    problems.append(f"wrong canvas: {record['file']} = {image.size}")
                bbox = image.getchannel("A").getbbox()
                if bbox is None:
                    problems.append(f"empty: {record['file']}")
                elif (
                    bbox[0] < minimum_margin
                    or bbox[1] < minimum_margin
                    or bbox[2] > expected_canvas[0] - minimum_margin
                    or bbox[3] > expected_canvas[1] - minimum_margin
                ):
                    problems.append(f"unsafe crop margin: {record['file']} = {bbox}")
    return problems


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--all", action="store_true")
    parser.add_argument("--attack", choices=sorted(ATTACKS))
    parser.add_argument("--validate", action="store_true")
    args = parser.parse_args()
    if not any((args.all, args.attack, args.validate)):
        parser.error("choose --all, --attack, or --validate")

    # Shared alignment is calculated across all three attacks even when one is
    # requested; this prevents per-animation scale and pivot drift.
    if args.all or args.attack:
        manifest = prepare_all()
        for name, attack in manifest["attacks"].items():
            print(
                f"{name}: {attack['source_frame_count']} source -> "
                f"{len(attack['frames'])} game frames @ {attack['game_fps']} FPS"
            )
        print(
            f"canvas={manifest['canvas']} anchor={manifest['canvas_anchor']} "
            f"godot_scale={manifest['godot_scale']} "
            f"sprite_position={manifest['sprite_position']}"
        )
    if args.all or args.attack or args.validate:
        problems = validate()
        if problems:
            print("validation failed:")
            for problem in problems:
                print("  - " + problem)
            return 1
        print("validation passed: RGBA, shared canvas, safe margins and active frames OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
