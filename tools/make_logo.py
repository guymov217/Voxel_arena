#!/usr/bin/env python3
"""The WRECKSMITH logo: the name in Roman capitals built of real voxels (extruded, bevelled cubes
seen in perspective from a little below, lit by a warm key light and the forge's glow from
beneath), forged gold with a hammered face over a body of darker gold, the I a broad gladius
driven into the line, the H breaking apart into chunks flying off, embers rising off it; a dark
rim, halo and shadow so it reads on any picture, down to the store's smallest capsule. Drawn by
a small painter's-algorithm voxel renderer, no engine needed. Writes logo.png and
logo_stacked.png (the masters, transparent) and library_logo_1280x720.png. Needs Pillow and
numpy.

    python3 tools/make_logo.py [out dir] [width]"""
import math
import os
import random
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FONT = os.path.join(ROOT, "tools", "fonts", "Cinzel-Black.ttf")
TITLE = "WRECKSMITH"
SWORD_AT = 7        # the I of SMITH
CAP = 26            # letter height in voxels
DEPTH = 8           # how far the letters are extruded
SS = 3              # supersampling
SWORD_W = 19        # the gladius's width in voxels, guard to guard
DEBRIS = 26         # the pieces flying off the broken H
SPARKS = 48         # embers rising off it
LINE_GAP = 19       # between WRECK and SMITH stacked (the pommel stands in it)

# Materials: base colours (sRGB) of each voxel kind.
# Polished gold seen as metal is seen: what it mirrors. The sky's light at the top, a bright
# band, the dark of the stands at the horizon (a thin line: a broad dark band cut the letters in
# two at the store's small sizes), then the warm sand and the forge's fire below.
GOLD_STOPS = [(0.0, (255, 252, 226)), (0.08, (255, 236, 150)), (0.30, (250, 196, 76)), (0.44, (214, 140, 40)),
              (0.50, (150, 84, 20)), (0.54, (196, 116, 30)), (0.64, (246, 176, 58)), (0.80, (255, 160, 50)),
              (1.0, (255, 96, 28))]
STEEL = np.array([196, 206, 220])
STEEL_EDGE = np.array([236, 242, 248])
STEEL_FULLER = np.array([120, 132, 148])
LEATHER = np.array([96, 56, 30])
LEATHER_DARK = np.array([62, 34, 18])
RUBY = np.array([210, 24, 34])
BLOOD = np.array([150, 10, 14])
BLOOD_DARK = np.array([86, 6, 8])
IRON = (16, 10, 8)
SIDE_GOLD = np.array([168, 98, 34])   # the letters' sides and undersides: the gold's body in shadow


def letter_grid(stack=False):
    """The title rasterised on the voxel grid: per letter (name, x0, y0, cells), the cap height
    CAP cells, y down from the cap line; `stack` sets WRECK over SMITH."""
    size = 40
    while True:
        f = ImageFont.truetype(FONT, size)
        top = f.getbbox("H")[1]
        bottom = f.getbbox("H")[3]
        if bottom - top >= CAP:
            break
        size += 1
    track = 2
    letters = []
    lines = [list(range(len(TITLE)))] if not stack else [list(range(0, 5)), list(range(5, len(TITLE)))]
    widths = []
    for li, idx in enumerate(lines):
        x0 = 0
        y0 = li * (CAP + LINE_GAP)
        row = []
        for i in idx:
            ch = TITLE[i]
            w = int(math.ceil(f.getlength(ch)))
            if i == SWORD_AT:
                row.append(["sword", x0, y0, SWORD_W])
                x0 += SWORD_W + track
                continue
            img = Image.new("L", (w + 4, CAP + 12), 0)
            ImageDraw.Draw(img).text((2, 2 - top), ch, font=f, fill=255)
            a = np.array(img) > 120
            ys, xs = np.nonzero(a)
            minx = xs.min()
            cells = [(x0 + int(x) - minx, y0 + int(y) - 2) for y, x in zip(ys, xs)]
            width = int(xs.max() - minx + 1)
            row.append([ch, x0, y0, cells])
            x0 += width + track
        widths.append(x0 - track)
        letters.append(row)
    # Lines centred on the widest.
    W = max(widths)
    out = []
    for row, w in zip(letters, widths):
        dx = (W - w) // 2
        for e in row:
            e[1] += dx
            if e[0] != "sword":
                e[3] = [(x + dx, y) for x, y in e[3]]
            out.append(tuple(e))
    return out, W


