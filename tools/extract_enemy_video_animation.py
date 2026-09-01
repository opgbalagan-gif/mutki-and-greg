#!/usr/bin/env python3
"""Extract the ordinary enemy's green-screen videos into aligned RGBA frames."""

from __future__ import annotations

import argparse
import json
from dataclasses import dataclass
from pathlib import Path

import numpy as np
from PIL import Image

from extract_video_animation import (
    chroma_key,
    clean_keyed_frame,
    content_bbox,
    decode_selected_frames,
    find_ffmpeg,
    probe_video,
    reference_anchor,
)


ROOT = Path(__file__).resolve().parents[1]
SOURCE_ROOT = ROOT / "source_art" / "animations" / "enemies" / "enemy_01_thug"
OUTPUT_ROOT = ROOT / "assets" / "enemies" / "enemy_01_thug"
MANIFEST_PATH = OUTPUT_ROOT / "video_animations_manifest.json"
CANVAS = (512, 512)
CANVAS_ANCHOR = (256.0, 458.0)
TARGET_STANDING_HEIGHT = 244.0
SAFE_MARGIN = 10.0
FRAME_HEIGHT_NORMALIZED = {"walk_video"}


@dataclass(frozen=True)
class AnimationSpec:
    source_name: str
    selected_frames: tuple[int, ...]
    fps: float
    active_frame: int = 0
    round_trip: bool = False


ANIMATIONS: dict[str, AnimationSpec] = {
    # The supplied set has no separate idle clip.  The first attack frame is a
    # clean guard pose and keeps every transition in the same visual style.
    "idle_video": AnimationSpec("enemy_attack_01_source.mp4", (0,), 1.0),
    # Frames after 66 transition from walking into a one-off guard pose.  The
    # 0..66 section is the repeatable walk cycle.
    "walk_video": AnimationSpec(
        "enemy_walk_source.mp4", tuple(range(0, 67, 2)), 15.0
    ),
    # The first punch ends extended, so Godot plays it forward and back once.
    "attack_01_video": AnimationSpec(
        "enemy_attack_01_source.mp4", tuple(range(0, 17, 2)), 15.0, 5, True
    ),
    "attack_02_video": AnimationSpec(
        "enemy_attack_02_source.mp4", tuple(range(0, 27, 2)), 15.0, 5
    ),
    # Remove the long guard holds around the actual reaction.
    "hit_video": AnimationSpec(
        "enemy_hit_source.mp4", tuple(range(4, 33, 2)), 15.0
    ),
    "death_01_video": AnimationSpec(
        "enemy_death_01_source.mp4", tuple(range(4, 65, 3)), 12.0
    ),
    # Frame zero contains a stray final pose from the preceding generation.
    "death_02_video": AnimationSpec(
        "enemy_death_02_source.mp4", tuple(range(12, 64, 3)), 12.0
    ),
}


def render_frame(
    frame: Image.Image,
    anchor_x: float,
    source_bottom: float,
    scale: float,
) -> Image.Image:
    left, top, right, bottom = content_bbox(frame)
    padding = 3
    crop_left = max(0, left - padding)
    crop_top = max(0, top - padding)
    crop_right = min(frame.width, right + padding)
    crop_bottom = min(frame.height, bottom + padding)
    cropped = frame.crop((crop_left, crop_top, crop_right, crop_bottom))
    resized = cropped.resize(
        (max(1, round(cropped.width * scale)), max(1, round(cropped.height * scale))),
        Image.Resampling.LANCZOS,
    )
    paste_x = round(CANVAS_ANCHOR[0] - (anchor_x - crop_left) * scale)
    paste_y = round(CANVAS_ANCHOR[1] - (source_bottom - crop_top) * scale)
    canvas = Image.new("RGBA", CANVAS, (0, 0, 0, 0))
    canvas.alpha_composite(resized, (paste_x, paste_y))
    return canvas


