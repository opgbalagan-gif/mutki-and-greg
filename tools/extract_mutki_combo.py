"""Curated seven attacks from the user's 2026-09-06 Mutki video.

All frame indices are zero based at 24 FPS. Export every second frame at 12 FPS,
keeping clip duration, one common scale and a fixed floor/pivot. The fifth
source attack faces left, so its whole clip is mirrored about the same pivot.
"""
from __future__ import annotations
import argparse, hashlib, json, subprocess
from pathlib import Path
import numpy as np
from PIL import Image, ImageFilter, ImageDraw, ImageOps

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT/'source_art/animations/mutki/mutki_attacks_20260906.mp4'
RAW = ROOT/'artifacts/mutki_royalty_attacks/raw'
OUTPUT = ROOT/'assets/characters/mutki'
REVIEW = ROOT/'artifacts/mutki_royalty_attacks'
FFMPEG = ROOT/'.tools/ffmpeg.exe'
# name, source start inclusive, end exclusive, impact, mirrored, damage
ATTACKS = [
    ('jab', 0, 18, 6, False, 34),
    ('cross', 24, 42, 30, False, 40),
    ('hook', 48, 70, 58, False, 48),
    ('kick', 80, 112, 92, False, 52),
    ('reverse_hook', 128, 156, 138, True, 48),
    ('uppercut', 174, 210, 190, False, 52),
    ('spinning_backfist', 228, 280, 260, False, 60),
]
CANVAS = (768, 512)
PIVOT = (384, 460)
SOURCE_PIVOT = (878, 950)
EXTRACTION_SCALE = .35
REFERENCE_HEIGHT = 777
GAME_SCALE = 290.0/(REFERENCE_HEIGHT*EXTRACTION_SCALE)


def key(image: Image.Image) -> Image.Image:
    rgb = np.asarray(image.convert('RGB'), dtype=np.float32)
    r,g,b = rgb[:,:,0],rgb[:,:,1],rgb[:,:,2]
    ratio = (g-np.maximum(r,b))/np.maximum(g,1)
    alpha = np.clip((.52-ratio)/.40,0,1)
    alpha[(np.max(rgb,axis=2)<80)&(ratio<.35)] = 1
    alpha[alpha<.07] = 0
    # The encoder has a faint vertical seam at the source image edges.
    alpha[:,:16] = 0; alpha[:,-16:] = 0
    background = np.median(rgb[:100].reshape(-1,3),axis=0)
    recovered = np.clip((rgb-(1-alpha[:,:,None])*background)/np.maximum(alpha[:,:,None],.07),0,255)
    recovered[:,:,1] = np.minimum(recovered[:,:,1],np.maximum(recovered[:,:,0],recovered[:,:,2]))
    a = Image.fromarray((alpha*255).astype('uint8')).filter(ImageFilter.GaussianBlur(.35))
    result = Image.fromarray(recovered.astype('uint8')).convert('RGBA')
    result.putalpha(a)
    return result


