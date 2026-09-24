"""Copy a verified Godot Web export into docs while preserving the custom loader."""
from __future__ import annotations

import hashlib
import json
import re
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
EXPORT = ROOT / "build" / "web"
DOCS = ROOT / "docs"


def copy_if_changed(source: Path, destination: Path) -> None:
    # Browsers can keep an identical WASM file memory-mapped on Windows.
    if destination.exists() and source.stat().st_size == destination.stat().st_size:
        if hashlib.sha256(source.read_bytes()).digest() == hashlib.sha256(destination.read_bytes()).digest():
            return
    shutil.copy2(source, destination)


def main() -> None:
    config_pattern = r"const GODOT_CONFIG = (\{[^\n]+\});"
    generated_html = (EXPORT / "index.html").read_text(encoding="utf-8")
    generated_title = re.search(r"<title>.*?</title>", generated_html)[0]
    config = json.loads(re.search(config_pattern, generated_html)[1])
    shell = (DOCS / "index.html").read_text(encoding="utf-8")
    # Keep both fresh exports and the custom GitHub Pages shell on the same transport.
    transport = ROOT / "web" / "net"
    for source in transport.rglob("*"):
        if source.is_file():
            destination = DOCS / "net" / source.relative_to(transport)
            destination.parent.mkdir(parents=True, exist_ok=True)
            copy_if_changed(source, destination)
            export_destination = EXPORT / "net" / source.relative_to(transport)
            export_destination.parent.mkdir(parents=True, exist_ok=True)
            copy_if_changed(source, export_destination)
    bridge_version = hashlib.sha256((transport / "coop.js").read_bytes()).hexdigest()[:12]
    scripts = '<script src="net/vendor/peerjs-1.5.5.min.js"></script>\n<script src="net/coop.js?v=' + bridge_version + '"></script>\n'
    if 'src="net/coop.js' not in shell:
        shell = shell.replace('</head>', scripts + '</head>')
    shell = re.sub(r'src="net/coop\.js(?:\?[^"\s]*)?"', 'src="net/coop.js?v=' + bridge_version + '"', shell)
    generated_html = re.sub(r'src="net/coop\.js(?:\?[^"\s]*)?"', 'src="net/coop.js?v=' + bridge_version + '"', generated_html)
    (EXPORT / "index.html").write_text(generated_html, encoding="utf-8")
    shell = re.sub(r"<title>.*?</title>", lambda _match: generated_title, shell)
    old_config = json.loads(re.search(config_pattern, shell)[1])
    pack = EXPORT / "index.pck"
    # GitHub stores the 8 MiB parts below, never this virtual combined PCK.
    pack_name = "index-" + hashlib.sha256(pack.read_bytes()).hexdigest()[:12] + ".pck"
    config["mainPack"] = pack_name
    config["fileSizes"].pop("index.pck", None)
    config["fileSizes"][pack_name] = pack.stat().st_size
    for source in EXPORT.iterdir():
        if source.is_file() and source.suffix in {".js", ".wasm", ".png"}:
            copy_if_changed(source, DOCS / source.name)
    # Keep API uploads small while streaming the exact exported bytes to Godot.
    parts_directory = DOCS / "packs"
    parts_directory.mkdir(exist_ok=True)
    parts = []
    combined_hash = hashlib.sha256()
    with pack.open("rb") as source:
        while data := source.read(8 * 1024 * 1024):
            part_name = f"{pack_name}.{len(parts):02d}.bin"
            (parts_directory / part_name).write_bytes(data)
            parts.append({"url": "packs/" + part_name, "size": len(data)})
            combined_hash.update(data)
    assert combined_hash.hexdigest()[:12] == pack_name[6:18]
    manifest = {"name": pack_name, "size": pack.stat().st_size, "parts": parts}
    loader_version = hashlib.sha256((transport / "pack-loader.js").read_bytes()).hexdigest()[:12]
    block = '<!-- split-pack:start -->\n<script>window.GREG_MUTKI_PACK = ' + json.dumps(manifest, separators=(",", ":")) + ';</script>\n<script src="net/pack-loader.js?v=' + loader_version + '"></script>\n<!-- split-pack:end -->'
    if '<!-- split-pack:start -->' in shell:
        shell = re.sub(r'<!-- split-pack:start -->[\s\S]*?<!-- split-pack:end -->', lambda _: block, shell)
    else:
        shell = shell.replace('</head>', block + '\n</head>')
    (DOCS / pack_name).unlink(missing_ok=True)
    loading_paths = [f"splash/loading_{index:02d}.jpg" for index in range(1, 7)]
    for path in loading_paths:
        if not (DOCS / path).is_file():
            raise FileNotFoundError(f"Missing loading screen: {path}")
    shell = re.sub(config_pattern, "const GODOT_CONFIG = " + json.dumps(config, separators=(",", ":")) + ";", shell)
    shell = re.sub(r"const startupArtPaths = \[[\s\S]*?\];", "const startupArtPaths = " + json.dumps(loading_paths) + ";", shell)
    rotation = """startupArtTimer = window.setInterval(() => {
        startupArtIndex = (startupArtIndex + 1) % startupArtPaths.length;
        showStartupArt(startupArtPaths[startupArtIndex]);
    }, 2400);"""
    rotation_pattern = r"startupArtTimer = window.setInterval\([\s\S]*?\}, 2400\);|// One urban title illustration shared with the game menu\.|// One approved illustration; no rotating alternate character designs\."
    shell, rotation_count = re.subn(rotation_pattern, lambda _match: rotation, shell)
    if rotation_count != 1:
        raise ValueError("Expected one startup slideshow block")
    shell = shell.replace('src="splash/urban_title.png"', 'src="splash/loading_01.jpg"')
    shell = shell.replace('src="splash/characters_canonical.png"', 'src="splash/loading_01.jpg"')
    shell = shell.replace('<html lang="en">', '<html lang="ru">')
    shell = re.sub(r'(<meta name="theme-color" content=")#[a-fA-F0-9]+', r'\g<1>#080e15', shell)
    style = """
/* Restored loading screens: dark surround with a cyan progress bar. */
body, #status { background: #080e15; color: #edf3f5; }
#status-splash::after { display: none; }
#startup-art-image { object-fit: contain; filter: none; box-shadow: none; }
#status-percent, #status-notice { color: #edf3f5; text-shadow: 0 2px 5px #080e15; }
#status-progress { accent-color: #68edff; }
#status-progress::-webkit-progress-value { background: #68edff; }
#status-progress::-moz-progress-bar { background: #68edff; }
"""
    palette_pattern = r"/\* (?:Canonical character reference:|Urban court palette:|Restored loading screens:)[\s\S]*?(?=</style>)"
    if re.search(palette_pattern, shell):
        shell = re.sub(palette_pattern, lambda _match: style.strip() + "\n", shell)
    else:
        shell = shell.replace("</style>", style + "</style>", 1)
    shell = "\n".join(line.rstrip() for line in shell.splitlines()) + "\n"
    (DOCS / "index.html").write_text(shell, encoding="utf-8")
    old_name = old_config.get("mainPack", "")
    if old_name != pack_name and re.fullmatch(r"index-[a-f0-9]+\.pck", old_name):
        (DOCS / old_name).unlink(missing_ok=True)
        for old_part in parts_directory.glob(old_name + ".*.bin"):
            old_part.unlink()
    print("WEB_BUILD_READY:", pack_name, pack.stat().st_size)


if __name__ == "__main__":
    main()
