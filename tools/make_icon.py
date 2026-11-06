"""Writes the launcher icon sources (SVG, 432 x 432) for THE WORTHY ONE's level 9999 'final sword' look.
Run:  python tools/make_icon.py   then   godot --headless --path . res://tools/rasterize_icons.tscn
Layers: background (full bleed), foreground (transparent; kept inside the Android safe circle), monochrome (one colour),
and the full icon (all layers, used for legacy and store icons)."""
import random, pathlib

SRC = pathlib.Path(__file__).resolve().parent.parent / "assets" / "branding" / "src"
SIZE = 432
C = SIZE / 2

def stars(seed, n):
    rnd = random.Random(seed)
    out = []
    for _ in range(n):
        x, y = rnd.uniform(0, SIZE), rnd.uniform(0, SIZE * 0.7)
        r = rnd.choice([0.8, 1.1, 1.4, 1.8])
        out.append(f'<circle cx="{x:.1f}" cy="{y:.1f}" r="{r}" fill="#fff4d6" opacity="{rnd.uniform(0.35, 0.9):.2f}"/>')
    return "\n".join(out)

BACKGROUND = f'''
  <defs>
    <linearGradient id="sky" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#140826"/><stop offset="0.55" stop-color="#3a1358"/><stop offset="1" stop-color="#1a0a22"/>
    </linearGradient>
    <radialGradient id="glow" cx="0.5" cy="0.5" r="0.5">
      <stop offset="0" stop-color="#ffb347" stop-opacity="0.85"/><stop offset="0.5" stop-color="#ff7a3c" stop-opacity="0.25"/><stop offset="1" stop-color="#ff7a3c" stop-opacity="0"/>
    </radialGradient>
  </defs>
  <rect width="{SIZE}" height="{SIZE}" fill="url(#sky)"/>
  <ellipse cx="{C}" cy="250" rx="230" ry="200" fill="url(#glow)"/>
  <path d="M0 220 Q 110 150 216 210 T 432 190 L432 232 Q 216 262 0 232 Z" fill="#7ee0c0" opacity="0.10"/>
  <path d="M0 250 Q 130 190 240 240 T 432 225" fill="none" stroke="#e7b8ff" stroke-width="10" opacity="0.10"/>
  {stars(9999, 70)}
'''

# The sword and the stump, drawn in the 432 space; FOREGROUND_TRANSFORM shrinks them into the adaptive safe circle.
ART = '''
  <circle cx="216" cy="172" r="118" fill="none" stroke="#ffcf6a" stroke-width="3" opacity="0.55"/>
  <circle cx="216" cy="172" r="132" fill="none" stroke="#ffcf6a" stroke-width="1.5" opacity="0.25"/>
  <ellipse cx="216" cy="300" rx="118" ry="30" fill="#f0a64a"/>
  <ellipse cx="216" cy="300" rx="92" ry="22" fill="none" stroke="#ffd98a" stroke-width="2" opacity="0.8"/>
  <ellipse cx="216" cy="300" rx="58" ry="13" fill="none" stroke="#ffd98a" stroke-width="2" opacity="0.7"/>
  <path d="M98 300 L98 362 Q216 404 334 362 L334 300 Z" fill="#1d0f2e"/>
  <path d="M120 330 L150 348 L140 366 M268 320 L300 340 L286 352 M200 350 L216 372 L232 350"
        fill="none" stroke="#ffb347" stroke-width="3" stroke-linecap="round" opacity="0.9"/>
  <ellipse cx="216" cy="362" rx="118" ry="30" fill="#2a1638"/>
  <polygon points="216,70 226,150 226,262 206,262 206,150" fill="#fff1c8"/>
  <polygon points="216,70 221,150 221,262 216,262" fill="#e2c27a" opacity="0.8"/>
  <rect x="214" y="104" width="4" height="150" fill="#b8925a" opacity="0.7"/>
  <rect x="146" y="256" width="140" height="16" rx="8" fill="#f5cd6f"/>
  <rect x="146" y="256" width="140" height="5" rx="2.5" fill="#fff3c4" opacity="0.8"/>
  <rect x="209" y="270" width="14" height="46" rx="4" fill="#4a2a10"/>
  <circle cx="216" cy="324" r="11" fill="#f5cd6f"/>
  <circle cx="216" cy="172" r="54" fill="#ffb347" opacity="0.10"/>
'''

FOREGROUND_TRANSFORM = f"translate({C} {C}) scale(0.7) translate({-C} {-C})"

def svg(body, extra_root=""):
    return f'<svg xmlns="http://www.w3.org/2000/svg" width="{SIZE}" height="{SIZE}" viewBox="0 0 {SIZE} {SIZE}"{extra_root}>{body}</svg>\n'

def write(name, text):
    (SRC / name).write_text(text, encoding="utf-8", newline="\n")
    print("wrote", name)

SRC.mkdir(parents=True, exist_ok=True)
write("icon_full.svg", svg(BACKGROUND + f'<g transform="{FOREGROUND_TRANSFORM}">{ART}</g>'))
write("adaptive_background.svg", svg(BACKGROUND))
write("adaptive_foreground.svg", svg(f'<g transform="{FOREGROUND_TRANSFORM}">{ART}</g>'))
mono = ART.replace("#ffcf6a", "#ffffff").replace("#fff1c8", "#ffffff")
write("adaptive_monochrome.svg", svg(f'<g transform="{FOREGROUND_TRANSFORM}" fill="#ffffff">{mono}</g>'))
