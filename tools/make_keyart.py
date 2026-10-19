#!/usr/bin/env python3
"""The WRECKSMITH poster and logo from the key-art frames (tests/keyart.gd): a warm graded frame
of the game with drifting embers, the voxel title in gold over it, the line under it and the
Steam strip at the foot. Writes poster_1200x1800.png, poster_wide_2560x1080.png, logo.png (the
title alone, transparent) and library_logo_1280x720.png into the out dir. Needs Pillow.

    python3 tools/make_keyart.py <frames dir> <out dir>"""
import os
import random
import sys

from PIL import Image, ImageChops, ImageDraw, ImageEnhance, ImageFilter, ImageFont

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import make_capsules as mc  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CINZEL = os.path.join(ROOT, "art", "fonts", "Cinzel.ttf")
TAGLINE = "FORGE IT.  SWING IT.  WRECK EVERYTHING."
STRIP = "COMING SOON TO STEAM"
FACTS = "PHYSICS GLADIATOR BRAWLER  ·  BUILD YOUR WEAPON VOXEL BY VOXEL  ·  UP TO 8 PLAYERS"


def font(size, weight=700):
    f = ImageFont.truetype(CINZEL, size)
    try:
        f.set_variation_by_axes([weight])
    except OSError:
        pass
    return f


def grade(img):
    """Sunset grade: deeper contrast, richer colour, warm highlights and teal-leaning shadows."""
    img = ImageEnhance.Contrast(img).enhance(1.16)
    img = ImageEnhance.Color(img).enhance(1.28)
    r, g, b = img.split()
    lum = img.convert("L")
    warm = Image.merge("RGB", (r.point(lambda v: min(255, int(v * 1.07 + 6))), g.point(lambda v: min(255, int(v * 1.01))), b.point(lambda v: int(v * 0.9))))
    cool = Image.merge("RGB", (r.point(lambda v: int(v * 0.9)), g.point(lambda v: min(255, int(v * 1.0 + 4))), b.point(lambda v: min(255, int(v * 1.12 + 10)))))
    # Highlights warm, shadows cool.
    mask = lum.point(lambda v: max(0, min(255, int((v - 60) * 1.6))))
    return Image.composite(warm, cool, mask)


def glow(img, k=0.35, radius=18):
    """A bloom on the bright parts (fire, gold, the sky by the sun)."""
    bright = img.convert("L").point(lambda v: 255 if v > 200 else int(max(0, v - 150) * 4))
    hi = Image.composite(img, Image.new("RGB", img.size, (0, 0, 0)), bright).filter(ImageFilter.GaussianBlur(radius))
    return ImageChops.add(img, ImageEnhance.Brightness(hi).enhance(k))


def embers(img, n, seed=3):
    """Sparks drifting up from the fire: small hot dots, a soft halo round each."""
    W, H = img.size
    rng = random.Random(seed)
    layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    for _ in range(n):
        x = rng.random() * W
        y = H * (0.25 + 0.75 * rng.random() ** 0.7)
        r = rng.choice([1, 1, 2, 2, 3, 4]) * W / 1200
        c = rng.choice([(255, 196, 92), (255, 142, 48), (255, 228, 160), (255, 110, 40)])
        d.ellipse([x - r, y - r, x + r, y + r], fill=c + (int(150 + 100 * rng.random()),))
    halo = layer.filter(ImageFilter.GaussianBlur(W / 300))
    out = img.convert("RGBA")
    out = Image.alpha_composite(out, halo)
    out = Image.alpha_composite(out, layer)
    return out.convert("RGB")


def text_center(d, W, y, text, f, fill, stroke=(16, 8, 3), sw=4):
    w = d.textlength(text, font=f)
    d.text(((W - w) / 2, y), text, font=f, fill=fill, stroke_width=sw, stroke_fill=stroke)


