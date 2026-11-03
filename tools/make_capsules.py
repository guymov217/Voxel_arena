#!/usr/bin/env python3
"""Every Steam capsule and store graphic for WRECKSMITH, from the key-art frames rendered by the
game itself (tests/capsuleart.gd: staged scenes of the current build frozen at the blow and drawn
large, in clear afternoon light with depth of field) and the voxel logo (tools/make_logo.py).

Each frame is graded like a film still (contrast, warm highlights, cool shadows, a vignette) and
cropped to the capsule around its subject; the logo sits on a soft dark ground so it reads at the
store's smallest size. The capsules carry the name and nothing else (Steam's rules). The feature
banners for the store page's description each name one side of the game.

    python3 tools/make_capsules.py [keyart dir] [out dir]

Needs Pillow and numpy. (voxel_title and the colours below are also used by the poster and
trailer tools.)"""
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageEnhance, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FONT = os.path.join(ROOT, "tools", "fonts", "Cinzel-Black.ttf")
CINZEL = os.path.join(ROOT, "art", "fonts", "Cinzel.ttf")
SANS = os.path.join(ROOT, "art", "fonts", "AlegreyaSans-Medium.ttf")
TITLE = "WRECKSMITH"

GOLD_HI = (255, 226, 140)
GOLD = (214, 160, 58)
GOLD_LO = (140, 92, 28)
SIDE = (78, 44, 14)
IRON = (18, 14, 12)
BLOOD = (150, 18, 16)

# capsule: (size, key-art frame, focus x, focus y (0..1 of the frame), logo as (kind, x, y, w, h):
# kind "line" or "stack", the box fractions of the capsule; None: no logo), and optionally a zoom
# (closer in on the focus than the frame's own width)
CAPSULES = {
    "header_920x430": ((920, 430), "giant_wide", 0.47, 0.45, ("line", 0.05, 0.67, 0.90, 0.29), 1.15),
    "library_header_920x430": ((920, 430), "giant_wide", 0.47, 0.45, ("line", 0.05, 0.67, 0.90, 0.29), 1.15),
    "small_462x174": ((462, 174), "giant_wide", 0.52, 0.42, ("line", 0.04, 0.18, 0.92, 0.66)),
    "main_1232x706": ((1232, 706), "giant_wide", 0.47, 0.46, ("line", 0.08, 0.71, 0.84, 0.25), 1.12),
    "vertical_748x896": ((748, 896), "beast_tall", 0.50, 0.55, ("stack", 0.08, 0.03, 0.84, 0.27)),
    "library_600x900": ((600, 900), "giant_tall", 0.50, 0.58, ("stack", 0.08, 0.03, 0.84, 0.25)),
    "library_hero_3840x1240": ((3840, 1240), "squad_hero", 0.50, 0.55, None),
    "background_1438x810": ((1438, 810), "dragon_wide", 0.50, 0.50, None),
    "event_cover_800x450": ((800, 450), "clash_wide", 0.50, 0.50, ("line", 0.06, 0.69, 0.88, 0.27)),
    "event_header_1920x622": ((1920, 622), "dragon_wide", 0.50, 0.42, ("line", 0.25, 0.63, 0.50, 0.31)),
}

# The store page's description: a banner for each side of the game (616 wide: Steam's column).
FEATURES = [
    ("feature_forge", "forge_wide", "FORGE YOUR OWN WEAPON", "Voxel by voxel: its weight, its edge and its balance are what you build."),
    ("feature_cut", "clash_wide", "EVERY BLOW CUTS THE BODY", "Limbs, armour and bone break where they are struck."),
    ("feature_giants", "giant_wide", "CYCLOPES, TITANS, GIANTS", "Bring a giant to his knees, one chunk at a time."),
    ("feature_beasts", "beast_wide", "24 BEASTS AND MONSTERS", "Lions, crocodiles, gorillas, hydras and dragons."),
    ("feature_dragon", "dragon_wide", "FIRE, BLOOD, THE CROWD", "The Emperor watches. The crowd decides."),
    ("feature_coop", "squad_wide", "FIGHT TOGETHER", "The whole campaign in co-op, up to four players."),
]


