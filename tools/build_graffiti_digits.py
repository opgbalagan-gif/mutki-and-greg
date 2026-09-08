"""Build original vector score glyphs. No system fonts or raster tracing used."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets/ui/graffiti_digits"

# Hand-authored outlines, with counters retained by even-odd filling.
GLYPHS = {
    "0": "M22 6 Q60 -3 88 18 L102 95 Q85 136 48 139 L4 121 Q-10 64 22 6 Z M40 35 L28 94 L49 106 L72 87 L76 37 Z",
    "1": "M15 28 L50 3 L78 9 L70 100 L95 105 L91 132 L6 136 L9 108 L33 104 L38 47 L14 60 Z",
    "2": "M5 15 Q50 -6 87 14 Q113 37 94 65 L39 102 L97 98 L94 135 L1 135 L4 99 L60 53 Q71 43 61 35 Q43 29 9 53 Z",
    "3": "M8 12 L73 3 Q106 15 98 52 L75 69 Q108 74 101 106 Q90 141 48 140 L3 128 L9 97 Q45 116 66 100 Q74 87 55 84 L28 85 L32 59 L54 58 Q74 56 69 40 Q57 29 8 45 Z",
    "4": "M64 3 L95 9 L83 76 L102 78 L98 105 L77 105 L74 136 L43 133 L48 105 L-1 103 L2 74 L34 1 L60 9 L33 76 L53 76 Z",
    "5": "M9 7 L96 7 L90 38 L36 35 L31 57 Q98 45 98 93 Q100 145 41 139 L2 127 L9 97 Q34 111 57 108 Q73 103 65 88 Q57 76 2 85 Z",
    "6": "M89 5 L83 36 Q46 20 32 62 Q55 47 78 58 Q107 70 98 110 Q80 145 44 138 Q4 138 0 100 Q-3 28 48 7 Q70 0 89 5 Z M38 85 Q29 105 48 113 Q69 113 72 95 Q67 76 38 85 Z",
    "7": "M4 5 L104 10 L98 39 L69 71 L55 139 L16 133 L38 66 L66 35 L1 38 Z",
    "8": "M46 2 Q99 -2 99 35 Q100 52 79 67 Q106 80 102 107 Q94 143 43 140 Q-6 137 -1 106 Q-4 84 22 65 Q-2 48 6 25 Q17 4 46 2 Z M39 27 Q23 44 45 52 Q71 48 69 32 Q53 20 39 27 Z M39 85 Q20 100 39 112 Q69 119 74 98 Q64 80 39 85 Z",
    "9": "M11 130 L16 102 Q48 122 69 79 Q44 93 18 77 Q-3 64 4 33 Q15 -3 57 4 Q106 5 101 62 Q95 124 63 138 Q36 149 11 130 Z M38 33 Q23 48 42 62 Q65 68 72 45 Q62 24 38 33 Z",
    "plus": "M38 34 L63 30 L60 65 L92 62 L90 89 L59 88 L54 121 L29 118 L32 87 L0 90 L4 64 L35 65 Z",
    "multiply": "M15 30 L46 60 L78 30 L97 50 L64 78 L91 106 L71 124 L42 94 L9 121 L-6 101 L25 74 L-2 46 Z",
    "comma": "M39 102 L65 100 L61 128 L38 147 L26 137 L40 123 L32 121 Z",
    "minus": "M7 68 L91 64 L87 92 L3 96 Z",
}
HIGHLIGHTS = {
    "0": "M26 14 Q58 3 82 23", "1": "M24 29 L53 12 L70 16",
    "2": "M14 20 Q53 4 82 21", "3": "M17 18 L70 11 Q85 16 88 28",
    "4": "M39 12 L48 15 M72 12 L86 16", "5": "M17 16 L85 16",
    "6": "M19 56 Q39 10 79 13", "7": "M13 14 L93 18",
    "8": "M17 30 Q33 7 60 10",
    "9": "M15 33 Q29 6 65 15", "plus": "M44 41 L54 39",
    "multiply": "M16 42 L39 66", "comma": "M42 110 L56 108",
    "minus": "M15 75 L80 72",
}

def drawing(name: str, prefix: str) -> str:
    path = GLYPHS[name]
    return f'''<defs><linearGradient id="{prefix}" x1="0" y1="0" x2="0" y2="140" gradientUnits="userSpaceOnUse">
<stop offset="0" stop-color="#83bc42"/><stop offset=".38" stop-color="#bad62f"/>
<stop offset=".77" stop-color="#f7e737"/><stop offset="1" stop-color="#ffe337"/>
</linearGradient></defs>
<g transform="matrix(1 0 -.12 1 17 0)" fill-rule="evenodd" stroke-linejoin="round" stroke-linecap="round">
<path d="{path}" transform="translate(7 10)" fill="#090a06" stroke="#fffef2" stroke-width="13"/>
<path d="{path}" fill="#090a06" stroke="#fffef2" stroke-width="13"/>
<path d="{path}" transform="translate(7 10)" fill="#090a06" stroke="#090a06" stroke-width="7"/>
<path d="{path}" fill="url(#{prefix})" stroke="#090a06" stroke-width="7"/>
<path d="{HIGHLIGHTS[name]}" fill="none" stroke="#fffeda" stroke-width="2.8"/>
</g>'''

def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    for name in GLYPHS:
        svg = '<svg xmlns="http://www.w3.org/2000/svg" width="312" height="348" viewBox="-14 -14 156 174">' + drawing(name, "fill") + '</svg>\n'
        (OUT / f"{name}.svg").write_text(svg, encoding="utf-8")
    preview = ROOT / "artifacts/graffiti_score"
    preview.mkdir(parents=True, exist_ok=True)
    sheet = '<svg xmlns="http://www.w3.org/2000/svg" width="1480" height="460" viewBox="0 0 1480 460"><rect width="1480" height="460" fill="#11180e"/>'
    for index in range(10):
        sheet += f'<g transform="translate({25 + (index % 5) * 290} {30 + (index // 5) * 220})">' + drawing(str(index), f"fill{index}") + '</g>'
    sheet += '</svg>\n'
    (preview / "digits.svg").write_text(sheet, encoding="utf-8")
    print(f"GRAFFITI_DIGITS_READY: {len(GLYPHS)} original SVG glyphs")

if __name__ == "__main__":
    main()
