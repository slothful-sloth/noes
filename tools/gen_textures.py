#!/usr/bin/env python3
"""Generate every texture: tile theme atlases, table faces, table border wood, scoreboard.

Atlas layout matches tools/gen_tiles.py: 4 x 8 cells of 1024 x 512 px (4096 x 4096 total);
cells 0..27 = tile faces in rules.allTiles() order, 28 = back, 29 = body.
One atlas per (face style, back) combination: assets/textures/tiles/<face>_<back>.jpg
"""
from __future__ import annotations

import io
import math
import sys
from pathlib import Path

import cairosvg
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

sys.path.insert(0, str(Path(__file__).resolve().parent))
import gen_tiles as G  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "assets" / "src"
DL = SRC / "downloads"
OUT = ROOT / "assets" / "textures"

CELL_W, CELL_H = 1024, 512
PX = CELL_W / G.L                        # pixels per world unit on a face cell
ATLAS = (CELL_W * G.ATLAS_COLS, CELL_H * G.ATLAS_ROWS)
SS = 2                                   # supersampling for vector drawing

rng = np.random.default_rng(7)


# --- noise helpers -----------------------------------------------------------------

def value_noise(w: int, h: int, scale: float, octaves: int = 4, seed: int = 0) -> np.ndarray:
    """Smooth multi-octave value noise in [0, 1], shape (h, w)."""
    r = np.random.default_rng(seed)
    out = np.zeros((h, w), np.float32)
    amp, total = 1.0, 0.0
    for o in range(octaves):
        cells = max(2, int(scale * (2 ** o)))
        grid = r.random((cells + 1, cells + 1)).astype(np.float32)
        img = Image.fromarray((grid * 255).astype(np.uint8)).resize((w, h), Image.BICUBIC)
        out += amp * (np.asarray(img, np.float32) / 255.0)
        total += amp
        amp *= 0.5
    return out / total


def to_img(arr: np.ndarray) -> Image.Image:
    return Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8))


def tint(noise: np.ndarray, c0, c1) -> np.ndarray:
    c0, c1 = np.array(c0, np.float32), np.array(c1, np.float32)
    return c0 + (c1 - c0) * noise[..., None]


def svg_to_img(svg: str, w: int, h: int) -> Image.Image:
    png = cairosvg.svg2png(bytestring=svg.encode(), output_width=w, output_height=h)
    return Image.open(io.BytesIO(png)).convert("RGBA")


# --- flags at 2:1 (drawn natively so stars and suns keep their shape) ---------------------

def star_points(cx, cy, r_out, r_in, n=5, rot=-90):
    pts = []
    for i in range(2 * n):
        r = r_out if i % 2 == 0 else r_in
        a = math.radians(rot + i * 180 / n)
        pts.append(f"{cx + r * math.cos(a):.2f},{cy + r * math.sin(a):.2f}")
    return " ".join(pts)


def flag_pr(w, h):
    stripes = "".join(
        f'<rect x="0" y="{i * h / 5}" width="{w}" height="{h / 5 + 0.5}" fill="{"#ED0000" if i % 2 == 0 else "#FFFFFF"}"/>'
        for i in range(5))
    apex = h * math.sqrt(3) / 2
    cx, cy = apex / 3, h / 2
    star = star_points(cx, cy, h / 6, h / 6 * 0.382)
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}">{stripes}'
            f'<polygon points="0,0 {apex},{h / 2} 0,{h}" fill="#0050F0"/>'
            f'<polygon points="{star}" fill="#FFFFFF"/></svg>')