def sword_cells(cx):
    """The gladius standing in for the I: a ruby-set pommel above the cap line, a leather grip, a
    broad gold guard, the blade (as broad as a letter's stem, so it still reads as the I at the
    smallest size) down through the baseline, blooded at the point. (x, y, kind)."""
    out = []
    def put(x, y, k):
        out.append((cx + x, y, k))
    for x in range(-2, 3):
        put(x, -13, "gold")
    for y in range(-12, -7):
        for x in range(-3, 4):
            if abs(x) == 3 and y in (-12, -8):
                continue
            put(x, y, "ruby" if abs(x) < 2 and -11 <= y <= -9 else "gold")
    for x in range(-2, 3):
        put(x, -7, "gold")
    for y in range(-6, 1):
        for x in (-1, 0, 1):
            put(x, y, "leather_dark" if (y + x) % 3 == 0 else "leather")
    for x in range(-9, 10):
        put(x, 1, "gold")
        put(x, 2, "gold")
    for x in range(-8, 9):
        put(x, 3, "gold")
    for x in (-9, 9):
        put(x, 0, "ruby")
    for y in range(4, CAP + 4):
        half = 4 if y < CAP - 5 else (3 if y < CAP - 2 else (2 if y < CAP + 1 else (1 if y < CAP + 3 else 0)))
        for x in range(-half, half + 1):
            k = "steel_fuller" if (abs(x) <= 1 and half >= 3 and y < CAP - 4) else ("steel_edge" if abs(x) == half and half > 0 else "steel")
            put(x, y, k)
    # Blooded: the last of the blade red, darker where it has dried.
    rng = random.Random(4)
    out = [(x, y, ("blood" if rng.random() < 0.75 else "blood_dark") if y >= CAP - 4 and (y >= CAP - 1 or rng.random() < 0.55) and k.startswith("steel") else k) for x, y, k in out]
    return out


