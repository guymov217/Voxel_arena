#!/usr/bin/env python3
"""Steam capsules for WRECKSMITH from the store screenshots (docs/store/screenshots, made by the
steamshots probe): every size the store and the library ask for, the title drawn as voxel letters
in aged gold over a frame of the game. Needs Pillow.

    python3 tools/make_capsules.py [screenshots dir] [out dir]

Each capsule names the screenshot it is cut from and the point of it to keep in frame (BACKDROP)."""
import os
import sys

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FONT = os.path.join(ROOT, "tools", "fonts", "Cinzel-Black.ttf")
TITLE = "WRECKSMITH"

GOLD_HI = (255, 226, 140)
GOLD = (214, 160, 58)
GOLD_LO = (140, 92, 28)
SIDE = (78, 44, 14)
IRON = (18, 14, 12)
BLOOD = (150, 18, 16)

# capsule: (size, screenshot, focus x, focus y (0..1 of the shot), title box as (x, y, w, h)
# fractions of the capsule, or None for no title)
BACKDROP = {
    "header_920x430": ((920, 430), "03_clash", 0.5, 0.45, (0.06, 0.62, 0.88, 0.30)),
    "small_462x174": ((462, 174), "03_clash", 0.5, 0.45, (0.05, 0.22, 0.90, 0.56)),
    "main_1232x706": ((1232, 706), "05_monster_hunt", 0.5, 0.45, (0.08, 0.66, 0.84, 0.26)),
    "vertical_748x896": ((748, 896), "04_bloodbath", 0.5, 0.45, (0.06, 0.06, 0.88, 0.17)),
    "library_600x900": ((600, 900), "04_bloodbath", 0.5, 0.45, (0.06, 0.06, 0.88, 0.15)),
    "background_1438x810": ((1438, 810), "01_title", 0.5, 0.5, None),
    "library_hero_3840x1240": ((3840, 1240), "05_monster_hunt", 0.5, 0.5, None),
}


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


def cover(shot, size, fx, fy):
    """Scale the shot to cover `size` and crop around the focus point."""
    W, H = size
    s = max(W / shot.width, H / shot.height)
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


def main():
    shots = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "docs", "store", "screenshots")
    out = sys.argv[2] if len(sys.argv) > 2 else os.path.join(ROOT, "docs", "store", "capsules")
    os.makedirs(out, exist_ok=True)
    for name, (size, shot, fx, fy, box) in BACKDROP.items():
        path = os.path.join(shots, shot + ".png")
        if not os.path.exists(path):
            print("missing", path)
            continue
        img = vignette(cover(Image.open(path).convert("RGB"), size, fx, fy))
        if box:
            img = shade_under(img, box)
            W, H = size
            x, y, w, h = box
            title = fit(voxel_title(int(h * H * 2)), int(w * W), int(h * H))
            tx = int(x * W + (w * W - title.width) / 2)
            ty = int(y * H + (h * H - title.height) / 2)
            img.paste(title, (tx, ty), title)
            if H >= 400:
                blood_rule(img, ty + title.height + max(4, H // 90), 0.35)
        img.save(os.path.join(out, name + ".png"))
        print("saved", name)
    # The library logo: the title alone on transparency, centred in 1280x720.
    logo = Image.new("RGBA", (1280, 720), (0, 0, 0, 0))
    t = fit(voxel_title(900), 1180, 400)
    logo.paste(t, ((1280 - t.width) // 2, (720 - t.height) // 2), t)
    logo.save(os.path.join(out, "library_logo_1280x720.png"))
    print("saved library_logo_1280x720")


if __name__ == "__main__":
    main()