def flag_tw(w, h):
    ch, cw = h / 2, h * 0.75
    cx, cy = cw / 2, ch / 2
    tip, base, ring, disc = 0.375 * ch, 0.2125 * ch, 0.2125 * ch, 0.1875 * ch
    rays = []
    for i in range(12):
        a = math.radians(-90 + i * 30)
        a1, a2 = a - math.radians(15), a + math.radians(15)
        p0 = (cx + tip * math.cos(a), cy + tip * math.sin(a))
        p1 = (cx + base * math.cos(a1), cy + base * math.sin(a1))
        p2 = (cx + base * math.cos(a2), cy + base * math.sin(a2))
        rays.append(f'<polygon points="{p0[0]:.2f},{p0[1]:.2f} {p1[0]:.2f},{p1[1]:.2f} {p2[0]:.2f},{p2[1]:.2f}" fill="#FFFFFF"/>')
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}">'
            f'<rect width="{w}" height="{h}" fill="#FE0000"/>'
            f'<rect width="{cw}" height="{ch}" fill="#000095"/>{"".join(rays)}'
            f'<circle cx="{cx}" cy="{cy}" r="{base}" fill="#FFFFFF"/>'
            f'<circle cx="{cx}" cy="{cy}" r="{ring}" fill="#000095"/>'
            f'<circle cx="{cx}" cy="{cy}" r="{disc}" fill="#FFFFFF"/></svg>')


def flag_bd(w, h):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}">'
            f'<rect width="{w}" height="{h}" fill="#006A4E"/>'
            f'<circle cx="{0.45 * w}" cy="{h / 2}" r="{h / 3}" fill="#F42A41"/></svg>')


def back_flag(fn, w, h) -> Image.Image:
    return svg_to_img(fn(w, h), w, h).convert("RGB")