def normalized(source_index: int, mirror: bool=False) -> Image.Image:
    raw = Image.open(RAW/f'{source_index+1:04d}.png')
    keyed = key(raw)
    anchor_x = SOURCE_PIVOT[0]
    if mirror:
        keyed = ImageOps.mirror(keyed)
        anchor_x = raw.width - anchor_x
    resized = keyed.resize((round(raw.width*EXTRACTION_SCALE),round(raw.height*EXTRACTION_SCALE)),Image.Resampling.LANCZOS)
    canvas = Image.new('RGBA',CANVAS,(0,0,0,0))
    canvas.alpha_composite(resized,(round(PIVOT[0]-anchor_x*EXTRACTION_SCALE),round(PIVOT[1]-SOURCE_PIVOT[1]*EXTRACTION_SCALE)))
    alpha = np.asarray(canvas.getchannel('A')).copy()
    alpha[alpha<5] = 0
    canvas.putalpha(Image.fromarray(alpha))
    return canvas


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--reuse-decoded',action='store_true')
    args=parser.parse_args()
    RAW.mkdir(parents=True,exist_ok=True)
    if not args.reuse_decoded:
        subprocess.run([str(FFMPEG),'-y','-v','error','-i',str(SOURCE),'-fps_mode','passthrough',str(RAW/'%04d.png')],check=True)
    assert len(list(RAW.glob('*.png')))==289,'Expected the supplied 12-second, 24 FPS source'
    reaction_idle=OUTPUT/'idle_reactions_v2/mutki_idle_reactions_v2_001.png'
    neutral=Image.open(reaction_idle).convert('RGBA') if reaction_idle.exists() else normalized(40)
    idle_dir=OUTPUT/'idle_video_v2';idle_dir.mkdir(exist_ok=True)
    for n,frame in enumerate([40,42,44,46,48],1):
        normalized(frame).save(idle_dir/f'mutki_idle_video_v2_{n:03}.png')
    clips=ROOT/'source_art/animations/mutki/clips_v2';clips.mkdir(exist_ok=True)
    manifest={'source':SOURCE.relative_to(ROOT).as_posix(),'source_sha256':hashlib.sha256(SOURCE.read_bytes()).hexdigest(),
              'source_fps':24,'source_frame_count':289,'game_fps':12,'canvas':CANVAS,'source_pivot':SOURCE_PIVOT,
              'canvas_pivot':PIVOT,'extraction_scale':EXTRACTION_SCALE,'game_scale':GAME_SCALE,
              'sprite_position':[0,-(PIVOT[1]-CANVAS[1]/2)*GAME_SCALE],
              'idle_source_frames':[40,42,44,46,48], 'attacks':[]}
    sheet=Image.new('RGB',(7*270,7*215),'#f7f5e9');draw=ImageDraw.Draw(sheet)
    for i,(name,start,end,impact,mirror,damage) in enumerate(ATTACKS,1):
        animation=f'attack_v2_{i:02d}';destination=OUTPUT/animation;destination.mkdir(exist_ok=True)
        frames=[];records=[]
        for n,source_index in enumerate(range(start,end,2)):
            # Shared neutral bookends eliminate the video's slightly different reset poses.
            endpoint=n==0 or source_index==end-2
            im=neutral.copy() if endpoint else normalized(source_index,mirror)
            file=destination/f'mutki_{animation}_{n+1:03}.png';im.save(file,optimize=True)
            box=im.getchannel('A').getbbox()
            assert box and box[0]>8 and box[1]>8 and box[2]<CANVAS[0]-8 and box[3]<CANVAS[1]-8,(animation,n,box)
            frames.append(im)
            record={'file':file.relative_to(ROOT).as_posix(),'source_frame':40 if endpoint else source_index,'clip_frame':source_index,'neutral_bookend':endpoint,'alpha_bbox':box}
            if endpoint and reaction_idle.exists():
                record.update(source_frame=0,source='source_art/animations/mutki/mutki_hit_20260906.mp4')
            records.append(record)
        active=(impact-start)//2
        clip=clips/f'{i:02d}_{name}.mp4'
        subprocess.run([str(FFMPEG),'-y','-v','error','-i',str(SOURCE),'-vf',f'trim=start_frame={start}:end_frame={end},setpts=PTS-STARTPTS',
                        '-af',f'atrim=start={start/24}:end={end/24},asetpts=PTS-STARTPTS','-c:v','libx264','-preset','fast','-crf','18','-c:a','aac','-movflags','+faststart',str(clip)],check=True)
        manifest['attacks'].append({'animation':animation,'label':name,'source_range':[start,end],'source_impact':impact,'active_frame':active,
                                    'active_end_frame':active+1,'mirrored_to_face_right':mirror,'damage':damage,'duration_seconds':(end-start)/24,'clip':clip.relative_to(ROOT).as_posix(),'frames':records})
        picks=np.linspace(0,len(frames)-1,7).round().astype(int)
        for col,n in enumerate(picks):
            thumb=Image.new('RGBA',CANVAS,'#829c8f');thumb.alpha_composite(frames[n]);thumb=thumb.convert('RGB').resize((270,180))
            x,y=col*270,(i-1)*215;sheet.paste(thumb,(x,y+30));draw.text((x+5,y+7),f'{i} {name} / {n}'+(' HIT' if n==active else ''),fill='black')
        preview=[]
        for im in frames:
            bg=Image.new('RGBA',CANVAS,'#829c8f');bg.alpha_composite(im);preview.append(bg.convert('RGB'))
        preview[0].save(REVIEW/f'{animation}.gif',save_all=True,append_images=preview[1:],duration=83,loop=0)
        print(animation,len(frames),'frames, hit',active,'duration',(end-start)/24,flush=True)
    (OUTPUT/'video_attacks_v2_manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
    sheet.save(REVIEW/'seven_attacks_contact.jpg')
    print('GAME_SCALE',GAME_SCALE,'SPRITE_POSITION',manifest['sprite_position'])

if __name__=='__main__':
    main()
