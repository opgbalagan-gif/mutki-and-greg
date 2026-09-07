"""Losslessly remove transparent GPU padding while retaining each frame's floor pivot.

Godot AtlasTexture margins reconstruct the original logical canvas. Source PNGs
remain editable; exports load only the smaller images and their atlas resources.
"""
from __future__ import annotations

import json
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "assets"
OUTPUT = ASSETS / "packed_sprites"


def main() -> None:
    directories = list((ASSETS / "characters/greg").iterdir())
    mutki = ASSETS / "characters/mutki"
    directories += [mutki / name for name in [
        "assist_super", "idle_reactions_v2", "hit_video_v2", "death_video_v2",
        *[f"attack_v2_{number:02d}" for number in range(1, 8)],
    ]]
    directories += list((ASSETS / "enemies/enemy_01_thug").glob("*_video"))
    original_bytes = packed_bytes = 0
    records = []
    for directory in directories:
        if not directory.is_dir():
            continue
        for source in sorted(directory.glob("*.png")):
            import_file = source.with_suffix(".png.import")
            assert "process/size_limit=0" in import_file.read_text(), source
            with Image.open(source) as image:
                original = image.convert("RGBA")
            box = original.getchannel("A").getbbox()
            assert box is not None, source
            left, top = max(0, box[0] - 2), max(0, box[1] - 2)
            right, bottom = min(original.width, box[2] + 2), min(original.height, box[3] + 2)
            packed = original.crop((left, top, right, bottom))
            destination = OUTPUT / source.relative_to(ASSETS)
            destination.parent.mkdir(parents=True, exist_ok=True)
            packed.save(destination, optimize=True)
            width, height = packed.size
            atlas_path = "res://" + destination.relative_to(ROOT).as_posix()
            destination.with_suffix(".tres").write_text(
                '[gd_resource type="AtlasTexture" load_steps=2 format=3]\n\n'
                f'[ext_resource type="Texture2D" path="{atlas_path}" id="1"]\n\n'
                '[resource]\natlas = ExtResource("1")\n'
                f'region = Rect2(0, 0, {width}, {height})\n'
                f'margin = Rect2({left}, {top}, {original.width - width}, {original.height - height})\n'
                'filter_clip = true\n', encoding="utf-8")
            # Verify every visible pixel and its original position, without resampling.
            restored = Image.new("RGBA", original.size)
            restored.paste(packed, (left, top))
            before, after = np.asarray(original), np.asarray(restored)
            assert np.array_equal(before[:, :, 3], after[:, :, 3]), source
            assert np.array_equal(before[before[:, :, 3] > 0], after[before[:, :, 3] > 0]), source
            original_bytes += original.width * original.height * 4
            packed_bytes += width * height * 4
            records.append({"source": source.relative_to(ROOT).as_posix(),
                            "texture": destination.with_suffix(".tres").relative_to(ROOT).as_posix(),
                            "canvas": original.size, "crop": [left, top, right, bottom]})
    summary = {"frames": len(records), "original_rgba_bytes": original_bytes,
               "packed_rgba_bytes": packed_bytes, "records": records}
    (OUTPUT / "manifest.json").write_text(json.dumps(summary, indent=2), encoding="utf-8")
    print(f"PACKED_SPRITES_PASS: {len(records)} lossless frames; "
          f"RGBA {original_bytes / 1048576:.1f} -> {packed_bytes / 1048576:.1f} MiB")


if __name__ == "__main__":
    main()