def back_nj(w, h) -> Image.Image:
    svg = (DL / "nj_flag.svg").read_text()
    zoom = 1.45
    art = svg_to_img(svg, int(h * zoom * 1000 / 600), int(h * zoom))
    field = art.getpixel((5, 5))[:3]
    img = Image.new("RGB", (w, h), field)
    img.paste(art, ((w - art.width) // 2, (h - art.height) // 2 + int(h * 0.04)), art)
    return img


def back_horsemen(w, h) -> Image.Image:
    src = Image.open(DL / "four_horsemen.jpg").convert("L")
    sw, sh = src.size
    band_h = sw / 2
    top = int(sh * 0.22)
    crop = src.crop((0, top, sw, int(top + band_h))).resize((w, h), Image.LANCZOS)
    ink = np.asarray(crop, np.float32) / 255.0
    paper = tint(value_noise(w, h, 6, 4, seed=11), (226, 212, 180), (240, 230, 205))
    rgb = paper * ink[..., None] + np.array([28, 22, 18], np.float32) * (1 - ink[..., None])
    return to_img(rgb)


def back_plain(w, h, colour) -> Image.Image:
    n = value_noise(w, h, 5, 4, seed=3)
    c = np.array(colour, np.float32)
    return to_img(tint(n, c * 0.95, np.minimum(c * 1.03, 255)))


# --- tile faces ---------------------------------------------------------------------------

FACE_STYLES = {
    "white": {"face": (246, 244, 238), "pips": {n: (18, 18, 18) for n in range(7)}},
    "ivory": {"face": (238, 226, 196), "pips": {n: (24, 20, 16) for n in range(7)}},
    "colors": {"face": (246, 244, 238), "pips": {
        1: (40, 150, 220), 2: (40, 150, 70), 3: (205, 40, 45),
        4: (120, 70, 160), 5: (20, 45, 120), 6: (230, 130, 20), 0: (0, 0, 0)}},
}

BACKS = {
    "pr": lambda w, h: back_flag(flag_pr, w, h),
    "tw": lambda w, h: back_flag(flag_tw, w, h),
    "bd": lambda w, h: back_flag(flag_bd, w, h),
    "nj": back_nj,
    "horsemen": back_horsemen,
    "plain": None,  # body colour, generated per face style
}


def to_px(x: float, z: float) -> tuple[float, float]:
    """Tile space -> face-cell pixel (u right = +x, image down = -z since v grows with +z)."""
    return (x + G.L / 2) * PX, (G.W / 2 - z) * PX


def draw_face(hi: int, lo: int, style: dict) -> Image.Image:
    w, h = CELL_W * SS, CELL_H * SS
    face = np.array(style["face"], np.float32)
    n = value_noise(w // 4, h // 4, 3, 3, seed=hi * 10 + lo)
    base = tint(np.asarray(Image.fromarray((n * 255).astype(np.uint8)).resize((w, h)), np.float32) / 255,
                face * 0.985, np.minimum(face * 1.01, 255))
    img = to_img(base)
    d = ImageDraw.Draw(img)
    s = SS * PX

    # divider groove
    gx = (G.L / 2) * s
    gw = max(2, int(0.006 * s))
    d.rectangle([gx - gw, 0.07 * s, gx + gw, h - 0.07 * s], fill=tuple(int(c * 0.78) for c in style["face"]))

    # pips with a soft inner shade (light comes from the top of the cell)
    for value, cx in ((hi, G.L / 4), (lo, -G.L / 4)):
        col = np.array(style["pips"][value], np.float32)
        for gxx, gzz in G.PIP_LAYOUT[value]:
            px, pz = to_px(cx + gxx * G.PIP_OFF, gzz * G.PIP_OFF)
            px, pz, r = px * SS, pz * SS, G.PIP_R * s
            for k in range(12, -1, -1):
                t = k / 12
                shade = 0.55 + 0.45 * (1 - t)
                cc = tuple(int(min(255, v * shade + (40 * (1 - t) if col.sum() < 60 else 0))) for v in col)
                rr = r * (0.55 + 0.45 * t)
                off = (1 - t) * r * 0.18
                d.ellipse([px - rr, pz - rr + off, px + rr, pz + rr + off], fill=cc)
            d.ellipse([px - r, pz - r, px + r, pz + r], outline=tuple(int(v * 0.6) for v in col), width=max(1, SS))

    # brass spinner nub
    cx, cz = to_px(0, 0)
    cx, cz, r = cx * SS, cz * SS, G.NUB_R * s
    for k in range(16, -1, -1):
        t = k / 16
        c0, c1 = np.array([150, 112, 40]), np.array([250, 225, 140])
        cc = tuple(int(v) for v in (c0 + (c1 - c0) * (1 - t) ** 1.5))
        rr = r * (0.25 + 0.75 * t)
        off = -(1 - t) * r * 0.25
        d.ellipse([cx - rr + off, cz - rr + off, cx + rr + off, cz + rr + off], fill=cc)
    return img.resize((CELL_W, CELL_H), Image.LANCZOS)


def build_atlas(face_name: str, back_name: str, faces_cache: dict) -> Image.Image:
    style = FACE_STYLES[face_name]
    atlas = Image.new("RGB", ATLAS, style["face"])
    for hi in range(7):
        for lo in range(hi + 1):
            key = (face_name, hi, lo)
            if key not in faces_cache:
                faces_cache[key] = draw_face(hi, lo, style)
            idx = G.tile_index(hi, lo)
            atlas.paste(faces_cache[key], ((idx % G.ATLAS_COLS) * CELL_W, (idx // G.ATLAS_COLS) * CELL_H))
    body = back_plain(CELL_W, CELL_H, style["face"])
    if back_name == "plain":
        back = back_plain(CELL_W, CELL_H, tuple(int(c * 0.97) for c in style["face"]))
    else:
        back = BACKS[back_name](CELL_W, CELL_H)
    for idx, im in ((G.BACK_CELL, back), (G.BODY_CELL, body)):
        atlas.paste(im, ((idx % G.ATLAS_COLS) * CELL_W, (idx // G.ATLAS_COLS) * CELL_H))
    return atlas


# --- table, wood, scoreboard ------------------------------------------------------------------

def streaks(w: int, h: int, seed: int, across: int) -> np.ndarray:
    """Noise stretched along x: long thin fibres."""
    r = np.random.default_rng(seed)
    small = r.random((across, 24)).astype(np.float32)
    img = Image.fromarray((small * 255).astype(np.uint8)).resize((w, h), Image.BICUBIC)
    return np.asarray(img, np.float32) / 255.0


def wood(w: int, h: int, light, dark, seed: int, rings: float = 38.0) -> Image.Image:
    """Hard-maple-like board: straight, low-contrast grain along x with soft figure."""
    y = np.linspace(0, 1, h, dtype=np.float32)[:, None]
    warp = value_noise(w, h, 2, 3, seed=seed) * 0.6
    grain = 0.5 + 0.5 * np.sin((y * rings + warp) * math.pi * 2)
    grain = grain ** 6
    fibres = streaks(w, h, seed + 1, h // 3) * 0.6 + streaks(w, h, seed + 2, h // 9) * 0.4
    figure = value_noise(w, h, 3, 3, seed=seed + 3)
    t = np.clip(0.35 * grain + 0.35 * fibres + 0.3 * figure, 0, 1)
    return to_img(tint(t, light, dark))


def felt(size: int) -> Image.Image:
    n = value_noise(size, size, 64, 3, seed=21) * 0.7 + value_noise(size, size, 4, 3, seed=22) * 0.3
    return to_img(tint(n, (20, 92, 48), (34, 122, 66)))


def slate(size: int) -> Image.Image:
    n = value_noise(size, size, 6, 6, seed=31)
    streak = value_noise(size, size // 8, 3, 4, seed=32)
    streak = np.asarray(Image.fromarray((streak * 255).astype(np.uint8)).resize((size, size)), np.float32) / 255
    t = np.clip(0.7 * n + 0.3 * streak, 0, 1)
    return to_img(tint(t, (38, 42, 48), (64, 70, 78)))


def matte_grey(size: int) -> Image.Image:
    fine = value_noise(size, size, 160, 2, seed=41)
    broad = value_noise(size, size, 3, 3, seed=42)
    n = 0.75 * fine + 0.25 * broad
    return to_img(tint(n, (118, 118, 116), (134, 134, 131)))


def suckers(size: int) -> Image.Image:
    img = matte_grey(size)
    font = ImageFont.truetype(str(DL / "GreatVibes-Regular.ttf"), int(size * 0.30))
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    text = "Suckers"
    bbox = d.textbbox((0, 0), text, font=font)
    tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
    pos = ((size - tw) / 2 - bbox[0], (size - th) / 2 - bbox[1])
    shadow = Image.new("RGBA", img.size, (0, 0, 0, 0))
    ImageDraw.Draw(shadow).text((pos[0] + size * 0.004, pos[1] + size * 0.006), text, font=font, fill=(0, 0, 0, 120))
    shadow = shadow.filter(ImageFilter.GaussianBlur(size * 0.004))
    d.text(pos, text, font=font, fill=(28, 28, 30, 235))
    out = img.convert("RGBA")
    out.alpha_composite(shadow)
    out.alpha_composite(layer)
    return out.convert("RGB")


COQUI_SVG = """
<g stroke="#F2EFE6" stroke-width="10" stroke-linejoin="round" paint-order="stroke" fill="#5a3a22">
  <path d="M-150,40 C-160,-30 -90,-80 -10,-70 C40,-64 70,-40 80,-10 C95,30 60,70 0,78 C-70,86 -140,80 -150,40 Z"/>
  <path d="M40,-60 C70,-120 170,-120 190,-60 C205,-20 170,20 110,18 C70,16 40,0 30,-20 Z"/>
  <path d="M-140,60 C-150,0 -60,-10 -40,40 C-30,70 -60,90 -100,92 C-125,92 -138,80 -140,60 Z"/>
  <path d="M-60,85 C-20,100 40,104 70,96 C80,93 84,100 76,106 C40,118 -20,116 -64,104 Z"/>
  <path d="M120,10 C125,50 130,80 150,98 C140,104 120,100 110,80 C100,60 100,35 102,14 Z"/>
  <circle cx="70" cy="102" r="11"/><circle cx="88" cy="110" r="10"/><circle cx="104" cy="112" r="9"/>
  <circle cx="150" cy="100" r="11"/><circle cx="166" cy="108" r="10"/><circle cx="178" cy="98" r="9"/>
</g>
<circle cx="132" cy="-72" r="26" fill="#d9a441" stroke="#2a1a0e" stroke-width="5"/>
<ellipse cx="136" cy="-72" rx="9" ry="15" fill="#120a04"/>
<path d="M175,-30 C160,-22 140,-20 120,-24" stroke="#2a1a0e" stroke-width="5" fill="none" stroke-linecap="round"/>
"""


def pr_table(size: int) -> Image.Image:
    """Puerto Rico flag table face with a faded coquí in the white stripe area."""
    w, h = size, size
    stripes = "".join(
        f'<rect x="0" y="{i * h / 5}" width="{w}" height="{h / 5 + 0.5}" fill="{"#C81E1E" if i % 2 == 0 else "#F2EFE6"}"/>'
        for i in range(5))
    apex = h * math.sqrt(3) / 2
    star = star_points(apex / 3, h / 2, h / 6, h / 6 * 0.382)
    svg = (f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}">{stripes}'
           f'<polygon points="0,0 {apex},{h / 2} 0,{h}" fill="#1E4FC8"/>'
           f'<polygon points="{star}" fill="#F2EFE6"/>'
           f'<g transform="translate({w * 0.7},{h * 0.73}) scale({size / 900})">{COQUI_SVG}</g>'
           f'</svg>')
    flag = np.asarray(svg_to_img(svg, w, h).convert("RGB"), np.float32)
    cloth = value_noise(w, h, 140, 2, seed=51)[..., None]
    return to_img(flag * (0.9 + 0.12 * cloth))


def chalkboard(w: int, h: int) -> Image.Image:
    n = value_noise(w, h, 8, 5, seed=61)
    return to_img(tint(n, (34, 46, 40), (50, 64, 56)))


# --- main ---------------------------------------------------------------------------------------

def save(img: Image.Image, path: Path, quality: int = 90):
    path.parent.mkdir(parents=True, exist_ok=True)
    img.save(path, quality=quality, optimize=True)
    print(f"  {path.relative_to(ROOT)}  {path.stat().st_size / 1e6:.2f} MB")


def main(argv: list[str]):
    only = set(argv)
    if not only or "tiles" in only:
        cache: dict = {}
        for face in FACE_STYLES:
            for back in BACKS:
                save(build_atlas(face, back, cache), OUT / "tiles" / f"{face}_{back}.jpg")
    if not only or "table" in only:
        S = 2048
        save(felt(S), OUT / "table" / "face_felt.jpg")
        save(wood(S, S, (232, 196, 146), (196, 150, 96), seed=71, rings=22), OUT / "table" / "face_maple.jpg")
        save(pr_table(S), OUT / "table" / "face_pr.jpg")
        save(slate(S), OUT / "table" / "face_slate.jpg")
        save(suckers(S), OUT / "table" / "face_suckers.jpg")
        save(wood(1024, 1024, (222, 180, 124), (184, 136, 82), seed=81, rings=10), OUT / "table" / "border_maple.jpg")
    if not only or "ui" in only:
        # Hand-panel images: each tile face (rounded corners, transparent outside), per face style.
        cache: dict = {}
        for face, style in FACE_STYLES.items():
            for hi in range(7):
                for lo in range(hi + 1):
                    im = draw_face(hi, lo, style).resize((256, 128), Image.LANCZOS).convert("RGBA")
                    mask = Image.new("L", im.size, 0)
                    ImageDraw.Draw(mask).rounded_rectangle([0, 0, 255, 127], radius=14, fill=255)
                    edge = Image.new("RGBA", im.size, (0, 0, 0, 0))
                    ImageDraw.Draw(edge).rounded_rectangle([1, 1, 254, 126], radius=14, outline=(90, 80, 60, 255), width=3)
                    im.putalpha(mask)
                    im.alpha_composite(edge)
                    im = im.rotate(90, expand=True)          # vertical, high end on top
                    out = OUT / "ui" / face / f"tv_{hi}{lo}.png"
                    out.parent.mkdir(parents=True, exist_ok=True)
                    im.save(out, optimize=True)
        print("  assets/textures/ui/<face>/t_*.png (84 images)")
    if not only or "board" in only:
        board = chalkboard(1024, 1024)
        frame = wood(512, 512, (150, 100, 55), (98, 62, 30), seed=91, rings=10)
        combo = Image.new("RGB", (1024, 1024))
        combo.paste(board.resize((1024, 768)), (0, 0))
        combo.paste(frame.resize((1024, 256)), (0, 768))
        save(combo, OUT / "board" / "scoreboard.jpg")


if __name__ == "__main__":
    main(sys.argv[1:])