def build(stack=False):
    letters, width = letter_grid(stack)
    vox = {}      # (x, y, z) -> kind
    local = {}    # (x, y) -> its height within its own line (for the gold's gradient)
    rng = random.Random(7)
    for entry in letters:
        if entry[0] == "sword":
            cx = entry[1] + SWORD_W // 2
            for x, y, k in sword_cells(cx):
                for z in range(0, 4):
                    vox[(x, y + entry[2], z + 1)] = k
                local[(x, y + entry[2])] = y
            continue
        for x, y in entry[3]:
            local[(x, y)] = y - entry[2]
            for z in range(DEPTH):
                vox[(x, y, z)] = "gold"
    # Battle-worn: a few notches knocked out of the letters' outer edges.
    edge = [p for p in vox if vox[p] == "gold" and p[2] == 0 and any((p[0] + dx, p[1] + dy, 0) not in vox for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)))]
    for p in rng.sample(edge, len(edge) // 28):
        for z in range(0, rng.randint(1, 3)):
            vox.pop((p[0], p[1], z), None)
    # The H breaks apart: its top right corner gone, flying off right and up as voxels.
    hx = letters[-1][1]
    hy = letters[-1][2]
    hcells = letters[-1][3]
    hw = max(c[0] for c in hcells) - hx + 1
    debris = []
    broken = []
    for (x, y, z), k in list(vox.items()):
        if x < hx or y < hy - 2:
            continue
        u = (x - hx) / hw
        v = (y - hy) / CAP
        # a jagged break across the top of the right stem: the H still an H
        if u > 0.64 and v < 0.13 + 0.38 * (u - 0.64) + 0.04 * math.sin(y * 2.3 + x * 1.3):
            vox.pop((x, y, z))
            broken.append((x, y, z, k))
    # The pieces: big ones close to the break, smaller the further they have flown.
    for i in range(DEBRIS):
        x, y, z, k = rng.choice(broken)
        t = (i + rng.random()) / DEBRIS * 8.5 + 0.6
        ang = math.radians(rng.uniform(-58, -6))
        debris.append({
            "p": (x + 2.5 + math.cos(ang) * t * 3.4, y - 1.0 + math.sin(ang) * t * 3.4 + 0.05 * t * t, z + rng.uniform(-1.2, 1.2) * t * 0.3),
            "rot": (rng.uniform(-1, 1) * (0.5 + t * 0.3), rng.uniform(-1, 1) * (0.5 + t * 0.3), rng.uniform(-1, 1) * (0.5 + t * 0.3)),
            "s": max(0.9, rng.uniform(2.0, 3.4) * (1.0 - t * 0.075)),
            "k": k})
    return vox, debris, width, local


def colour(kind, x, y, z, rng):
    if kind == "gold":
        v = min(1.0, max(0.0, (y + 0.5) / CAP))
        c = np.array(GOLD_STOPS[-1][1], dtype=float)
        for (a, ca), (b, cb) in zip(GOLD_STOPS, GOLD_STOPS[1:]):
            if a <= v <= b:
                u = (v - a) / (b - a)
                c = np.array(ca, dtype=float) + (np.array(cb, dtype=float) - np.array(ca, dtype=float)) * u
                break
        n = 1.0 + rng.uniform(-0.06, 0.06)       # hammered: every voxel its own
        return np.clip(c * n, 0, 255)
    table = {"steel": STEEL, "steel_edge": STEEL_EDGE, "steel_fuller": STEEL_FULLER, "leather": LEATHER, "leather_dark": LEATHER_DARK, "ruby": RUBY, "blood": BLOOD, "blood_dark": BLOOD_DARK}
    c = table[kind] * (1.0 + rng.uniform(-0.04, 0.04))
    if kind.startswith("steel"):
        v = min(1.0, max(0.0, (y - 4) / (CAP - 4)))
        c = c * (1.12 - 0.3 * v) + np.array([40, 60, 90]) * 0.25 * v
    return np.clip(c, 0, 255)


FACES = [
    ((0, 0, 1), [(0, 0, 1), (1, 0, 1), (1, 1, 1), (0, 1, 1)]),     # front (toward the camera, +z)
    ((0, 0, -1), [(1, 0, 0), (0, 0, 0), (0, 1, 0), (1, 1, 0)]),
    ((0, -1, 0), [(0, 0, 0), (1, 0, 0), (1, 0, 1), (0, 0, 1)]),    # top (y is down on the grid)
    ((0, 1, 0), [(0, 1, 1), (1, 1, 1), (1, 1, 0), (0, 1, 0)]),
    ((-1, 0, 0), [(0, 0, 0), (0, 0, 1), (0, 1, 1), (0, 1, 0)]),
    ((1, 0, 0), [(1, 0, 1), (1, 0, 0), (1, 1, 0), (1, 1, 1)]),
]


def render(out_w, stack=False):
    vox, debris, width, local = build(stack)
    lines = 2 if stack else 1
    rng = random.Random(11)
    # World: x right, y up, z toward the camera. Grid y is down, so world y = -y.
    cx = width / 2.0
    cy = -(CAP * lines + LINE_GAP * (lines - 1)) / 2.0 + 1.5
    # Square on and seen a little from below: the letters stand over you on a dark base of their
    # own undersides, lit by the forge. (Seen from above and turned, the lit tops and sides of
    # every voxel step ran along the letters' edges like a saw.)
    yaw = 0.0
    pitch = math.radians(-13.0)
    cam_dist = width * 1.55
    f = cam_dist * 1.0

    def world(p):
        x, y, z = p[0] - cx, -(p[1]) - cy, p[2] - DEPTH * 0.5
        # turn the word: yaw about y, then tilt
        x, z = x * math.cos(yaw) + z * math.sin(yaw), -x * math.sin(yaw) + z * math.cos(yaw)
        y, z = y * math.cos(pitch) - z * math.sin(pitch), y * math.sin(pitch) + z * math.cos(pitch)
        return (x, y, z)

    def project(w):
        x, y, z = w
        d = cam_dist - z
        return (f * x / d, -f * y / d, d)

    key = np.array([-0.45, 0.75, 0.55])
    key = key / np.linalg.norm(key)
    fill = np.array([0.7, 0.1, 0.5])
    fill = fill / np.linalg.norm(fill)
    glow = np.array([0.2, -0.9, 0.4])
    glow = glow / np.linalg.norm(glow)

    def rot_normal(n):
        x, y, z = n[0], -n[1], n[2]
        x, z = x * math.cos(yaw) + z * math.sin(yaw), -x * math.sin(yaw) + z * math.cos(yaw)
        y, z = y * math.cos(pitch) - z * math.sin(pitch), y * math.sin(pitch) + z * math.cos(pitch)
        return np.array([x, y, z])

    def shade(base, n, front):
        lam = max(0.0, float(np.dot(n, key)))
        c = base * (0.32 + 0.78 * lam) + np.array([255, 236, 210]) * 0.05 * lam
        c = c + np.array([110, 150, 210]) * 0.10 * max(0.0, float(np.dot(n, fill)))
        c = c + np.array([255, 110, 30]) * 0.34 * max(0.0, float(np.dot(n, glow)))
        if front:
            c = c * 1.04
        return np.clip(c, 0, 255)

    polys = []     # (depth, points, colour, bevel)
    for (x, y, z), kind in vox.items():
        base = colour(kind, x, local.get((x, y), y), z, rng)
        for (nx, ny, nz), corners in FACES:
            if (x + nx, y + ny, z + nz) in vox:
                continue
            fb = base
            if kind == "gold" and nz != 1:    # darker toward the back, so the face stands clear of it
                fb = SIDE_GOLD * (0.62 + 0.38 * z / max(1, DEPTH - 1)) * (1.0 + rng.uniform(-0.03, 0.03))
            n = rot_normal((nx, ny, nz))
            centre = world((x + 0.5 + nx * 0.5, y + 0.5 + ny * 0.5, z + 0.5 + nz * 0.5))
            to_cam = np.array([-centre[0], -centre[1], cam_dist - centre[2]])
            if float(np.dot(n, to_cam)) <= 0:
                continue
            pts = [project(world((x + a, y + b, z + c))) for a, b, c in corners]
            polys.append((sum(p[2] for p in pts) / 4.0, [(p[0], p[1]) for p in pts], shade(fb, n, nz == 1), nz == 1))
    # The flying voxels: rotated cubes.
    for d in debris:
        base = colour(d["k"], d["p"][0], rng.uniform(0.35, 0.95) * CAP, 0, rng)
        if rng.random() < 0.3:
            base = np.clip(base * 0.6 + np.array([255, 110, 30]) * 0.5, 0, 255)
        rx, ry, rz = d["rot"]
        s = d["s"]
        def rot(v):
            x, y, z = v
            y, z = y * math.cos(rx) - z * math.sin(rx), y * math.sin(rx) + z * math.cos(rx)
            x, z = x * math.cos(ry) + z * math.sin(ry), -x * math.sin(ry) + z * math.cos(ry)
            x, y = x * math.cos(rz) - y * math.sin(rz), x * math.sin(rz) + y * math.cos(rz)
            return (x, y, z)
        px, py, pz = d["p"]
        for (nx, ny, nz), corners in FACES:
            nr = rot((nx, ny, nz))
            n = rot_normal(nr)
            cc = rot((nx * 0.5 * s, ny * 0.5 * s, nz * 0.5 * s))
            centre = world((px + 0.5 + cc[0], py + 0.5 + cc[1], pz + 0.5 + cc[2]))
            to_cam = np.array([-centre[0], -centre[1], cam_dist - centre[2]])
            if float(np.dot(n, to_cam)) <= 0:
                continue
            pts = []
            for a, b, c in corners:
                v = rot(((a - 0.5) * s, (b - 0.5) * s, (c - 0.5) * s))
                pts.append(project(world((px + 0.5 + v[0], py + 0.5 + v[1], pz + 0.5 + v[2]))))
            polys.append((sum(p[2] for p in pts) / 4.0, [(p[0], p[1]) for p in pts], shade(base, n, False), True))
    polys.sort(key=lambda q: -q[0])
    xs = [p[0] for q in polys for p in q[1]]
    ys = [p[1] for q in polys for p in q[1]]
    minx, maxx, miny, maxy = min(xs), max(xs), min(ys), max(ys)
    margin = 0.08
    scale = float(out_w * SS * (1 - 2 * margin) / (maxx - minx))
    W = out_w * SS
    H = int((maxy - miny) * scale + W * margin * 1.3)
    ox = W * margin - minx * scale
    oy = (H - (maxy - miny) * scale) / 2 - miny * scale
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    for depth, pts, col, bevel in polys:
        P = [(ox + x * scale, oy + y * scale) for x, y in pts]
        c = tuple(int(v) for v in col) + (255,)
        d.polygon(P, fill=c)
        if bevel:
            # A bevel on every face: lit along its upper and left edges, dark along the others (soft:
            # the voxels show close up, and the letter still reads whole at the smallest size).
            hi = tuple(int(min(255, v * 1.16 + 12)) for v in col) + (255,)
            lo = tuple(int(v * 0.68) for v in col) + (255,)
            lw = max(1, int(scale * 0.07))
            d.line([P[3], P[0], P[1]], fill=hi, width=lw)
            d.line([P[1], P[2], P[3]], fill=lo, width=lw)
        else:
            lo = tuple(int(v * 0.86) for v in col) + (255,)
            d.line(P + [P[0]], fill=lo, width=max(1, int(scale * 0.03)))
    return img, scale


def sparks(size, scale, rng, box):
    """Embers rising off the logo, thickest about the breaking H, none far from the letters (the
    logo is cropped to what it draws: a stray ember high above would shrink it in every
    capsule): bright cores in a glow. `box`: the letters' bounds."""
    x0, y0, x1, y1 = box
    w, h = x1 - x0, y1 - y0
    layer = Image.new("RGBA", size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    for i in range(SPARKS):
        if rng.random() < 0.75:
            x = x1 - w * rng.uniform(-0.02, 0.13)
            y = y0 + h * rng.uniform(-0.12, 0.55)
        else:
            x = x0 + w * rng.uniform(0.04, 0.92)
            y = y0 - h * rng.uniform(0.0, 0.14)
        s = rng.uniform(0.25, 0.6) * scale
        col = rng.choice([(255, 210, 120), (255, 160, 60), (255, 120, 40), (255, 236, 170)])
        a = int(rng.uniform(150, 255))
        if rng.random() < 0.35:
            d.line([(x, y), (x - rng.uniform(-0.3, 0.3) * scale, y + rng.uniform(1.0, 2.6) * scale)], fill=col + (int(a * 0.7),), width=max(1, int(s * 0.6)))
        d.rectangle([x - s / 2, y - s / 2, x + s / 2, y + s / 2], fill=col + (a,))
    glow = layer.filter(ImageFilter.GaussianBlur(scale * 0.7))
    return Image.alpha_composite(glow, layer)


def glints(size, scale, rng, spots):
    layer = Image.new("RGBA", size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    for x, y in spots:
        r = scale * rng.uniform(1.6, 2.6)
        w = max(1, int(scale * 0.22))
        d.line([(x - r, y), (x + r, y)], fill=(255, 250, 225, 230), width=w)
        d.line([(x, y - r), (x, y + r)], fill=(255, 250, 225, 230), width=w)
        d.line([(x - r * 0.4, y - r * 0.4), (x + r * 0.4, y + r * 0.4)], fill=(255, 240, 200, 170), width=max(1, w // 2))
        d.line([(x - r * 0.4, y + r * 0.4), (x + r * 0.4, y - r * 0.4)], fill=(255, 240, 200, 170), width=max(1, w // 2))
    glow = layer.filter(ImageFilter.GaussianBlur(scale * 0.5))
    return Image.alpha_composite(glow, layer)


def grow(a, k):
    """The alpha grown by a k x k square (a max filter, done along each axis with numpy: PIL's
    MaxFilter takes minutes at the master's size)."""
    m = np.array(a)
    r = k // 2
    for axis in (0, 1):
        out = m.copy()
        n = m.shape[axis]
        for d in range(1, r + 1):
            if axis == 0:
                np.maximum(out[d:], m[:n - d], out=out[d:])
                np.maximum(out[:n - d], m[d:], out=out[:n - d])
            else:
                np.maximum(out[:, d:], m[:, :n - d], out=out[:, d:])
                np.maximum(out[:, :n - d], m[:, d:], out=out[:, :n - d])
        m = out
    return Image.fromarray(m)


def finish(img, scale):
    """The outline that keeps it readable on any picture, a drop shadow and the forge's glow."""
    a = img.split()[3]
    rim_a = grow(a, int(scale * 1.3) | 1)
    rim = Image.new("RGBA", img.size, IRON + (0,))
    rim.putalpha(rim_a.point(lambda v: int(v * 0.96)))
    shadow = Image.new("RGBA", img.size, (0, 0, 0, 0))
    sh = rim_a.filter(ImageFilter.GaussianBlur(scale * 1.6)).point(lambda v: int(v * 0.8))
    shadow.paste(Image.new("RGBA", img.size, (0, 0, 0, 255)), (int(scale * 0.5), int(scale * 1.2)), sh)
    # A dark halo, so the gold stands on the bright sand and sky as well as on the stands.
    halo_a = grow(rim_a, int(scale * 2.0) | 1).filter(ImageFilter.GaussianBlur(scale * 3.0)).point(lambda v: int(v * 0.5))
    halo = Image.new("RGBA", img.size, (14, 7, 4, 0))
    halo.putalpha(halo_a)
    glow_a = rim_a.filter(ImageFilter.GaussianBlur(scale * 2.2)).point(lambda v: int(v * 0.22))
    glow = Image.new("RGBA", img.size, (255, 120, 36, 0))
    glow.putalpha(glow_a)
    out = Image.alpha_composite(halo, glow)
    out = Image.alpha_composite(out, shadow)
    out = Image.alpha_composite(out, rim)
    out = Image.alpha_composite(out, img)
    out = Image.alpha_composite(out, sparks(img.size, scale, random.Random(3), a.point(lambda v: 255 if v > 128 else 0).getbbox()))
    # Light caught on the upper left corners of a few letters.
    a2 = np.array(img.split()[3]) > 128
    rows = np.nonzero(a2.any(axis=1))[0]
    top = rows.min() + (rows.max() - rows.min()) * 0.22
    cols = np.nonzero(a2[int(top)])[0]
    rng = random.Random(5)
    spots = []
    if len(cols):
        for fx in (0.08, 0.43, 0.71):
            c = cols[min(len(cols) - 1, int(len(cols) * fx))]
            spots.append((float(c), float(top)))
    out = Image.alpha_composite(out, glints(img.size, scale, rng, spots))
    return out


def main():
    out_dir = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "docs", "store", "capsules")
    width = int(sys.argv[2]) if len(sys.argv) > 2 else 3200
    os.makedirs(out_dir, exist_ok=True)
    for stack, name in ((True, "logo_stacked.png"), (False, "logo.png")):
        img, scale = render(width, stack)
        img = finish(img, scale)
        img = img.resize((width, int(img.height * width / img.width)), Image.LANCZOS)
        bbox = img.split()[3].point(lambda v: 255 if v > 8 else 0).getbbox()
        img = img.crop(bbox)
        img.save(os.path.join(out_dir, name))
    # The library logo: the logo alone on a transparent 1280x720, as Steam lays it over the hero.
    lib = Image.new("RGBA", (1280, 720), (0, 0, 0, 0))
    k = min(1180 / img.width, 600 / img.height)
    small = img.resize((int(img.width * k), int(img.height * k)), Image.LANCZOS)
    lib.alpha_composite(small, ((1280 - small.width) // 2, (720 - small.height) // 2))
    lib.save(os.path.join(out_dir, "library_logo_1280x720.png"))
    print("logo", img.size, "->", out_dir)


if __name__ == "__main__":
    main()