def cube(size, base):
    """One gold voxel like the title's: a bevelled face, lit from the top left. RGBA."""
    c = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(c)
    e = max(1, size // 5)
    d.rectangle([0, 0, size - 1, size - 1], fill=base + (255,))
    d.rectangle([0, 0, size - 1, e - 1], fill=mc.GOLD_HI + (255,))
    d.rectangle([0, 0, e - 1, size - 1], fill=tuple(min(255, v + 25) for v in base) + (255,))
    d.rectangle([0, size - e, size - 1, size - 1], fill=tuple(int(v * 0.65) for v in base) + (255,))
    d.rectangle([size - e, 0, size - 1, size - 1], fill=tuple(int(v * 0.75) for v in base) + (255,))
    return c


def title_block(width, seed=5):
    """The logo: the voxel title in gold on a glow of fire, its last letter breaking up into
    voxels flying off (the game's whole idea in a word), the tagline under it on a blood-red
    rule with WRECK EVERYTHING in the colour of the fire. RGBA."""
    rng = random.Random(seed)
    t = mc.voxel_title(int(width * 0.26))
    t = mc.fit(t, int(width * 0.86), int(width * 0.3))
    f = font(max(18, int(width * 0.04)), 800)
    pad = int(width * 0.035)
    top = int(width * 0.05)
    H = top + t.height + pad * 3 + int(width * 0.05)
    out = Image.new("RGBA", (width, H), (0, 0, 0, 0))
    tx = int(width * 0.05)
    # Fire behind the letters: a wide red-orange glow, hottest under the middle.
    fire = Image.new("RGBA", (width, H), (0, 0, 0, 0))
    fd = ImageDraw.Draw(fire)
    for k, (col, a) in enumerate([((170, 24, 8), 235), ((240, 90, 18), 215), ((255, 185, 70), 170)]):
        ix, iy = width * (0.06 + 0.07 * k), top + t.height * (0.15 + 0.12 * k)
        fd.ellipse([ix, iy, width - ix, top + t.height * (1.05 - 0.05 * k)], fill=col + (a,))
    fire = fire.filter(ImageFilter.GaussianBlur(width * 0.028))
    out = Image.alpha_composite(out, fire)
    # A dark edge round the letters so they stand on the fire and on any frame.
    # (Both drawn on the whole canvas: blurred inside the letters' own box, they ended in a
    # hard-edged rectangle.)
    shape = Image.new("L", out.size, 0)
    shape.paste(t.split()[3], (tx, top))
    rim = Image.new("RGBA", out.size, (12, 5, 2, 255))
    rim.putalpha(shape.filter(ImageFilter.MaxFilter(9)).filter(ImageFilter.GaussianBlur(width * 0.006)).point(lambda v: min(255, int(v * 1.2))))
    # A hot orange edge glowing round the letters, as if they had just come out of the forge.
    hot = Image.new("RGBA", out.size, (255, 120, 30, 255))
    hot.putalpha(shape.filter(ImageFilter.MaxFilter(15)).filter(ImageFilter.GaussianBlur(width * 0.012)).point(lambda v: int(v * 0.85)))
    out = Image.alpha_composite(out, hot)
    out = Image.alpha_composite(out, rim)
    out.alpha_composite(t, (tx, top))
    # The last letter coming apart: voxels thrown off up and to the right, smaller and fainter
    # the further they fly, each turned a little.
    cell = max(4, t.height // 11)
    x0 = tx + t.width - cell * 4
    for i in range(34):
        u = rng.random()
        dist = (0.06 + u ** 1.3) * width * 0.09
        ang = rng.uniform(-1.3, 0.45)
        cx = x0 + dist * (0.75 + 0.35 * rng.random())
        cy = top + t.height * 0.42 + dist * ang * 0.85
        sz = max(4, int(cell * (1.35 - u * 0.8)))
        base = mc.GOLD if rng.random() < 0.6 else (230, 120, 40)
        cb = cube(sz, base).rotate(rng.uniform(-40, 40), resample=Image.BICUBIC, expand=True)
        if u > 0.6:
            cb.putalpha(cb.split()[3].point(lambda v, k=u: int(v * (1.4 - k))))
        if cx + cb.width < width and cy > 0:
            out.alpha_composite(cb, (int(cx), int(cy)))
    d = ImageDraw.Draw(out)
    ry = top + t.height + pad // 2
    rw = int(width * 0.52)
    d.rectangle([(width - rw) // 2, ry, (width + rw) // 2, ry + max(3, width // 240)], fill=mc.BLOOD + (255,))
    # The tagline: the first two in gold, the last in fire.
    parts = [("FORGE IT.  SWING IT.  ", mc.GOLD_HI), ("WRECK EVERYTHING.", (255, 120, 40))]
    total = sum(d.textlength(p, font=f) for p, _ in parts)
    x = (width - total) / 2
    for p, col in parts:
        d.text((x, ry + pad // 2), p, font=f, fill=col + (255,), stroke_width=max(2, width // 350), stroke_fill=(16, 6, 2, 255))
        x += d.textlength(p, font=f)
    return out


def poster(frame, size, title_w, title_y, strip=True):
    W, H = size
    img = mc.cover(frame, size, 0.5, 0.45)
    img = grade(img)
    img = glow(img)
    img = embers(img, int(W * H / 9000))
    img = mc.vignette(img, 0.5)
    # Dark at the top for the title, dark at the foot for the strip.
    top = Image.new("L", size, 0)
    ImageDraw.Draw(top).rectangle([0, 0, W, int(title_y + H * 0.2)], fill=150)
    top = top.filter(ImageFilter.GaussianBlur(H * 0.08))
    img = Image.composite(Image.new("RGB", size, (8, 5, 3)), img, top)
    out = img.convert("RGBA")
    tb = title_block(title_w)
    out.alpha_composite(tb, ((W - tb.width) // 2, int(title_y)))
    if strip:
        foot = Image.new("L", size, 0)
        ImageDraw.Draw(foot).rectangle([0, int(H * 0.86), W, H], fill=220)
        foot = foot.filter(ImageFilter.GaussianBlur(H * 0.03))
        out = Image.composite(Image.new("RGBA", size, (8, 5, 3, 255)), out, foot)
        d = ImageDraw.Draw(out)
        f1 = font(int(W * 0.05), 800)
        f2 = font(max(12, int(W * 0.0165)), 700)
        text_center(d, W, H * 0.885, STRIP, f1, mc.GOLD_HI + (255,), sw=max(2, W // 300))
        text_center(d, W, H * 0.885 + W * 0.075, FACTS, f2, (226, 200, 150, 255), sw=1)
    return out.convert("RGB")


def main():
    src, out = sys.argv[1], sys.argv[2]
    os.makedirs(out, exist_ok=True)
    tall = Image.open(os.path.join(src, "keyart_poster.png")).convert("RGB")
    poster(tall, (1200, 1800), 1100, 70).save(os.path.join(out, "poster_1200x1800.png"))
    wide_src = os.path.join(src, "keyart_wide.png")
    if os.path.exists(wide_src):
        wide = Image.open(wide_src).convert("RGB")
        poster(wide, (2560, 1080), 1500, 40, strip=False).save(os.path.join(out, "poster_wide_2560x1080.png"))
    logo = title_block(2000)
    logo.save(os.path.join(out, "logo.png"))
    lib = Image.new("RGBA", (1280, 720), (0, 0, 0, 0))
    l2 = mc.fit(logo, 1240, 680)
    lib.alpha_composite(l2, ((1280 - l2.width) // 2, (720 - l2.height) // 2))
    lib.save(os.path.join(out, "library_logo_1280x720.png"))
    print("saved to", out)


if __name__ == "__main__":
    main()