def prepare_all() -> dict:
    ffmpeg = find_ffmpeg()
    decoded: dict[str, dict] = {}

    for animation_name, spec in ANIMATIONS.items():
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
        first = keyed[spec.selected_frames[0]]
        first_left, first_top, first_right, first_bottom = content_bbox(first)
        first_anchor_x, _, _ = reference_anchor(first)
        standing_height = float(first_bottom - first_top)
        decoded[animation_name] = {
            "spec": spec,
            "source": source,
            "source_size": (width, height),
            "source_fps": source_fps,
            "duration": duration,
            "source_frame_count": frame_count,
            "frames": keyed,
            "anchor_x": first_anchor_x,
            "standing_height": standing_height,
            "scale": TARGET_STANDING_HEIGHT / standing_height,
        }

    # The long white incoming-hit trails deliberately reach beyond the actor.
    # They must not make the character smaller, so scale is based on body height
    # alone.  The 512 px canvas still safely contains every body and fallen pose.
    fit_multiplier = 1.0

    manifest: dict = {
        "canvas": list(CANVAS),
        "canvas_anchor": list(CANVAS_ANCHOR),
        "target_standing_height": TARGET_STANDING_HEIGHT,
        "fit_multiplier": round(fit_multiplier, 6),
        "sprite_position": [0.0, -202.0],
        "sprite_scale": 1.0,
        "animations": {},
    }

    for animation_name, animation in decoded.items():
        spec: AnimationSpec = animation["spec"]
        final_scale = animation["scale"] * fit_multiplier
        destination = OUTPUT_ROOT / animation_name
        destination.mkdir(parents=True, exist_ok=True)
        for old in destination.glob("*.png"):
            old.unlink()
        records: list[dict] = []
        for output_index, source_index in enumerate(spec.selected_frames, start=1):
            frame = animation["frames"][source_index]
            frame_box = content_bbox(frame)
            source_bottom = float(frame_box[3])
            frame_scale = final_scale
            if animation_name in FRAME_HEIGHT_NORMALIZED:
                frame_scale = TARGET_STANDING_HEIGHT / float(frame_box[3] - frame_box[1])
            rendered = render_frame(
                frame, animation["anchor_x"], source_bottom, frame_scale
            )
            file_name = f"enemy_01_{animation_name}_{output_index:03d}.png"
            output = destination / file_name
            rendered.save(output, optimize=True)
            records.append(
                {
                    "file": output.relative_to(ROOT).as_posix(),
                    "source_frame": source_index,
                    "render_scale": round(frame_scale, 6),
                    "content_bbox": list(content_bbox(rendered)),
                }
            )
        manifest["animations"][animation_name] = {
            "source": animation["source"].relative_to(ROOT).as_posix(),
            "source_size": list(animation["source_size"]),
            "source_fps": animation["source_fps"],
            "source_duration": animation["duration"],
            "source_frame_count": animation["source_frame_count"],
            "selected_source_frames": list(spec.selected_frames),
            "game_fps": spec.fps,
            "active_frame": spec.active_frame,
            "round_trip": spec.round_trip,
            "render_scale": round(final_scale, 6),
            "rendered_standing_height": round(
                animation["standing_height"] * final_scale, 3
            ),
            "frames": records,
        }

    OUTPUT_ROOT.mkdir(parents=True, exist_ok=True)
    MANIFEST_PATH.write_text(
        json.dumps(manifest, indent=2, ensure_ascii=False), encoding="utf-8"
    )
    return manifest


def validate() -> list[str]:
    if not MANIFEST_PATH.exists():
        return [f"missing manifest: {MANIFEST_PATH.relative_to(ROOT)}"]
    manifest = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
    problems: list[str] = []
    minimum_frames = {
        "idle_video": 1,
        "walk_video": 24,
        "attack_01_video": 8,
        "attack_02_video": 10,
        "hit_video": 10,
        "death_01_video": 15,
        "death_02_video": 15,
    }
    for animation_name, animation in manifest["animations"].items():
        records = animation["frames"]
        if len(records) < minimum_frames[animation_name]:
            problems.append(f"{animation_name}: too few frames ({len(records)})")
        if animation["active_frame"] >= len(records):
            problems.append(f"{animation_name}: active frame outside sequence")
        for record in records:
            path = ROOT / record["file"]
            if not path.exists():
                problems.append(f"missing: {record['file']}")
                continue
            with Image.open(path) as image:
                if image.mode != "RGBA" or image.size != CANVAS:
                    problems.append(f"invalid output: {record['file']}")
                    continue
                bbox = image.getchannel("A").getbbox()
                if bbox is None:
                    problems.append(f"empty output: {record['file']}")
                elif animation_name not in {
                    "hit_video",
                    "death_01_video",
                    "death_02_video",
                } and (
                    bbox[0] < 2
                    or bbox[1] < 2
                    or bbox[2] > CANVAS[0] - 2
                    or bbox[3] > CANVAS[1] - 2
                ):
                    problems.append(f"clipped output: {record['file']} = {bbox}")
    for death_name in ("death_01_video", "death_02_video"):
        records = manifest["animations"][death_name]["frames"]
        start_box = records[0]["content_bbox"]
        end_box = records[-1]["content_bbox"]
        start_height = start_box[3] - start_box[1]
        end_height = end_box[3] - end_box[1]
        if end_height >= start_height * 0.72:
            problems.append(f"{death_name}: final fallen pose was not preserved")
    walk_heights = [
        record["content_bbox"][3] - record["content_bbox"][1]
        for record in manifest["animations"]["walk_video"]["frames"]
    ]
    if max(walk_heights) - min(walk_heights) > 2:
        problems.append("walk_video: frame height is not vertically stabilized")
    return problems


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--all", action="store_true")
    parser.add_argument("--validate", action="store_true")
    args = parser.parse_args()
    if not args.all and not args.validate:
        parser.error("choose --all or --validate")

    if args.all:
        manifest = prepare_all()
        for name, animation in manifest["animations"].items():
            print(
                f"{name}: {animation['source_frame_count']} source -> "
                f"{len(animation['frames'])} game frames @ "
                f"{animation['game_fps']} FPS"
            )
        print(
            f"canvas={manifest['canvas']} anchor={manifest['canvas_anchor']} "
            f"fit={manifest['fit_multiplier']}"
        )
    problems = validate()
    if problems:
        print("validation failed:")
        for problem in problems:
            print("  - " + problem)
        return 1
    print("validation passed: RGBA, aligned ground, safe canvas and death poses OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
