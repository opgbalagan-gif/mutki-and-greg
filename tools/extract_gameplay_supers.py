"""Key fixed-camera gameplay clips and pack frames without changing their pivot.

End-keyframe geometry comes from render_super_idle.gd, which renders the real
idle frame in Godot. The same inverse transform puts it back on the arena.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import subprocess
from pathlib import Path
import numpy as np
from PIL import Image, ImageFilter, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'source_art/supers_20260925/gameplay'
REVIEW = ROOT / 'artifacts/arena_supers'
CANVAS = (1024, 576)
PIVOT = (512, 862 * 576 / 941)
GAME_SCALE = 1672 / (2560 * 2.3525 * .4)


def key(image: Image.Image) -> Image.Image:
    rgb = np.asarray(image.convert('RGB'), dtype=np.float32)
    r, g, b = rgb[:, :, 0], rgb[:, :, 1], rgb[:, :, 2]
    ratio = (g - np.maximum(r, b)) / np.maximum(g, 1)
    alpha = np.clip((.52 - ratio) / .40, 0, 1)
    alpha[(np.max(rgb, axis=2) < 80) & (ratio < .35)] = 1
    alpha[alpha < .07] = 0
    background = np.median(rgb[:60].reshape(-1, 3), axis=0)
    recovered = np.clip((rgb - (1-alpha[:, :, None])*background) / np.maximum(alpha[:, :, None], .07), 0, 255)
    # Despill only transition pixels; retain the teal cap's actual color.
    edge = alpha < .98
    recovered[:, :, 1][edge] = np.minimum(recovered[:, :, 1][edge], np.maximum(recovered[:, :, 0][edge], recovered[:, :, 2][edge]))
    result = Image.fromarray(recovered.astype('uint8')).convert('RGBA')
    result.putalpha(Image.fromarray((alpha*255).astype('uint8')).filter(ImageFilter.GaussianBlur(.3)))
    return result


def pack(image: Image.Image, path: Path) -> int:
    bbox = image.getchannel('A').getbbox()
    assert bbox
    x, y = max(0, bbox[0]-2), max(0, bbox[1]-2)
    right, bottom = min(image.width, bbox[2]+2), min(image.height, bbox[3]+2)
    packed = image.crop((x, y, right, bottom))
    dest = ROOT/'assets/packed_sprites'/path.relative_to(ROOT/'assets')
    dest.parent.mkdir(parents=True, exist_ok=True)
    packed.save(dest, optimize=True)
    w, h = packed.size
    dest.with_suffix('.tres').write_text(
        '[gd_resource type="AtlasTexture" load_steps=2 format=3]\n\n'
        f'[ext_resource type="Texture2D" path="res://{dest.relative_to(ROOT).as_posix()}" id="1"]\n\n'
        '[resource]\natlas = ExtResource("1")\n'
        f'region = Rect2(0, 0, {w}, {h})\n'
        f'margin = Rect2({x}, {y}, {image.width-w}, {image.height-h})\nfilter_clip = true\n', encoding='utf-8')
    restored = Image.new('RGBA', image.size)
    restored.paste(packed, (x, y))
    a, b = np.asarray(image), np.asarray(restored)
    assert np.array_equal(a[:, :, 3], b[:, :, 3])
    assert np.array_equal(a[a[:, :, 3] > 0], b[b[:, :, 3] > 0])
    return w*h*4


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('hero', choices=['mutki', 'greg'])
    parser.add_argument('--version', default='v3')
    parser.add_argument('--end', type=int, default=58)
    parser.add_argument('--review-only', action='store_true')
    args = parser.parse_args()
    hero = args.hero
    source = SOURCE/f'{hero}-gameplay-h3-{args.version}.mp4'
    raw = REVIEW/f'{hero}-{args.version}-raw'
    raw.mkdir(parents=True, exist_ok=True)
    subprocess.run([str(ROOT/'.tools/ffmpeg.exe'), '-y', '-v', 'error', '-i', str(source), '-vf', 'fps=12', str(raw/'%03d.png')], check=True)
    files = sorted(raw.glob('*.png'))
    sheet = Image.new('RGB', (6*280, ((len(files)+5)//6)*180), '#eeeeee')
    draw = ImageDraw.Draw(sheet)
    for i, file in enumerate(files):
        thumb = Image.open(file).resize((280, 157))
        x, y = i%6*280, i//6*180
        sheet.paste(thumb, (x, y+23))
        draw.text((x+4, y+4), f'{i}: {i/12:.3f}s', fill='black')
    sheet.save(REVIEW/f'{hero}-{args.version}-timeline.jpg')
    if args.review_only:
        return
    out = ROOT/f'assets/characters/{hero}/super_gameplay'
    out.mkdir(parents=True, exist_ok=True)
    frames, records, texture_bytes = [], [], 0
    indices = list(range(min(args.end, len(files))))
    if hero == 'greg':
        indices = [0, 1] + list(range(12, min(args.end, len(files))))
    for index in indices:
        file = files[index]
        image = key(Image.open(file)).resize(CANVAS, Image.Resampling.LANCZOS)
        a = np.asarray(image.getchannel('A')).copy()
        a[a < 5] = 0
        image.putalpha(Image.fromarray(a))
        frames.append(image)
    # The exact gameplay idle is the handoff frame, matching _play_idle(0).
    end_idle = key(Image.open(SOURCE/f'{hero}-idle-end-green.png')).resize(CANVAS, Image.Resampling.LANCZOS)
    frames.append(end_idle)
    for i, image in enumerate(frames):
        path = out/f'{hero}_super_{i:03d}.png'
        image.save(path, optimize=True)
        texture_bytes += pack(image, path)
        records.append({'file':path.relative_to(ROOT).as_posix(), 'alpha_bbox':image.getchannel('A').getbbox(), 'source_frame_12fps':indices[i] if i<len(indices) else None})
    assert texture_bytes < 80*1048576, texture_bytes
    manifest = {'hero':hero, 'source':source.relative_to(ROOT).as_posix(), 'sha256':hashlib.sha256(source.read_bytes()).hexdigest(), 'canvas':CANVAS, 'pivot':PIVOT, 'game_scale':GAME_SCALE, 'fps':18, 'end_idle':'actual gameplay idle frame 0', 'packed_rgba_bytes':texture_bytes, 'frames':records}
    (out.parent/'super_gameplay_manifest.json').write_text(json.dumps(manifest, indent=2), encoding='utf-8')
    preview=[]
    for frame in frames:
        canvas=Image.new('RGBA', CANVAS, '#515968')
        canvas.alpha_composite(frame)
        preview.append(canvas.convert('RGB').resize((720,405)))
    preview[0].save(REVIEW/f'{hero}-keyed.gif', save_all=True, append_images=preview[1:], duration=56, loop=0)
    print(hero, len(frames), 'frames, packed MiB', round(texture_bytes/1048576,2), 'scale', GAME_SCALE, 'pivot', PIVOT)


if __name__ == '__main__':
    main()
