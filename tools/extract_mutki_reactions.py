"""Extract Mutki's supplied idle, hit and complete fall, using one fixed transform.

Run with the project Python dependencies (Pillow and NumPy). Source frame indices
are zero based at 24 FPS. No per-frame crop, recentering or size normalization.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
import numpy as np
from PIL import Image, ImageDraw

from extract_mutki_combo import CANVAS, GAME_SCALE, OUTPUT, PIVOT, ROOT, key

SOURCE = ROOT / "source_art/animations/mutki/mutki_hit_20260906.mp4"
REVIEW = ROOT / "artifacts/mutki_hit_v2"
RAW = REVIEW / "raw"
SOURCE_PIVOT = (929, 857)
# Match the 272-pixel standing body in the existing attack sheets.
SCALE = 777 * .35 / 642
CLIPS = {
    "idle_reactions_v2": list(range(0, 20, 2)),
    # Omit the long held recoil, retain the impact and recovery drawings.
    "hit_video_v2": [0, 64, 66, 68, 90, 92, 94, 96, 0],
    "death_video_v2": [0, *range(220, 260, 2)],
}


def normalized(index: int) -> Image.Image:
    with Image.open(RAW / f"{index + 1:04d}.png") as raw:
        sprite = key(raw)
    source_box = sprite.getbbox()
    assert source_box, (index, "empty source")
    offset = (round(PIVOT[0] - SOURCE_PIVOT[0] * SCALE),
              round(PIVOT[1] - SOURCE_PIVOT[1] * SCALE))
    # Check the transformed source BEFORE compositing, which would hide a crop.
    transformed_box = [source_box[i] * SCALE + offset[i % 2] for i in range(4)]
    assert all(10 < transformed_box[i] < CANVAS[i % 2] - 10 for i in range(4)), (index, transformed_box)
    sprite = sprite.resize((round(sprite.width * SCALE), round(sprite.height * SCALE)), Image.Resampling.LANCZOS)
    canvas = Image.new("RGBA", CANVAS)
    canvas.alpha_composite(sprite, offset)
    alpha = np.asarray(canvas.getchannel("A")).copy()
    alpha[alpha < 5] = 0
    canvas.putalpha(Image.fromarray(alpha))
    return canvas


def preview_frame(frame: Image.Image) -> Image.Image:
    background = Image.new("RGBA", CANVAS, "#829c8f")
    background.alpha_composite(frame)
    return background.convert("RGB")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--reuse-decoded", action="store_true")
    args = parser.parse_args()
    RAW.mkdir(parents=True, exist_ok=True)
    if not args.reuse_decoded:
        subprocess.run([str(ROOT / ".tools/ffmpeg.exe"), "-y", "-v", "error", "-i", str(SOURCE),
                        "-fps_mode", "passthrough", "-pix_fmt", "rgb24", str(RAW / "%04d.png")], check=True)
    assert len(list(RAW.glob("*.png"))) == 289, "Expected the supplied 24 FPS video"
    manifest = {
        "source": SOURCE.relative_to(ROOT).as_posix(),
        "source_sha256": hashlib.sha256(SOURCE.read_bytes()).hexdigest(),
        "source_fps": 24, "source_frame_count": 289, "game_fps": 12,
        "canvas": CANVAS, "canvas_pivot": PIVOT, "source_pivot": SOURCE_PIVOT,
        "extraction_scale": SCALE, "game_scale": GAME_SCALE, "animations": {},
    }
    sheet = Image.new("RGB", (6 * 384, 3 * 288), "#f7f5e9")
    draw = ImageDraw.Draw(sheet)
    for row, (animation, indices) in enumerate(CLIPS.items()):
        directory = OUTPUT / animation
        directory.mkdir(exist_ok=True)
        frames, records = [], []
        for n, source_index in enumerate(indices, 1):
            frame = normalized(source_index)
            destination = directory / f"mutki_{animation}_{n:03d}.png"
            frame.save(destination, optimize=True)
            frames.append(frame)
            records.append({"file": destination.relative_to(ROOT).as_posix(),
                            "source_frame": source_index, "alpha_bbox": frame.getbbox()})
        loop = frames + frames[-2:0:-1] if animation.startswith("idle") else frames
        preview = [preview_frame(frame) for frame in loop]
        preview[0].save(REVIEW / f"{animation}.gif", save_all=True, append_images=preview[1:],
                        duration=[83] * (len(preview) - 1) + [83 if animation.startswith("idle") else 800], loop=0)
        for column, n in enumerate(np.linspace(0, len(frames) - 1, 6).round().astype(int)):
            x, y = column * 384, row * 288
            sheet.paste(preview_frame(frames[n]).resize((384, 256)), (x, y + 32))
            draw.text((x + 8, y + 8), f"{animation} / source {indices[n]}", fill="black")
        manifest["animations"][animation] = {"frames": records, "duration_seconds": len(frames) / 12}
        print(animation, len(frames), "frames", flush=True)

    neutral_path = OUTPUT / "idle_reactions_v2/mutki_idle_reactions_v2_001.png"
    neutral_bytes = neutral_path.read_bytes()
    neutral_box = normalized(0).getbbox()
    # Both ends of every attack return to the same new neutral drawing.
    attacks_path = OUTPUT / "video_attacks_v2_manifest.json"
    attacks = json.loads(attacks_path.read_text(encoding="utf-8"))
    for attack in attacks["attacks"]:
        for record in (attack["frames"][0], attack["frames"][-1]):
            (ROOT / record["file"]).write_bytes(neutral_bytes)
            record.update(source_frame=0, source=manifest["source"], alpha_bbox=neutral_box)
    attacks["neutral_bookend_source"] = manifest["source"]
    attacks_path.write_text(json.dumps(attacks, ensure_ascii=False, indent=2), encoding="utf-8")
    (OUTPUT / "video_reactions_v2_manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
    sheet.save(REVIEW / "reactions_complete_contact.jpg", quality=94)
    normalized(258).save(REVIEW / "fallen_complete.png")
    print("REACTIONS_READY: fixed scale; all source bounds inside canvas; attack bookends aligned")


if __name__ == "__main__":
    main()