def voxel_title(height):
    """The title as a block of voxels: the letters rasterised small, each pixel a bevelled cube
    with its side faces stepping down and right, on a dark rim. RGBA, `height` px tall."""
    font = ImageFont.truetype(FONT, 24)
    # Drawn letter by letter with a little tracking, so neighbours never touch.
    track = 2
    top = min(font.getbbox(ch)[1] for ch in TITLE)
    bottom = max(font.getbbox(ch)[3] for ch in TITLE)
    w = sum(int(font.getlength(ch)) + track for ch in TITLE) + 2
    h = bottom - top + 2
    mask = Image.new("L", (w, h), 0)
    md = ImageDraw.Draw(mask)
    x = 1
    for ch in TITLE:
        md.text((x, 1 - top), ch, font=font, fill=255)
        x += int(font.getlength(ch)) + track
    px = mask.load()
    on = [[px[x, y] > 110 for x in range(w)] for y in range(h)]
    depth = 2
    cell = max(2, height // (h + depth + 2))
    W, H = (w + depth + 2) * cell, (h + depth + 2) * cell
    out = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(out)
    ox, oy = cell, cell
    cells = [(x, y) for y in range(h) for x in range(w) if on[y][x]]
    # The dark rim and the extrusion: the same shape stepped down-right, darkest furthest back.
    for k in range(depth, 0, -1):
        for x, y in cells:
            X, Y = ox + (x + k) * cell, oy + (y + k) * cell
            d.rectangle([X - cell // 2, Y - cell // 2, X + cell + cell // 2 - 1, Y + cell + cell // 2 - 1], fill=IRON + (255,))
    for k in range(depth, 0, -1):
        t = k / depth
        col = tuple(int(SIDE[i] * (1.15 - 0.45 * t)) for i in range(3))
        for x, y in cells:
            X, Y = ox + (x + k) * cell, oy + (y + k) * cell
            d.rectangle([X, Y, X + cell - 1, Y + cell - 1], fill=col + (255,))
    # The front faces: gold, lighter at the top of the letters, every cube bevelled.
    for x, y in cells:
        X, Y = ox + x * cell, oy + y * cell
        t = y / max(1, h - 1)
        a, b, u = (GOLD_HI, GOLD, t * 2) if t < 0.5 else (GOLD, GOLD_LO, t * 2 - 1)
        base = tuple(int(a[i] + (b[i] - a[i]) * u) for i in range(3))
        d.rectangle([X, Y, X + cell - 1, Y + cell - 1], fill=base + (255,))
        e = max(1, cell // 5)
        if y == 0 or not on[y - 1][x]:
            d.rectangle([X, Y, X + cell - 1, Y + e - 1], fill=GOLD_HI + (255,))
        if x == 0 or not on[y][x - 1]:
            d.rectangle([X, Y, X + e - 1, Y + cell - 1], fill=tuple(min(255, c + 25) for c in base) + (255,))
        if y == h - 1 or not on[y + 1][x]:
            d.rectangle([X, Y + cell - e, X + cell - 1, Y + cell - 1], fill=tuple(int(c * 0.72) for c in base) + (255,))
        if x == w - 1 or not on[y][x + 1]:
            d.rectangle([X + cell - e, Y, X + cell - 1, Y + cell - 1], fill=tuple(int(c * 0.8) for c in base) + (255,))
        # A faint seam between the cubes, so the letters read as stacked voxels.
        d.line([X, Y + cell - 1, X + cell - 1, Y + cell - 1], fill=tuple(int(c * 0.9) for c in base) + (255,))
        d.line([X + cell - 1, Y, X + cell - 1, Y + cell - 1], fill=tuple(int(c * 0.9) for c in base) + (255,))
    return out


def fit(img, max_w, max_h):
    s = min(max_w / img.width, max_h / img.height)
    return img.resize((max(1, int(img.width * s)), max(1, int(img.height * s))), Image.NEAREST)


def cover(shot, size, fx, fy, zoom=1.0):
    """Scale the shot to cover `size` (`zoom` times closer) and crop around the focus point."""
    W, H = size
    s = max(W / shot.width, H / shot.height) * zoom
    img = shot.resize((int(shot.width * s + 0.5), int(shot.height * s + 0.5)), Image.LANCZOS)
    x = int(min(max(0, fx * img.width - W / 2), img.width - W))
    y = int(min(max(0, fy * img.height - H / 2), img.height - H))
    return img.crop((x, y, x + W, y + H))


def shade_under(img, box):
    """Darken the band behind the title, fading out, so the letters read on any frame."""
    W, H = img.size
    x, y, w, h = box
    band = Image.new("L", (W, H), 0)
    d = ImageDraw.Draw(band)
    d.rectangle([0, int((y - h * 0.35) * H), W, int((y + h * 1.35) * H)], fill=170)
    band = band.filter(ImageFilter.GaussianBlur(H * 0.08))
    dark = Image.new("RGB", (W, H), (10, 6, 4))
    return Image.composite(dark, img, band)


def vignette(img, k=0.55):
    W, H = img.size
    m = Image.new("L", (W, H), 0)
    ImageDraw.Draw(m).ellipse([-W * 0.25, -H * 0.25, W * 1.25, H * 1.25], fill=255)
    m = m.filter(ImageFilter.GaussianBlur(min(W, H) * 0.18))
    dark = Image.new("RGB", (W, H), (0, 0, 0))
    inv = m.point(lambda v: int((255 - v) * k))
    return Image.composite(dark, img, inv)


def blood_rule(img, y, w_frac=0.5):
    """A thin blood-red rule under the title."""
    W, _ = img.size
    d = ImageDraw.Draw(img)
    w = int(W * w_frac)
    d.rectangle([(W - w) // 2, y, (W + w) // 2, y + max(2, W // 300)], fill=BLOOD)


def grade(img, punch=1.0):
    """A film still's grade: an S-curve, warm highlights and teal-leaning shadows, richer colour,
    the haze pulled back a little, a touch of sharpening."""
    a = np.asarray(img.convert("RGB")).astype(np.float32) / 255.0
    lum = (a[..., 0] * 0.2126 + a[..., 1] * 0.7152 + a[..., 2] * 0.0722)[..., None]
    a = np.clip((a - 0.04 * punch) / (1 - 0.04 * punch), 0, 1)
    a = a + 0.22 * punch * a * (1 - a) * (2 * a - 1)
    hi = np.clip((lum - 0.5) / 0.5, 0, 1)
    lo = np.clip((0.42 - lum) / 0.42, 0, 1)
    a = np.clip(a + hi * np.array([0.04, 0.018, -0.03]) + lo * np.array([-0.03, 0.004, 0.04]), 0, 1)
    out = Image.fromarray((a * 255 + 0.5).astype(np.uint8))
    out = ImageEnhance.Color(out).enhance(1.0 + 0.14 * punch)
    return out.filter(ImageFilter.UnsharpMask(radius=1.6, percent=60, threshold=2))


def ground_for(img, box):
    """A soft dark ground where the logo sits, fading into the picture."""
    W, H = img.size
    x, y, w, h = box
    m = Image.new("L", (W, H), 0)
    ImageDraw.Draw(m).rounded_rectangle([int((x - w * 0.04) * W), int((y - h * 0.12) * H), int((x + w * 1.04) * W), int((y + h * 1.12) * H)], radius=int(min(W, H) * 0.1), fill=170)
    m = m.filter(ImageFilter.GaussianBlur(max(W, H) * 0.035))
    return Image.composite(Image.new("RGB", (W, H), (12, 6, 3)), img, m)


def place_logo(img, logo, box):
    W, H = img.size
    x, y, w, h = box
    k = min(w * W / logo.width, h * H / logo.height)
    lg = logo.resize((max(1, int(logo.width * k)), max(1, int(logo.height * k))), Image.LANCZOS)
    out = img.convert("RGBA")
    out.alpha_composite(lg, (int(x * W + (w * W - lg.width) / 2), int(y * H + (h * H - lg.height) / 2)))
    return out.convert("RGB")


def cinzel(size, weight=800):
    f = ImageFont.truetype(CINZEL, size)
    try:
        f.set_variation_by_axes([weight])
    except OSError:
        pass
    return f


def feature(frame, title, line):
    """A banner for the description: the frame graded, a dark plate at its foot with the line."""
    W, H = 616, 330
    img = vignette(grade(cover(frame, (W, H), 0.5, 0.5)), 0.45)
    plate = Image.new("L", (W, H), 0)
    ImageDraw.Draw(plate).rectangle([0, int(H * 0.68), W, H], fill=205)
    plate = plate.filter(ImageFilter.GaussianBlur(24))
    img = Image.composite(Image.new("RGB", (W, H), (10, 5, 3)), img, plate)
    d = ImageDraw.Draw(img)
    ft = cinzel(28, 900)
    fs = ImageFont.truetype(SANS, 17)
    ty = int(H * 0.735)
    tw = d.textlength(title, font=ft)
    d.text(((W - tw) / 2 + 2, ty + 2), title, font=ft, fill=(0, 0, 0))
    d.text(((W - tw) / 2, ty), title, font=ft, fill=(240, 196, 98))
    d.rectangle([W * 0.34, ty + 39, W * 0.66, ty + 41], fill=BLOOD)
    lw = d.textlength(line, font=fs)
    d.text(((W - lw) / 2, ty + 49), line, font=fs, fill=(236, 226, 210))
    return img


def main():
    src = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "docs", "store", "keyart")
    out = sys.argv[2] if len(sys.argv) > 2 else os.path.join(ROOT, "docs", "store", "capsules")
    os.makedirs(out, exist_ok=True)
    logos = {k: Image.open(os.path.join(out, n)).convert("RGBA") for k, n in (("line", "logo.png"), ("stack", "logo_stacked.png"))}
    frames = {}

    def frame(name):
        if name not in frames:
            # (the key art kept as a high-quality JPEG in the repository, a PNG straight from the render)
            ps = [os.path.join(src, name + ext) for ext in (".png", ".jpg")]
            p = next((q for q in ps if os.path.exists(q)), None)
            frames[name] = Image.open(p).convert("RGB") if p else None
        return frames[name]

    for name, (size, fr, fx, fy, lg, *zoom) in CAPSULES.items():
        f = frame(fr)
        if f is None:
            print("missing", fr)
            continue
        img = vignette(grade(cover(f, size, fx, fy, zoom[0] if zoom else 1.0)), 0.42)
        if lg:
            kind, x, y, w, h = lg
            img = place_logo(ground_for(img, (x, y, w, h)), logos[kind], (x, y, w, h))
        img.save(os.path.join(out, name + ".png"))
        print("saved", name)
    for name, fr, title, line in FEATURES:
        f = frame(fr)
        if f is None:
            print("missing", fr)
            continue
        feature(f, title, line).save(os.path.join(out, name + ".png"))
        print("saved", name)


if __name__ == "__main__":
    main()
