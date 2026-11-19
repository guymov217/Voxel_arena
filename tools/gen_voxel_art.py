"""Makes the arena's voxel art (art/voxel/*.glb, art/textures/sand_voxel.png): the bowl itself
(podium wall, stands, aisles, the two gatehouses, the Emperor's box, the arcade) as world-aligned
10 cm voxels, the props (braziers, gates, statues, amphorae, the yard's stations...) as 5 cm
voxels, and the smithy the forge's anvil stands in (forge_room: its floor, walls and roof; the
hearth, the bellows and the rest of what stands in it). Every model is built from code, so it can
be changed and rebuilt:

    pip install numpy numba pillow
    python3 tools/gen_voxel_art.py            # everything
    python3 tools/gen_voxel_art.py brazier    # one model (forge_room: the smithy's room)

The look: per-block colour, a little per-voxel variation, baked corner occlusion, a handful of
materials with their own shading (scripts/game/voxel_art.gd). The game reads the layout numbers
below from arena.gd too; keep them in step.
"""
import math
import os
import sys
import time

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(__file__))
import voxlib as V  # noqa: E402
from voxlib import hash3, vnoise, tint, pack  # noqa: E402

ROOT = os.path.join(os.path.dirname(__file__), "..")
OUT = os.path.join(ROOT, "art", "voxel")

# ---- the arena's layout (arena.gd uses the same numbers) ----
R = 15.0                       # the sand's radius
TIER_R0, TIER_DR = 16.4, 1.3   # tier t's middle radius: TIER_R0 + t * TIER_DR
TIER_Y0, TIER_DY = 2.6, 0.7    # tier t's seat height: TIER_Y0 + t * TIER_DY
TIERS = 6
TOP_R = 24.1                   # the arcade's columns
WALK_Y = TIER_Y0 + (TIERS - 1) * TIER_DY   # 6.1
COLS = 48

# ---- palette (sRGB) ----
TRAVERTINE = (0.80, 0.73, 0.60)
TRAV_DARK = (0.66, 0.59, 0.48)
MARBLE = (0.91, 0.89, 0.84)
RED = (0.58, 0.16, 0.11)
PURPLE = (0.38, 0.11, 0.36)
GOLD = (0.95, 0.74, 0.30)
BRONZE = (0.62, 0.42, 0.22)
IRON = (0.24, 0.23, 0.22)
WOOD = (0.52, 0.34, 0.19)
WOOD_DARK = (0.36, 0.23, 0.13)
TERRA = (0.72, 0.40, 0.22)
CREAM = (0.90, 0.84, 0.70)
STRAW = (0.85, 0.72, 0.40)
SAND = (0.87, 0.75, 0.56)


def dang(th, step, off=0.0):
    """Angle from the nearest of off + k * step, in (-step/2, step/2]."""
    return np.mod(th - off + step / 2, step) - step / 2


def ashlar(mat, base, bl=0.6, bh=0.3, var=0.07, seed=1, dirt=0.0, mortar=0.84, vs=0.1, radial=True, streak=0.0, damp=0.0):
    """Dressed stone: staggered blocks bl x bh, each its own shade, darker mortar joints,
    blotches of weathering, (dirt) sand splashed up the lowest half metre, (streak) grime run
    down the face in long thin streaks where the rain went, and (damp) the dark of damp stone at
    its foot. The streaks and the damp come in a few steps, not a smooth ramp, so flat runs of
    one colour still merge into big quads."""
    def f(ix, iy, iz, x, y, z):
        if radial:
            r = np.sqrt(x * x + z * z)
            s = np.arctan2(x, z) * r
        else:
            s = x + z
        row = np.floor(y / bh)
        sh = s + np.mod(row, 2) * bl * 0.5
        b = np.floor(sh / bl)
        within = sh - b * bl
        jy = y - row * bh
        n_block = hash3(b.astype(np.int64), row.astype(np.int64), 0, seed)
        # Weathering per block (its middle), not per voxel: the shader adds the per-voxel grain,
        # and flat runs of one colour merge into big quads.
        r_ = np.sqrt(x * x + z * z) if radial else 1.0
        bx = (b + 0.5) * bl
        n_big = vnoise(bx, (row + 0.5) * bh, r_ * 0 + (seed % 7), 1.7, seed + 3)
        c = tint(base, var, n_block) * tint((1, 1, 1), 0.07, n_big)
        if PER_VOX[0]:
            c *= tint((1, 1, 1), 0.025, hash3(ix, iy, iz, seed + 7))
        joint = (within < vs * 0.99) | (jy < vs * 0.99)
        c[joint] *= mortar
        if dirt > 0:
            k = np.clip((0.6 - y) / 0.6, 0, 1) * dirt * (0.6 + 0.8 * hash3(b.astype(np.int64), row.astype(np.int64), 1, seed + 5))
            c = c * (1 - k[:, None]) + np.array([0.55, 0.43, 0.30])[None, :] * k[:, None]
        if streak > 0:
            # Long thin streaks: noise stretched up and down (a lattice 0.25 m across, 1.6 m tall).
            st = vnoise(s / 0.25, y / 1.6, (seed % 5) * 3.0, 1.0, seed + 11)
            k = np.round(np.clip((st - 0.6) / 0.25, 0, 1) * 3) / 3 * streak
            c = c * (1 - 0.2 * k[:, None]) * np.array([0.98, 0.97, 0.95])[None, :] ** k[:, None]
        if damp > 0:
            k = np.round(np.clip((0.35 - y) / 0.35, 0, 1) * 3) / 3 * damp
            c = c * (1 - k[:, None] * 0.45) + np.array([0.30, 0.29, 0.22])[None, :] * (k[:, None] * 0.45)
        return pack(mat, c)
    return f


def ashlar_joints(x, y, z, bl, bh, radial=True):
    """Where a voxel sits among ashlar's blocks: how far along its block (m) and up its course
    (m), and the block and course it is in (the same layout as ashlar())."""
    if radial:
        r = np.sqrt(x * x + z * z)
        s = np.arctan2(x, z) * r
    else:
        s = x + z
    row = np.floor(y / bh)
    sh = s + np.mod(row, 2) * bl * 0.5
    b = np.floor(sh / bl)
    return sh - b * bl, y - row * bh, b, row


def chip(s, region, bl, bh, seed, p_corner=0.45, p_edge=0.05, radial=True):
    """Knocks chips out of dressed stone (only its look: the arena's walls are their own boxes):
    the voxel where four blocks meet often, one along a joint now and then. (Worked out for the
    voxels of `region` alone: over the whole grid it would take gigabytes.)"""
    idx = np.nonzero(region & (s.c != 0))
    if len(idx[0]) == 0:
        return
    vs = s.vs
    x = s.lo[0] + (idx[0] + 0.5) * vs
    y = s.lo[1] + (idx[1] + 0.5) * vs
    z = s.lo[2] + (idx[2] + 0.5) * vs
    within, jy, b, row = ashlar_joints(x, y, z, bl, bh, radial)
    h = hash3(idx[0], idx[1], idx[2], seed)
    corner = (within < vs * 0.99) & (jy < vs * 0.99) & (h < p_corner)
    edge = ((within < vs * 0.99) | (jy < vs * 0.99)) & (h < p_edge)
    hit = corner | edge
    s.c[idx[0][hit], idx[1][hit], idx[2][hit]] = 0


PER_VOX = [True]   # off for the bowl: the shader's grain is enough there, and quads merge


def plain(mat, base, var=0.04, big=0.05, seed=2):
    def f(ix, iy, iz, x, y, z):
        if not PER_VOX[0]:
            n = vnoise(np.floor(x / 0.5), np.floor(y / 0.5), np.floor(z / 0.5), 1.0, seed)
            return pack(mat, tint(base, big + var, np.round(n * 4) / 4))
        c = tint(base, var, hash3(ix, iy, iz, seed)) * tint((1, 1, 1), big, vnoise(x, y, z, 0.9, seed))
        return pack(mat, c)
    return f


def planks(mat, base, along=1, width=0.15, var=0.12, seed=4, vs=0.05, post=None):
    """Boards running along axis `along`, `width` wide across the other horizontal axis, each
    its own shade, with the grain in it (lanes of darker and paler wood wandering a voxel this way
    and that along the board), a knot now and then, greyer where the weather got at it, and a dark
    seam between boards. `post(c, x, y, z)` may stain the colours after (rust run down from iron)."""
    def f(ix, iy, iz, x, y, z):
        idx = (ix, iy, iz)
        pos = (x, y, z)
        across = pos[2] if along != 2 else pos[0]
        if along == 2:
            across = pos[0] + pos[1] * 0.0
        al = pos[along]
        b = np.floor(across / width)
        bi = b.astype(np.int64)
        n_b = hash3(bi, 0, 0, seed)
        lane = idx[2] if along != 2 else idx[0]
        wander = np.floor(vnoise(al, 0 * al, b * 3.1, 0.35, seed + 3) * 2.0).astype(np.int64)
        g = hash3(lane + wander, 0, bi, seed + 1)
        shade = 1.0 - 0.14 * (g < 0.28) + 0.06 * (g > 0.86)
        c = tint(base, var, n_b) * shade[:, None] * tint((1, 1, 1), 0.03, hash3(*idx, seed + 2))
        # Knots: a dark heart and a ring round it, one in a stretch of board now and then.
        kw = min(width, 0.3)
        kb = np.floor(across / kw)
        cell = np.floor(al / 0.6).astype(np.int64)
        kbi = kb.astype(np.int64)
        kx = (cell + 0.2 + 0.6 * hash3(cell, kbi, 0, seed + 5)) * 0.6
        ky = (kb + 0.3 + 0.4 * hash3(cell, kbi, 1, seed + 5)) * kw
        kd = np.sqrt((al - kx) ** 2 + ((across - ky) * 1.6) ** 2)
        knot = hash3(cell, kbi, 2, seed + 5) < 0.35
        c[knot & (kd < 0.035)] *= 0.55
        c[knot & (kd >= 0.035) & (kd < 0.075)] *= 0.82
        # Weathered: greyer in patches.
        w = np.clip((vnoise(x, y, z, 0.45, seed + 6) - 0.55) * 2.5, 0.0, 0.35)
        lum = (c @ np.array([0.3, 0.55, 0.15], np.float32))[:, None]
        c = c * (1 - w[:, None]) + lum * np.array([[0.95, 0.93, 0.9]], np.float32) * w[:, None]
        if vs > 0:
            seam = (across - b * width) < vs * 0.99
            c[seam] *= 0.7
        if post is not None:
            c = post(c, x, y, z)
        return pack(mat, c)
    return f


def grain(mat, base, along=1, var=0.06, seed=5):
    """Wood in one piece (a post, a shaft, a beam): the grain along it, knots, no seams."""
    return planks(mat, base, along=along, width=100.0, var=var, seed=seed, vs=0.0)


RUST = (0.44, 0.21, 0.1)
VERDIGRIS = (0.29, 0.40, 0.33)


def rusty(base, seed=0, amount=0.42, scale=0.12):
    """Iron gone to rust in patches (a rough, dull orange-brown: its own material), dark pits in
    the bare metal, the bare metal itself a little uneven."""
    def f(ix, iy, iz, x, y, z):
        h = hash3(ix, iy, iz, seed)
        c = tint(base, 0.05, h) * tint((1, 1, 1), 0.1, vnoise(x, y, z, 0.5, seed + 1))
        n = vnoise(x, y, z, scale, seed + 2) * 0.8 + 0.2 * hash3(ix, iy, iz, seed + 3)
        r = n > 1.0 - amount
        rc = tint(RUST, 0.18, hash3(ix, iy, iz, seed + 4)) * tint((1, 1, 1), 0.12, vnoise(x, y, z, 0.05, seed + 5))
        c[(h < 0.06) & ~r] *= 0.55
        out = pack("iron", c)
        out[r] = pack("rust", rc[r])
        return out
    return f


def patina(base, seed=0, amount=0.3, scale=0.1):
    """Bronze gone green in patches, most of all low down where the wet lies."""
    def f(ix, iy, iz, x, y, z):
        c = tint(base, 0.05, hash3(ix, iy, iz, seed)) * tint((1, 1, 1), 0.12, vnoise(x, y, z, 0.3, seed + 1))
        n = vnoise(x, y, z, scale, seed + 2) * 0.88 + 0.12 * hash3(ix, iy, iz, seed + 3) + 0.3 * np.clip(0.45 - y, 0.0, 0.45)
        g = n > 1.0 - amount
        gc = tint(VERDIGRIS, 0.15, hash3(ix, iy, iz, seed + 4))
        out = pack("bronze", c)
        out[g] = pack("rust", gc[g])
        return out
    return f


# ---- a tiny pixel font for inscriptions ----
FONT = {
    "S": ["111", "100", "111", "001", "111"], "P": ["111", "101", "111", "100", "100"],
    "Q": ["111", "101", "101", "111", "001"], "R": ["110", "101", "110", "101", "101"],
    "V": ["101", "101", "101", "101", "010"], "M": ["101", "111", "111", "101", "101"],
    "N": ["101", "111", "111", "111", "101"], "E": ["111", "100", "110", "100", "111"],
    "A": ["010", "101", "111", "101", "101"], " ": ["000", "000", "000", "000", "000"],
}


def text_cells(text):
    """Set (col, row) pixels of `text`, row 0 at the top, 4 columns a letter."""
    out = set()
    for i, ch in enumerate(text):
        for row, bits in enumerate(FONT[ch]):
            for col, bit in enumerate(bits):
                if bit == "1":
                    out.add((i * 4 + col, row))
    return out, len(text) * 4 - 1


# ====================================================================== the frescoes

# Pictures on the podium's panels (9 voxels high, 10 cm each), top row first: k a dark umber
# line, s the pale grey of a blade, o ochre, w white, g laurel green, y gold, r the dark red of the
# ground's shade. Painted as the Romans did, flat colour on red.
MOTIFS = {
    "gladiators": [
        "...o.........o...",
        "..ooo.......ooo..",
        "..wws.......sww..",
        "y.wwws.....swwwyy",
        "yykwwws...swwwkyy",
        "yy.ww..s.s..ww.yy",
        "...ww...s...ww...",
        "..w..w.....w..w..",
        ".w....w...w....w.",
    ],
    "lion": [
        "...........",
        "...........",
        "......ooo..",
        ".....ooooo.",
        "o..ooooooko",
        ".oooooooooo",
        "..oo.oo.oo.",
        "..o..o..o..",
        "...........",
    ],
    "wreath": [
        "...ggggg...",
        "..g.....g..",
        ".g.......g.",
        "g....y....g",
        "g...yyy...g",
        "g....y....g",
        ".g.......g.",
        "..g.....g..",
        "...yy.yy...",
    ],
    "shield": [
        "s.......s",
        ".s.ooo.s.",
        "..soooso.",
        ".oookooo.",
        ".ooyyyoo.",
        ".oookooo.",
        "..soooso.",
        ".s.ooo.s.",
        "s.......s",
    ],
    "palm": [
        ".g.g.g.",
        "g.ggg.g",
        "..ggg..",
        "g.ggg.g",
        "...o...",
        "...o...",
        "...o...",
        "...o...",
        "..ooo..",
    ],
}
FRESCO_COL = {"k": (0.22, 0.09, 0.06), "s": (0.68, 0.66, 0.60), "o": (0.82, 0.60, 0.24), "w": (0.88, 0.82, 0.68),
              "g": (0.30, 0.42, 0.22), "y": (0.95, 0.74, 0.30), "r": (0.40, 0.10, 0.07)}
FRESCO_ORDER = ["gladiators", "lion", "wreath", "shield", "palm", "lion", "gladiators", "wreath"]


def fresco(ix, iy, iz, x, y, z):
    """A painted panel of the podium (between two pilasters, 15 degrees of the wall): Pompeian
    red with a darker band at its foot and a deep red one under its gilt top; where no banner
    hangs, a picture in the middle (gladiators, a lion, a wreath, a shield on crossed swords, a
    palm); and the wear of years in the arena: the plaster flaking off in patches, cracks, old
    blood splashed up from the sand, the scratches of blades."""
    th = np.arctan2(x, z)
    step = math.radians(15)
    k = np.floor(th / step).astype(np.int64)
    u = np.floor((th - k * step) * 15.0 / 0.1).astype(np.int64)    # 0..38 across the panel
    v = np.round((y - 0.6) / 0.1 - 0.5).astype(np.int64)             # 0 (foot) .. 8 (top)
    n = len(x)
    c = tint(RED, 0.04, hash3(ix, iy, iz, 300)) * tint((1, 1, 1), 0.06, vnoise(th * 15.0, y, 0, 0.6, 301))
    c[v <= 0] *= 0.62                       # the band at the foot, darker
    c[v >= 8] *= 0.5                        # the deep red band under the gilt
    # The picture, on the panels without a banner in the middle (odd ones), centred.
    odd = np.mod(k, 2) == 1
    width = 39
    painted = np.zeros(n, bool)
    for idx, name in enumerate(MOTIFS):
        pat = MOTIFS[name]
        h, w = len(pat), len(pat[0])
        which = np.array([FRESCO_ORDER[((i + 12) // 2) % len(FRESCO_ORDER)] == name for i in range(-12, 12)])
        sel = odd & which[np.clip(k + 12, 0, 23)]
        pu = u - (width - w) // 2
        pv = (h - 1) - v
        inside = sel & (pu >= 0) & (pu < w) & (pv >= 0) & (pv < h)
        for i in np.nonzero(inside)[0]:
            ch = pat[pv[i]][pu[i]]
            if ch in FRESCO_COL:
                c[i] = FRESCO_COL[ch]
                painted[i] = True
    # Wear: plaster flaked off (the pale lime under it), cracks, old blood, blade scratches.
    flake = vnoise(th * 15.0 / 0.35, y / 0.3, 7.0, 1.0, 302)
    off = (flake > np.where(painted, 0.88, 0.8)) & (v > 0)
    c[off] = np.array([0.80, 0.73, 0.60]) * (0.95 + 0.1 * hash3(ix[off], iy[off], 0, 303))[:, None]
    crack_line = np.abs(v - (3 + np.round(2.5 * np.sin(u * 0.45 + k * 1.7)))) < 0.5
    crack = crack_line & (hash3(k, 0, 0, 304) < 0.5) & (u > 4 + np.mod(k * 7, 11)) & (u < 18 + np.mod(k * 5, 13))
    c[crack] = np.array([0.22, 0.07, 0.05])
    blood = (vnoise(th * 15.0 / 0.25, y / 0.2, 3.0, 1.0, 305) > 0.66) & (v <= 3) & (hash3(k, 1, 0, 306) < 0.6)
    drip = (np.mod(u * 7 + k * 3, 11) == 0) & (v <= 4) & (hash3(k, u, 0, 307) < 0.35)
    c[blood | drip] = c[blood | drip] * 0.35 + np.array([0.24, 0.04, 0.03]) * 0.65
    scr = (np.mod(u - v, 9) == 0) & (hash3(k, np.floor(u / 9).astype(np.int64), 0, 308) < 0.3) & (v >= 2) & (v <= 6)
    c[scr] = c[scr] * 0.6 + np.array([0.85, 0.72, 0.62]) * 0.4
    return pack("plaster", c)


# ====================================================================== the bowl

def build_arena():
    PER_VOX[0] = False
    vs = 0.1
    s = V.Sculpt(vs, (-25.6, 0.0, -25.6), (25.6, 12.4, 25.6))
    x, y, z = s.grids()
    r = np.sqrt(x * x + z * z)
    th = np.arctan2(x, z)
    Y = y

    def band(r0, r1):
        return (r >= r0) & (r < r1)

    # -- the stands: six stepped tiers, then the walkway under the arcade.
    for t in range(TIERS):
        rr = TIER_R0 + t * TIER_DR
        r0 = rr - TIER_DR / 2 if t else 15.75
        r1 = rr + TIER_DR / 2 if t < TIERS - 1 else 24.7
        top = TIER_Y0 + t * TIER_DY
        s.put(band(r0, r1) & (Y < top - vs), ashlar("stone", TRAV_DARK, 1.0, 0.35, 0.1, seed=10 + t, streak=0.7))
        # The seat: a lighter slab with its own joints, a worn front edge.
        s.put(band(r0, r1) & (Y >= top - vs) & (Y < top), ashlar("stone", (0.86, 0.80, 0.68), 0.9, 1.0, 0.07, seed=20 + t, mortar=0.9))
        lip = band(r0, r0 + vs) & (Y >= top - vs) & (Y < top)
        s.carve(lip & (hash3(np.floor(th * r0 / vs).astype(np.int64), t, 0, 210 + t) < 0.14))
    # -- twelve aisles of stairs (half steps), clear of the gates and the Emperor's box.
    aisle = np.abs(dang(th, math.radians(30), math.radians(15))) * r < 0.45
    for t in range(TIERS):
        rr = TIER_R0 + t * TIER_DR
        top = TIER_Y0 + t * TIER_DY
        prev = TIER_Y0 + (t - 1) * TIER_DY if t else 2.0
        r0 = rr - TIER_DR / 2 if t else 15.75
        lo_half = band(r0, rr) & aisle
        hi_half = band(rr, rr + TIER_DR / 2) & aisle
        s.carve(lo_half & (Y >= prev + 0.4))
        s.recolor(lo_half & (Y >= prev + 0.3) & (Y < prev + 0.4), plain("stone", (0.70, 0.64, 0.55), seed=30))
        s.recolor(hi_half & (Y >= top - vs) & (Y < top), plain("stone", (0.70, 0.64, 0.55), seed=31))

    # -- the podium wall round the sand.
    wall = band(15.0, 15.8) & (Y < 2.0)
    s.put(wall, ashlar("stone", TRAVERTINE, 0.6, 0.3, 0.1, seed=1, dirt=0.55, streak=1.0, damp=0.6))
    s.put(band(14.9, 15.0) & (Y < 0.3), ashlar("stone", (0.62, 0.56, 0.47), 0.8, 0.3, 0.1, seed=2, dirt=0.4, damp=0.8))
    chip(s, band(14.9, 15.0) & (Y < 0.3), 0.8, 0.3, 201, 0.5, 0.06)
    s.put(band(14.9, 15.9) & (Y >= 1.8) & (Y < 2.0), ashlar("marble", MARBLE, 1.2, 0.2, 0.04, seed=3, mortar=0.9))
    arc = th * 15.0
    pil_d = np.abs(dang(th, math.radians(15))) * 15.0
    pilaster = band(14.9, 15.0) & (Y >= 0.3) & (Y < 1.8) & (pil_d < 0.25)
    s.put(pilaster, ashlar("marble", MARBLE, 2.0, 0.5, 0.04, seed=4, dirt=0.3, mortar=0.92))
    s.put(band(14.85, 14.9) & (Y >= 1.6) & (Y < 1.8) & (pil_d < 0.3), pack("marble", MARBLE))
    # Painted panels between the pilasters, gold-edged; on every other one a hanging banner.
    panel = band(15.0, 15.1) & (Y >= 0.5) & (Y < 1.6) & (pil_d > 0.35)
    edge = (Y < 0.6) | (Y >= 1.5) | (pil_d < 0.45)
    s.put(panel & ~edge, fresco)
    s.put(panel & edge, plain("gold", GOLD, 0.03, 0.03, seed=6))
    pc = dang(th, math.radians(30), math.radians(7.5)) * 15.0      # from the banner's middle
    ban_idx = np.floor((th - math.radians(7.5) + math.radians(15)) / math.radians(30)).astype(int)
    banner = band(14.9, 15.0) & (Y >= 0.7) & (Y < 1.75) & (np.abs(pc) < 0.35)
    emblem = (np.abs(pc) + np.abs(Y - 1.3) * 1.2) < 0.17
    fringe = (Y < 0.8) & (np.mod(np.floor(arc / vs), 2) == 0)
    s.put(banner & ~fringe & ~emblem & (np.mod(ban_idx, 2) == 0), plain("cloth", PURPLE, 0.03, 0.1, seed=7))
    s.put(banner & ~fringe & ~emblem & (np.mod(ban_idx, 2) == 1), plain("cloth", RED, 0.03, 0.1, seed=8))
    s.put(banner & (emblem | fringe | (np.abs(np.abs(pc) - 0.3) < 0.05)), pack("gold", GOLD))
    s.carve(banner & (Y < 0.8) & ~fringe)
    s.put(band(14.8, 14.9) & (Y >= 1.75) & (Y < 1.85) & (np.abs(pc) < 0.45), pack("bronze", BRONZE))
    # A balustrade along the top of the wall.
    s.put(band(15.0, 15.2) & (Y >= 2.0) & (Y < 2.1), pack("marble", MARBLE))
    s.put(band(15.0, 15.2) & (Y >= 2.4) & (Y < 2.5), plain("marble", MARBLE, 0.03, 0.04, seed=9))
    post = np.mod(np.floor(th * 15.1 / vs), 3) == 0
    s.put(band(15.05, 15.15) & (Y >= 2.1) & (Y < 2.4) & post, pack("marble", (0.86, 0.84, 0.79)))

    # -- the gatehouses, east (+x) and west (-x).
    for gx in (1, -1):
        u = gx * x
        v = z
        side = (u > 10)
        av = np.abs(v)
        block = side & (u >= 14.8) & (u < 16.8) & (av < 2.4) & (Y < 3.8)
        s.carve(side & (u >= 14.8) & (u < 16.8) & (av < 2.5) & (Y >= 2.0))
        s.put(block, ashlar("stone", TRAVERTINE, 0.6, 0.3, 0.1, seed=40, dirt=0.5, streak=1.0, damp=0.6))
        chip(s, block & (u < 14.9), 0.6, 0.3, 220 + (1 if gx > 0 else 0), 0.4, 0.05)
        s.put(side & (u >= 14.6) & (u < 16.9) & (av < 2.5) & (Y >= 3.8) & (Y < 4.0), ashlar("marble", MARBLE, 1.2, 0.2, 0.04, seed=41, mortar=0.9))
        s.put(side & (u >= 14.7) & (u < 14.8) & (av >= 2.0) & (av < 2.4) & (Y < 3.8), ashlar("marble", MARBLE, 2.0, 0.6, 0.04, seed=42, dirt=0.3, mortar=0.92))
        # The tunnel, sooty deeper in.
        tunnel = side & (u >= 14.6) & (u < 18.6) & (av < 1.35) & (Y < 2.5)
        lining = side & (u >= 14.6) & (u < 18.8) & (av < 1.55) & (Y < 2.7) & ~tunnel

        def soot(ix, iy, iz, xx, yy, zz, gx=gx):
            k = np.clip((gx * xx - 14.8) / 3.5, 0, 1)
            c = tint(TRAV_DARK, 0.08, hash3(np.floor(gx * xx / 0.5).astype(np.int64), np.floor(yy / 0.3).astype(np.int64), 3))
            c *= (1 - 0.65 * np.round(k * 6) / 6)[:, None]
            return pack("stone", c)
        s.recolor(lining, soot)
        s.carve(tunnel)
        # The frame, the lintel and its gold keystone, the inscription above.
        frame = side & (u >= 14.7) & (u < 14.8) & (av >= 1.35) & (av < 1.75) & (Y < 2.8)
        lintel = side & (u >= 14.7) & (u < 14.8) & (av < 1.75) & (Y >= 2.5) & (Y < 2.8)
        s.put(frame | lintel, ashlar("marble", MARBLE, 0.5, 0.4, 0.04, seed=43, dirt=0.3, mortar=0.9))
        s.put(side & (u >= 14.65) & (u < 14.8) & (av < 0.15) & (Y >= 2.5) & (Y < 2.8), pack("gold", GOLD))
        insc = side & (u >= 14.7) & (u < 14.8) & (av < 1.3) & (Y >= 2.9) & (Y < 3.8)
        s.put(insc, plain("plaster", RED, 0.03, 0.06, seed=44))
        s.put(insc & ((av >= 1.2) | (Y < 3.0) | (Y >= 3.7)), pack("gold", GOLD))
        cells, w = text_cells("SPQR")
        col = (np.round(gx * v / vs - 0.5) + w // 2).astype(int)   # reads left to right from the sand
        row = np.round((3.55 - Y) / vs).astype(int)
        letter = np.zeros(np.broadcast_shapes(col.shape, row.shape), bool)
        for (cx, cy) in cells:
            letter |= (col == cx) & (row == cy)
        s.put(insc & letter & (u < 14.8), pack("gold", GOLD))

    # -- the Emperor's box, north (+z).
    ax = np.abs(x)
    boxreg = (ax < 2.3) & (z >= 15.9) & (z < 18.5)
    s.carve((ax < 2.6) & (z >= 15.8) & (z < 18.8) & (Y >= 3.6))
    s.put(boxreg & (Y < 3.6) & (Y >= 2.0), ashlar("stone", TRAVERTINE, 0.6, 0.3, seed=50))
    front = (ax < 2.3) & (z >= 15.9) & (z < 16.0) & (Y >= 2.6) & (Y < 3.5)
    s.put(front, plain("plaster", RED, 0.03, 0.06, seed=51))
    s.put(front & ((Y < 2.7) | (Y >= 3.4) | (ax >= 2.2) | (np.abs(np.mod(x + 0.75, 1.5) - 0.75) < 0.06)), pack("gold", GOLD))
    tiles = (np.mod(np.floor(x / 0.3) + np.floor(z / 0.3), 2) == 0)
    floor_ = boxreg & (Y >= 3.5) & (Y < 3.6)
    s.put(floor_ & tiles, plain("marble", MARBLE, 0.02, 0.03, seed=52))
    s.put(floor_ & ~tiles, plain("marble", (0.55, 0.30, 0.36), 0.03, 0.04, seed=53))
    rail = (Y >= 3.6) & (Y < 4.2) & (((z >= 15.9) & (z < 16.0) & (ax < 2.3)) | ((ax >= 2.2) & (ax < 2.3) & (z >= 15.9) & (z < 18.5)))
    bal = (Y >= 4.1) | (Y < 3.7) | (np.mod(np.floor((x + z) / vs), 3) == 0)
    s.put(rail & bal, pack("marble", MARBLE))
    s.put(rail & (Y >= 4.1), pack("gold", GOLD))
    for px_ in (-2.2, 2.1):
        for pz in (15.9, 18.3):
            s.put((x >= px_) & (x < px_ + 0.2) & (z >= pz) & (z < pz + 0.2) & (Y >= 3.6) & (Y < 6.0), plain("gold", GOLD, 0.02, 0.02, seed=54))
    back = (ax < 2.3) & (z >= 18.5) & (z < 18.7) & (Y >= 3.6) & (Y < 6.0)
    s.put(back, plain("cloth", PURPLE, 0.03, 0.1, seed=55))
    s.put(back & (np.abs(np.mod(x + 0.25, 0.5) - 0.25) < 0.05), pack("gold", GOLD))
    s.put((ax < 2.5) & (z >= 15.7) & (z < 18.7) & (Y >= 6.0) & (Y < 6.2), plain("cloth", PURPLE, 0.03, 0.08, seed=56))
    val = (ax < 2.5) & (z >= 15.7) & (z < 15.8) & (Y >= 5.8) & (Y < 6.0)
    s.put(val & (np.mod(np.floor(x / vs), 2) == 0), pack("gold", GOLD))
    s.put(val & (Y >= 5.9) & (np.mod(np.floor(x / vs), 2) == 1), pack("cloth", PURPLE))

    # -- the arcade: columns, arches, the cornice on top, the flagpoles.
    ci = np.round(th / (2 * math.pi / COLS))
    ca = ci * 2 * math.pi / COLS
    cx_, cz_ = np.sin(ca) * TOP_R, np.cos(ca) * TOP_R
    d = np.sqrt((x - cx_) ** 2 + (z - cz_) ** 2)
    shaft = (d < 0.26) & (Y >= WALK_Y) & (Y < 8.6)
    s.put(shaft, ashlar("marble", MARBLE, 2.0, 0.6, 0.04, seed=60, mortar=0.93, radial=False))
    s.put((d < 0.36) & (((Y >= WALK_Y) & (Y < WALK_Y + 0.2)) | ((Y >= 8.4) & (Y < 8.6))), pack("marble", (0.86, 0.84, 0.79)))
    archband = band(23.85, 24.35) & (Y >= 8.6) & (Y < 9.6)
    dm = dang(th, 2 * math.pi / COLS, math.pi / COLS) * TOP_R
    hole = dm ** 2 + (Y - 7.75) ** 2 < 1.32 ** 2
    s.put(archband & ~hole, ashlar("marble", (0.88, 0.85, 0.78), 0.5, 0.25, 0.06, seed=61, mortar=0.88, streak=0.6))
    s.put(band(23.7, 24.5) & (Y >= 9.6) & (Y < 9.9), ashlar("marble", MARBLE, 1.4, 0.3, 0.04, seed=62, mortar=0.9))
    s.put(band(23.6, 24.6) & (Y >= 9.9) & (Y < 10.0), pack("marble", MARBLE))
    s.put(band(23.65, 24.55) & (Y >= 9.6) & (Y < 9.7), pack("plaster", RED))
    fi = np.round(th / (2 * math.pi / 16)) * 2 * math.pi / 16
    fd = np.sqrt((x - np.sin(fi) * 24.4) ** 2 + (z - np.cos(fi) * 24.4) ** 2)
    s.put((fd < 0.07) & (Y >= 10.0) & (Y < 12.0), pack("bronze", BRONZE))
    s.put((fd < 0.1) & (Y >= 12.0) & (Y < 12.1), pack("gold", GOLD))

    # Chunks: eight sectors, so the renderer can skip the ones behind the camera.
    def split(cent):
        a = np.arctan2(cent[:, 0], cent[:, 2])
        return np.clip(np.floor((a + math.pi) / (2 * math.pi) * 8).astype(int), 0, 7)
    t0 = time.time()
    tris = V.export(s, os.path.join(OUT, "arena.glb"), cull_r=16.0, cull_floor=0.01,
                    split=split, split_names=["sector%d" % i for i in range(8)])
    print("arena.glb: %d triangles (%.1fs)" % (tris, time.time() - t0))


# ====================================================================== props (5 cm)

def prop(name, lo, hi, build, vs=0.05):
    s = V.Sculpt(vs, lo, hi)
    build(s)
    tris = V.export(s, os.path.join(OUT, name + ".glb"), name=name, cull_floor=0.001 if lo[1] >= 0 else -1e9)
    print("%s.glb: %d triangles" % (name, tris))


def brazier(s):
    """A bronze tripod brazier, 1.55 m to the rim, full of glowing coals."""
    br = patina(BRONZE, seed=70, amount=0.17)
    for k in range(3):
        a = k * 2 * math.pi / 3
        foot = (math.sin(a) * 0.34, 0.05, math.cos(a) * 0.34)
        s.seg(foot, (math.sin(a) * 0.12, 1.2, math.cos(a) * 0.12), 0.04, br)
        s.sphere((foot[0], 0.06, foot[2]), 0.07, br, (1, 0.8, 1))
    s.cyl((0, 0, 0), 0.2, 0.55, 0.62, br, r_in=0.12)
    s.cyl((0, 0, 0), 0.16, 1.12, 1.22, br)
    bowl = s.lathe_mask((0, 0, 0), lambda t: 0.14 + 0.24 * np.sqrt(t), 1.2, 1.52, thick=0.05)
    s.put(bowl, br)
    s.cyl((0, 0, 0), 0.4, 1.5, 1.56, pack("gold", GOLD), r_in=0.33)

    def coals(ix, iy, iz, x, y, z):
        h = hash3(ix, iy, iz, 71)
        c = np.where((h > 0.55)[:, None], np.array([[1.0, 0.42, 0.08]]), np.array([[0.12, 0.08, 0.06]]))
        c = c * (0.7 + 0.6 * hash3(ix, iy, iz, 72))[:, None]
        hot = h > 0.55
        out = pack("stone", c)
        out[hot] = pack("ember", c[hot])
        return out
    x, y, z = s.grids()
    lump = (y < 1.42 + 0.08 * vnoise(x, 0 * y, z, 0.08, 73)) & s.lathe_mask((0, 0, 0), lambda t: 0.14 + 0.24 * np.sqrt(t) - 0.04, 1.25, 1.52)
    s.put(lump, coals)


def gate_door(s):
    """A gate leaf, hinged at z = 0, 2.6 m wide and 2.4 m tall: oak boards, iron straps and studs."""
    def stain(c, x, y, z):
        # Rust run down the boards from under each strap's studs, fading as it goes.
        col = np.abs(np.mod(z - 0.216, 0.433) - 0.216) > 0.17
        for by in (0.45, 1.75):
            d = by - y
            run = col & (d > 0) & (d < 0.5) & (hash3(np.floor(z / 0.05).astype(np.int64), int(by * 10), 0, 84) > 0.25)
            k = (0.55 * (1.0 - d / 0.5))[:, None] * run[:, None]
            c = c * (1 - k) + np.array([[0.36, 0.17, 0.08]], np.float32) * k
        return c
    s.box((-0.12, 0, 0), (0.12, 2.4, 2.6), planks("wood", WOOD, along=1, width=0.433, seed=80, post=stain))
    x, y, z = s.grids()
    for by in (0.45, 1.75):
        strap = (y >= by) & (y < by + 0.2) & (z >= 0.05) & (z < 2.55) & (np.abs(x) < 0.17)
        s.put(strap, rusty(IRON, seed=81))
        stud = (np.abs(x) < 0.22) & (np.abs(y - by - 0.1) < 0.05) & (np.abs(np.mod(z - 0.216, 0.433) - 0.216) > 0.17)
        s.put(stud & (z > 0.1) & (z < 2.5), pack("iron", (0.30, 0.29, 0.27)))
    s.box((-0.17, 0, 0), (0.17, 2.4, 0.08), rusty(IRON, seed=82, amount=0.35))
    ring = s.cyl_mask((0, 1.1, 2.2), 0.13, -0.27, 0.27, axis=0, r_in=0.08) & (np.abs(x) > 0.15)
    s.put(ring, pack("iron", (0.3, 0.28, 0.26)))
    s.put((np.abs(x) < 0.16) & (np.abs(y - 1.23) < 0.04) & (np.abs(z - 2.2) < 0.04), pack("iron", IRON))
    # Scars: a few gouges in the boards.
    gouge = (hash3(np.floor(y / 0.05).astype(np.int64), np.floor(z / 0.05).astype(np.int64), 0, 83) < 0.03) & (np.abs(x) > 0.1)
    s.carve(gouge & (np.abs(x) < 0.13))


def statue(s):
    """A marble gladiator on a pedestal (2.7 m), a bronze spear and shield."""
    mb = ashlar("marble", MARBLE, 3.0, 3.0, 0.02, seed=90, mortar=1.0, radial=False)
    ped = ashlar("marble", (0.84, 0.81, 0.75), 0.4, 0.3, 0.05, seed=91, mortar=0.9, radial=False)
    s.box((-0.4, 0, -0.4), (0.4, 0.6, 0.4), ped)
    s.box((-0.45, 0, -0.45), (0.45, 0.1, 0.45), pack("marble", (0.8, 0.77, 0.7)))
    s.box((-0.45, 0.5, -0.45), (0.45, 0.6, 0.45), pack("marble", (0.8, 0.77, 0.7)))
    s.box((-0.41, 0.2, 0.39), (0.41, 0.4, 0.41), pack("gold", GOLD))
    b = 0.6
    # Legs (one forward), the kilt, the torso, the arms, the crested helmet.
    s.box((-0.2, b, -0.08), (-0.04, b + 0.75, 0.1), mb)
    s.box((0.04, b, -0.0), (0.2, b + 0.75, 0.2), mb)
    s.box((-0.22, b + 0.6, -0.12), (0.22, b + 0.9, 0.16), plain("marble", (0.86, 0.84, 0.79), seed=92))
    s.box((-0.24, b + 0.85, -0.12), (0.24, b + 1.35, 0.14), mb)
    s.box((-0.24, b + 1.05, 0.12), (0.24, b + 1.3, 0.16), mb)                  # the chest
    s.box((-0.36, b + 0.85, -0.06), (-0.24, b + 1.35, 0.08), mb)               # left arm, down
    s.seg((0.3, b + 1.3, 0.0), (0.34, b + 1.75, 0.08), 0.07, mb)              # right arm, raised
    s.box((-0.1, b + 1.35, -0.1), (0.1, b + 1.6, 0.11), mb)                    # head
    s.box((-0.12, b + 1.5, -0.12), (0.12, b + 1.68, 0.13), plain("bronze", BRONZE, seed=93))
    s.box((-0.03, b + 1.62, -0.2), (0.03, b + 1.82, 0.16), pack("plaster", RED))  # the crest
    s.seg((0.36, b - 0.0, 0.1), (0.36, b + 2.15, 0.1), 0.03, plain("bronze", BRONZE, seed=94))
    s.seg((0.36, b + 2.1, 0.1), (0.36, b + 2.3, 0.1), 0.045, pack("bronze", (0.75, 0.55, 0.3)))
    shield = s.cyl_mask((-0.42, b + 1.05, 0.04), 0.3, -0.48, -0.36, axis=0)
    s.put(shield, plain("bronze", BRONZE, 0.04, 0.15, seed=95))
    s.put(s.cyl_mask((-0.42, b + 1.05, 0.04), 0.08, -0.52, -0.36, axis=0), pack("gold", GOLD))


def amphora(s, wide=False):
    """A terracotta jar with two handles and a painted band."""
    if wide:
        prof = lambda t: np.interp(t, [0, 0.1, 0.45, 0.8, 0.86, 1.0], [0.1, 0.2, 0.26, 0.2, 0.13, 0.15])
        h = 0.62
    else:
        prof = lambda t: np.interp(t, [0, 0.08, 0.4, 0.68, 0.78, 0.95, 1.0], [0.06, 0.1, 0.19, 0.16, 0.1, 0.1, 0.13])
        h = 0.78

    def terra(ix, iy, iz, x, y, z):
        c = tint(TERRA, 0.05, hash3(ix, iy, iz, 100)) * tint((1, 1, 1), 0.08, vnoise(x, y, z, 0.2, 101))
        bandm = np.abs(y - h * 0.55) < 0.025
        c[bandm] = np.array([0.15, 0.1, 0.08])
        return pack("terracotta", c)
    s.put(s.lathe_mask((0, 0, 0), prof, 0, h), terra)
    s.carve(s.cyl_mask((0, 0, 0), 0.05 if not wide else 0.08, h - 0.06, h + 0.01))
    for sx in (-1, 1):
        s.seg((sx * 0.08, h * 0.9, 0), (sx * 0.18, h * 0.86, 0), 0.035, pack("terracotta", TERRA))
        s.seg((sx * 0.18, h * 0.86, 0), (sx * 0.18, h * 0.6, 0), 0.035, pack("terracotta", TERRA))


def crate(s):
    """A crate of pale boards in a dark frame, a little proud of the boards, with a cross brace."""
    x, y, z = s.grids()
    s.box((-0.27, 0.03, -0.27), (0.27, 0.57, 0.27), 0)
    boards = (np.maximum(np.abs(x), np.abs(z)) < 0.27) & (y > 0.03) & (y < 0.57)
    def board(ix, iy, iz, xx, yy, zz):
        b = np.floor(yy / 0.1)
        bi = b.astype(np.int64)
        c = tint((0.66, 0.5, 0.31), 0.12, hash3(bi, np.floor((xx + zz) * 3).astype(np.int64), 0, 110))
        # The grain along the board, and a knot here and there.
        along = xx + zz
        g = hash3(iy, np.floor(vnoise(along, 0 * along, b, 0.3, 113) * 2).astype(np.int64), bi, 114)
        c *= (1.0 - 0.13 * (g < 0.3) + 0.06 * (g > 0.85))[:, None]
        cell = np.floor(along / 0.25).astype(np.int64)
        kx = (cell + 0.3 + 0.4 * hash3(cell, bi, 0, 115)) * 0.25
        knot = (hash3(cell, bi, 1, 115) < 0.3) & (np.abs(along - kx) < 0.03)
        c[knot] *= 0.6
        c[(yy - b * 0.1) < 0.049] *= 0.72
        return pack("wood", c)
    s.put(boards, board)
    frame = (((np.abs(x) > 0.25).astype(int) + (np.abs(z) > 0.25) + ((y < 0.08) | (y > 0.52))) >= 2) & (np.maximum(np.abs(x), np.abs(z)) < 0.31) & (y < 0.6)
    s.put(frame, plain("wood", WOOD_DARK, 0.06, 0.1, seed=111))
    brace = (np.abs((y - 0.3) - np.where(np.abs(x) > 0.28, z, x) * 0.9) < 0.04) & (np.maximum(np.abs(x), np.abs(z)) > 0.27) & (np.maximum(np.abs(x), np.abs(z)) < 0.31) & (y > 0.05) & (y < 0.55)
    s.put(brace, plain("wood", WOOD_DARK, 0.06, 0.1, seed=112))
    corner = frame & (np.abs(x) > 0.25) & (np.abs(z) > 0.25) & ((y < 0.17) | (y > 0.43))
    s.recolor(corner, rusty(IRON, seed=116, amount=0.5))
    rivet = corner & ((np.abs(y - 0.1) < 0.025) | (np.abs(y - 0.5) < 0.025)) & (np.maximum(np.abs(x), np.abs(z)) > 0.29)
    s.recolor(rivet, pack("iron", (0.36, 0.34, 0.31)))


def weapon_rack(s):
    """A rack of spears and two shields, 2 m wide."""
    wd = planks("wood", WOOD, along=0, width=2.0, seed=120)
    s.box((-1.0, 0, -0.1), (-0.9, 1.4, 0.1), wd)
    s.box((0.9, 0, -0.1), (1.0, 1.4, 0.1), wd)
    s.box((-1.0, 1.3, -0.1), (1.0, 1.4, 0.1), wd)
    s.box((-1.0, 0.25, -0.15), (1.0, 0.35, 0.15), wd)
    for k in range(7):
        xx = -0.725 + k * 0.25
        s.seg((xx, 0.3, 0.025), (xx, 1.75, -0.025), 0.04, grain("wood", (0.6, 0.45, 0.28), seed=121 + k))
        s.seg((xx, 1.75, -0.025), (xx, 1.98, -0.03), 0.05, pack("iron", (0.45, 0.44, 0.42)))
    for sx, colr in ((-0.45, RED), (0.45, (0.18, 0.28, 0.5))):
        m = s.cyl_mask((sx, 0.55, 0.22), 0.36, 0.15, 0.22, axis=2)
        s.put(m, plain("plaster", colr, 0.04, 0.1, seed=122))
        s.put(m & ~s.cyl_mask((sx, 0.55, 0.22), 0.32, 0.1, 0.3, axis=2), pack("bronze", BRONZE))
        s.put(s.cyl_mask((sx, 0.55, 0.22), 0.08, 0.1, 0.22, axis=2), pack("bronze", (0.75, 0.55, 0.3)))


def throne(s):
    gd = plain("gold", GOLD, 0.03, 0.05, seed=130)
    s.box((-0.45, 0, -0.35), (0.45, 0.45, 0.35), gd)
    s.box((-0.4, 0.45, -0.3), (0.4, 0.55, 0.3), plain("cloth", PURPLE, 0.03, 0.08, seed=131))
    s.box((-0.45, 0.45, 0.25), (0.45, 1.5, 0.35), gd)
    s.box((-0.38, 0.55, 0.22), (0.38, 1.38, 0.25), plain("cloth", PURPLE, 0.03, 0.08, seed=132))
    for sx in (-1, 1):
        s.box((sx * 0.45 - 0.05, 0.45, -0.35), (sx * 0.45 + 0.05, 0.8, 0.35), gd)
        s.sphere((sx * 0.45, 0.82, -0.33), 0.08, gd)
    s.sphere((0, 1.55, 0.3), 0.1, gd)


def sign_post(s):
    """A post with a little plank board on top (2.2 m); the game puts the label above it."""
    s.box((-0.05, 0, -0.05), (0.05, 2.2, 0.05), grain("wood", WOOD_DARK, seed=140))
    s.box((-0.5, 1.75, -0.05), (0.5, 2.05, 0.05), planks("wood", (0.62, 0.46, 0.28), along=0, width=0.1, seed=141))
    s.box((-0.05, 1.75, -0.1), (0.05, 2.05, -0.05), rusty(IRON, seed=142, amount=0.5))


def target(s):
    """A straw target, painted rings, on two legs; the origin is the bull's eye, the ground 1.5 m below."""
    def face(ix, iy, iz, x, y, z):
        d = np.sqrt(x * x + y * y)
        c = tint(STRAW, 0.1, hash3(ix, iy, iz, 150)) * tint((1, 1, 1), 0.06, vnoise(x, y, z, 0.1, 151))
        front = z < -0.03
        c[front & (d < 0.5)] = np.array(CREAM) * (0.95 + 0.1 * hash3(ix, iy, iz, 152)[front & (d < 0.5)])[:, None]
        c[front & (d < 0.3)] = np.array(RED)
        c[front & (d < 0.15)] = np.array([0.95, 0.82, 0.3])
        return pack("straw", c)
    s.put(s.cyl_mask((0, 0, 0), 0.5, -0.06, 0.06, axis=2), face)
    s.put(s.cyl_mask((0, 0, 0), 0.52, -0.04, 0.06, axis=2, r_in=0.48), pack("wood", WOOD_DARK))
    for sx in (-1, 1):
        s.seg((sx * 0.3, -0.35, 0.08), (sx * 0.4, -1.5, 0.35), 0.035, grain("wood", WOOD, seed=153))
    s.seg((-0.4, -1.1, 0.25), (0.4, -1.1, 0.25), 0.03, plain("wood", WOOD, seed=154))


def smithy(s):
    """The smith's corner: a brick hearth with live coals and a hood, an anvil on a stump, a quench
    barrel and a rack of tongs. 3 m wide, faces +z."""
    brick = ashlar("stone", (0.55, 0.30, 0.22), 0.25, 0.1, 0.1, seed=160, radial=False, mortar=0.75, vs=0.05)
    s.box((-1.4, 0, -0.6), (-0.2, 0.8, 0.3), brick)
    x, y, z = s.grids()
    s.carve((x > -1.3) & (x < -0.3) & (z > -0.5) & (z < 0.2) & (y > 0.7))

    def coal(ix, iy, iz, xx, yy, zz):
        h = hash3(ix, iy, iz, 161)
        c = np.where((h > 0.5)[:, None], np.array([[1.0, 0.45, 0.1]]), np.array([[0.1, 0.07, 0.06]]))
        out = pack("stone", c)
        out[h > 0.5] = pack("ember", c[h > 0.5])
        return out
    s.put((x > -1.3) & (x < -0.3) & (z > -0.5) & (z < 0.2) & (y >= 0.7) & (y < 0.75 + 0.05 * (hash3(np.floor(x / 0.05).astype(np.int64), 0, np.floor(z / 0.05).astype(np.int64), 162) > 0.6)), coal)
    s.box((-1.45, 1.6, -0.65), (-0.15, 1.75, 0.35), brick)
    hood = (y >= 1.75) & (y < 2.5) & (np.abs(x + 0.8) < 0.65 - (y - 1.75) * 0.6) & (z > -0.6) & (z < 0.3 - (y - 1.75) * 0.6)
    s.put(hood, brick)
    s.box((-1.0, 2.5, -0.55), (-0.6, 3.0, -0.15), brick)
    s.box((-1.42, 0.8, -0.62), (-1.32, 1.6, -0.52), grain("wood", WOOD_DARK, seed=163))
    s.box((-0.28, 0.8, -0.62), (-0.18, 1.6, -0.52), grain("wood", WOOD_DARK, seed=164))
    # The anvil on its stump.
    s.cyl((0.5, 0, 0.3), 0.28, 0, 0.55, planks("wood", WOOD_DARK, along=1, width=0.07, seed=165))
    ir = plain("iron", (0.2, 0.2, 0.21), 0.04, 0.08, seed=166)
    s.box((0.35, 0.55, 0.2), (0.65, 0.65, 0.4), ir)
    s.box((0.4, 0.65, 0.22), (0.6, 0.75, 0.38), ir)
    s.box((0.2, 0.75, 0.18), (0.75, 0.9, 0.42), ir)
    s.seg((0.75, 0.86, 0.3), (0.98, 0.84, 0.3), 0.05, ir)
    s.seg((0.3, 0.92, 0.25), (0.48, 1.0, 0.36), 0.025, plain("wood", WOOD, seed=167))
    s.box((0.26, 0.9, 0.22), (0.34, 0.98, 0.32), ir)
    # A quench barrel.
    s.cyl((1.15, 0, -0.3), 0.27, 0, 0.7, planks("wood", WOOD, along=1, width=0.08, seed=168))
    s.cyl((1.15, 0, -0.3), 0.28, 0.12, 0.17, rusty(IRON, seed=169))
    s.cyl((1.15, 0, -0.3), 0.28, 0.55, 0.6, rusty(IRON, seed=170))
    s.cyl((1.15, 0, -0.3), 0.22, 0.6, 0.7, pack("glow", (0.12, 0.2, 0.22)))


def market_stall(s):
    """A market stall 2.4 m wide: posts, a striped awning, a counter of bread, fruit and jars."""
    wd = grain("wood", WOOD, seed=170)
    for sx in (-1.15, 1.05):
        for sz in (-0.55, 0.45):
            s.box((sx, 0, sz), (sx + 0.1, 2.2 if sz < 0 else 1.9, sz + 0.1), wd)
    x, y, z = s.grids()
    aw_y = 2.2 - (z + 0.6) * 0.33
    awn = (np.abs(x) < 1.3) & (z > -0.7) & (z < 0.95) & (y >= aw_y) & (y < aw_y + 0.06)
    stripe = np.mod(np.floor((x + 1.3) / 0.3), 2) == 0
    s.put(awn & stripe, plain("cloth", RED, 0.03, 0.08, seed=171))
    s.put(awn & ~stripe, plain("cloth", CREAM, 0.03, 0.08, seed=172))
    s.put(awn & (z > 0.85) & (np.mod(np.floor(x / 0.05), 2) == 0), pack("cloth", RED))
    s.box((-1.1, 0, 0.3), (1.05, 0.9, 0.55), planks("wood", (0.6, 0.44, 0.27), along=0, width=0.15, seed=173))
    s.box((-1.15, 0.9, 0.2), (1.1, 0.96, 0.6), planks("wood", WOOD_DARK, along=0, width=2.5, seed=174))
    # Goods: loaves, apples and pears, a basket, jars.
    for k in range(5):
        s.sphere((-0.95 + k * 0.17, 1.0, 0.4), 0.08, plain("straw", (0.78, 0.52, 0.24), seed=175 + k), (1.0, 0.6, 0.8))
    for k in range(10):
        xx = -0.05 + (k % 5) * 0.09
        zz = 0.32 + (k // 5) * 0.12
        colr = (0.75, 0.15, 0.1) if k % 3 else (0.6, 0.7, 0.2)
        s.sphere((xx, 1.0, zz), 0.045, pack("plaster", colr))
    s.cyl((0.75, 0, 0.4), 0.13, 0.96, 1.15, pack("terracotta", TERRA))
    s.cyl((0.95, 0, 0.42), 0.09, 0.96, 1.12, pack("terracotta", (0.6, 0.32, 0.18)))
    # Crates and a jar behind.
    s.box((-0.9, 0, -0.45), (-0.4, 0.5, 0.05), planks("wood", (0.6, 0.44, 0.27), along=0, width=0.12, seed=176))
    s.box((-0.85, 0.5, -0.4), (-0.45, 0.8, 0.0), planks("wood", (0.56, 0.4, 0.24), along=2, width=0.1, seed=177))
    s.put(s.lathe_mask((0.6, 0, -0.2), lambda t: np.interp(t, [0, 0.1, 0.5, 0.8, 1], [0.08, 0.16, 0.2, 0.1, 0.09]), 0, 0.6), plain("terracotta", TERRA, seed=178))


def notice_board(s):
    """The mission board: a framed plank board on two posts, notices pinned to it."""
    wd = grain("wood", WOOD_DARK, seed=180)
    s.box((-0.85, 0, -0.06), (-0.75, 2.1, 0.06), wd)
    s.box((0.75, 0, -0.06), (0.85, 2.1, 0.06), wd)
    s.box((-0.85, 0.85, -0.04), (0.85, 1.95, 0.04), planks("wood", WOOD, along=0, width=0.11, seed=181))
    s.box((-0.95, 1.95, -0.12), (0.95, 2.05, 0.12), wd)
    rng = np.random.default_rng(3)
    for k in range(7):
        cx, cy = rng.uniform(-0.6, 0.6), rng.uniform(1.05, 1.75)
        w, h = rng.uniform(0.18, 0.3), rng.uniform(0.22, 0.32)
        s.box((cx - w / 2, cy - h / 2, 0.05), (cx + w / 2, cy + h / 2, 0.1), plain("cloth", CREAM, 0.04, 0.1, seed=182 + k))
        s.box((cx - 0.03, cy + h / 2 - 0.08, 0.1), (cx + 0.03, cy + h / 2 - 0.02, 0.15), pack("plaster", RED))


def physician(s):
    """The physician's table: a bench with a cloth, jars and a bowl, bundles of herbs."""
    wd = planks("wood", (0.6, 0.44, 0.27), along=0, width=0.15, seed=190)
    s.box((-0.9, 0.75, -0.35), (0.9, 0.82, 0.35), wd)
    for sx in (-0.82, 0.74):
        for sz in (-0.3, 0.22):
            s.box((sx, 0, sz), (sx + 0.08, 0.75, sz + 0.08), grain("wood", WOOD_DARK, seed=191))
    s.box((-0.85, 0.82, -0.3), (0.2, 0.84, 0.3), plain("cloth", CREAM, 0.04, 0.1, seed=192))
    for k, (xx, h) in enumerate([(-0.6, 0.22), (-0.42, 0.16), (-0.25, 0.26), (0.45, 0.18), (0.62, 0.24)]):
        s.cyl((xx, 0, -0.12 + 0.08 * (k % 2)), 0.06 + 0.02 * (k % 2), 0.84, 0.84 + h, pack("terracotta" if k % 2 else "glow", TERRA if k % 2 else (0.35, 0.55, 0.45)))
    s.cyl((0.0, 0, 0.1), 0.14, 0.84, 0.9, pack("bronze", BRONZE), r_in=0.1)
    for k in range(3):
        s.seg((-0.7 + k * 0.5, 1.6, -0.36), (-0.7 + k * 0.5, 1.3, -0.36), 0.05, plain("straw", (0.35, 0.5, 0.25), seed=193 + k))
    s.box((-0.9, 1.6, -0.4), (0.9, 1.66, -0.34), plain("wood", WOOD_DARK, seed=196))
    for sx in (-0.88, 0.82):
        s.box((sx, 0, -0.42), (sx + 0.06, 1.66, -0.36), plain("wood", WOOD_DARK, seed=197))


def column(s):
    """A fluted marble column 6 m tall with its base and capital (the title screen's)."""
    x, y, z = s.grids()
    d = np.sqrt(x * x + z * z)
    ang = np.arctan2(x, z)
    flute = np.abs(np.mod(ang * 12 / (2 * math.pi), 1.0) - 0.5) < 0.18
    shaft = (d < 0.33 - 0.03 * (y / 6.0)) & (y >= 0.35) & (y < 5.55)
    mb = ashlar("marble", (0.86, 0.83, 0.77), 3.0, 0.9, 0.05, seed=210, mortar=0.88, radial=False)
    s.put(shaft, mb)
    s.carve(shaft & flute & (d > 0.28 - 0.03 * (y / 6.0)) & (y > 0.6) & (y < 5.3))
    s.put((np.maximum(np.abs(x), np.abs(z)) < 0.45) & (y < 0.2), ashlar("marble", (0.8, 0.77, 0.7), 0.5, 0.2, 0.05, seed=211, radial=False))
    s.put((d < 0.4) & (y >= 0.2) & (y < 0.35), pack("marble", (0.84, 0.81, 0.75)))
    s.put((d < 0.38) & (y >= 5.55) & (y < 5.7), pack("marble", (0.84, 0.81, 0.75)))
    s.put((np.maximum(np.abs(x), np.abs(z)) < 0.48) & (y >= 5.7) & (y < 6.0), ashlar("marble", MARBLE, 0.5, 0.3, 0.04, seed=212, radial=False))
    # Weathered: chips knocked out of the edges.
    chip = (hash3(np.floor(x / 0.05).astype(np.int64), np.floor(y / 0.05).astype(np.int64), np.floor(z / 0.05).astype(np.int64), 213) < 0.06) & (d > 0.27)
    s.carve(chip & (y > 0.4) & (y < 5.5))


def banner(s):
    """A red banner 1.1 x 2.4 m with a gold SPQR and fringe, hanging from a bronze rod (top at 2.4)."""
    x, y, z = s.grids()
    cloth = (np.abs(x) < 0.55) & (y < 2.35) & (np.abs(z) < 0.025)
    s.put(cloth & ~((y < 0.3) & (np.abs(x) < 0.3 - y)), plain("cloth", (0.5, 0.07, 0.06), 0.04, 0.12, seed=220))
    trim = cloth & ((np.abs(x) > 0.47) | ((y > 2.22) & (y < 2.28)))
    s.recolor(trim, pack("gold", GOLD))
    cells, w = text_cells("SPQR")
    col = (np.round(x / 0.05 - 0.5) + w // 2).astype(int)
    row = np.floor((1.85 - y) / 0.05).astype(int)
    letter = np.zeros(np.broadcast_shapes(col.shape, row.shape), bool)
    for (cx, cy) in cells:
        letter |= (col == cx) & (row == cy)
    s.recolor(cloth & letter & (z > 0), pack("gold", GOLD))
    s.recolor(cloth & letter & (z < 0), pack("gold", GOLD))
    # A laurel ring under the letters.
    d = np.sqrt(x * x + (y - 1.15) ** 2)
    s.recolor(cloth & (d > 0.22) & (d < 0.28) & (y < 1.4), pack("gold", (0.8, 0.62, 0.2)))
    fringe = (y >= 0.0) & (y < 0.1) & (np.abs(x) < 0.55) & (np.abs(z) < 0.025) & (np.mod(np.floor(x / 0.05), 2) == 0)
    s.put(fringe & (np.abs(x) >= 0.3), pack("gold", GOLD))
    s.seg((-0.65, 2.37, 0), (0.65, 2.37, 0), 0.035, pack("bronze", BRONZE))
    for sx in (-1, 1):
        s.sphere((sx * 0.68, 2.37, 0), 0.06, pack("gold", GOLD))


def spike_plate(s):
    """The floor plate the spikes come up through: iron, a grid of holes, rivets round the edge."""
    x, y, z = s.grids()
    s.box((-0.55, 0, -0.55), (0.55, 0.05, 0.55), plain("iron", (0.26, 0.24, 0.22), 0.06, 0.15, seed=230))
    holes = (np.abs(np.mod(x + 0.55, 0.2) - 0.1) < 0.03) & (np.abs(np.mod(z + 0.55, 0.2) - 0.1) < 0.03) & (np.maximum(np.abs(x), np.abs(z)) < 0.45)
    s.recolor(holes, pack("iron", (0.05, 0.045, 0.04)))
    rim = (np.maximum(np.abs(x), np.abs(z)) > 0.5) & (y < 0.05)
    s.recolor(rim, pack("iron", (0.32, 0.3, 0.27)))
    rust = (vnoise(x, 0 * y, z, 0.15, 231) > 0.62) & (y < 0.05)
    s.recolor(rust & ~holes, plain("iron", (0.42, 0.24, 0.14), 0.08, 0.1, seed=232))


def bomb(s):
    """The hot potato: an iron ball with bands and rivets, a stub of fuse burning at the top.
    Origin at its middle; the fuse's tip is 0.19 m above."""
    x, y, z = s.grids()
    ball = s.sphere_mask((0, 0, 0), 0.14)
    s.put(ball, plain("iron", (0.13, 0.13, 0.14), 0.05, 0.1, seed=240))
    band = ball & (np.abs(y) < 0.025)
    s.recolor(band, pack("iron", (0.26, 0.25, 0.24)))
    s.recolor(ball & (np.abs(x) < 0.025) & (y > 0), pack("iron", (0.26, 0.25, 0.24)))
    s.box((-0.05, 0.11, -0.05), (0.05, 0.16, 0.05), pack("bronze", BRONZE))
    s.seg((0.0, 0.15, 0.0), (0.03, 0.19, 0.0), 0.02, pack("straw", (0.75, 0.62, 0.35)))
    s.box((0.0, 0.18, -0.025), (0.05, 0.23, 0.025), pack("ember", (1.0, 0.55, 0.15)))


def forge_anvil(s):
    """The forge's anvil block (0.5 x 0.22 x 0.3, its middle at the origin): dark stone with an
    iron face plate on top, chipped edges."""
    x, y, z = s.grids()
    s.box((-0.25, -0.11, -0.15), (0.25, 0.08, 0.15), ashlar("stone", (0.3, 0.28, 0.27), 0.25, 0.1, 0.1, seed=250, radial=False, mortar=0.85, vs=0.05))
    s.box((-0.26, 0.06, -0.16), (0.26, 0.11, 0.16), plain("iron", (0.22, 0.22, 0.23), 0.05, 0.12, seed=251))
    s.recolor((y > 0.06) & (np.abs(x) < 0.2) & (np.abs(z) < 0.1), plain("iron", (0.34, 0.33, 0.33), 0.05, 0.1, seed=252))
    chip = (hash3(np.floor(x / 0.05).astype(np.int64), np.floor(y / 0.05).astype(np.int64), np.floor(z / 0.05).astype(np.int64), 253) < 0.12) & ((np.abs(x) > 0.2) | (np.abs(z) > 0.1)) & (y < 0.05)
    s.carve(chip)


def ludus_gate(s):
    """The yard's way to the arena (4.4 m tall, 3.8 wide, its face toward +z): a round-arched
    gateway of travertine ashlar on two piers, a gilt keystone, an iron portcullis raised into
    the arch, the oak leaves swung back inside, and the dark of the tunnel beyond."""
    x, y, z = s.grids()
    stone = ashlar("stone", TRAVERTINE, 0.5, 0.3, 0.07, seed=300, mortar=0.84, radial=False, vs=0.05)
    dark_stone = ashlar("stone", TRAV_DARK, 0.5, 0.3, 0.06, seed=301, mortar=0.86, radial=False, vs=0.05)
    hw, spring, rad = 1.1, 2.55, 1.1          # the opening: half its width, where the arch springs, its radius
    opening = (np.abs(x) < hw) & ((y < spring) | ((x * x + (y - spring) ** 2) < rad * rad))
    body = (np.abs(x) < 1.9) & (y < 4.05) & (z > -0.5) & (z < 0.5)
    s.put(body & ~opening, stone)
    # A plinth and a cornice standing proud of the face, a frieze between in the darker stone.
    s.put((np.abs(x) < 2.0) & (y < 0.35) & (z > -0.55) & (z < 0.6) & ~opening, dark_stone)
    s.put((np.abs(x) < 2.05) & (y >= 4.05) & (y < 4.4) & (z > -0.6) & (z < 0.62), dark_stone)
    s.put((np.abs(x) < 1.95) & (y >= 3.8) & (y < 4.05) & (z > -0.5) & (z < 0.55), pack("stone", (0.6, 0.53, 0.43)))
    # The arch's voussoirs: a ring of wedge stones round the opening, a gilt keystone at the top.
    rr = np.sqrt(x * x + (y - spring) ** 2)
    ring = (rr >= rad) & (rr < rad + 0.3) & (y >= spring) & (z > 0.3) & (z < 0.58)
    seg = np.floor((np.arctan2(y - spring, x) / math.pi) * 9).astype(np.int64)
    vc = (0.84, 0.77, 0.64)
    s.put(ring & (np.mod(seg, 2) == 0), pack("stone", vc))
    s.put(ring & (np.mod(seg, 2) == 1), pack("stone", (0.78, 0.71, 0.58)))
    key = (np.abs(x) < 0.17) & (y >= spring + rad - 0.05) & (y < spring + rad + 0.42) & (z > 0.3) & (z < 0.62)
    s.put(key, pack("gold", GOLD))
    # Pilasters up the piers' faces, with capitals.
    for px in (-1.55, 1.55):
        pil = (np.abs(x - px) < 0.2) & (y >= 0.35) & (y < 3.6) & (z >= 0.5) & (z < 0.62)
        s.put(pil, ashlar("marble", MARBLE, 3.0, 0.9, 0.04, seed=302, mortar=0.9, radial=False, vs=0.05))
        s.put((np.abs(x - px) < 0.26) & (y >= 3.6) & (y < 3.8) & (z >= 0.48) & (z < 0.66), pack("marble", (0.86, 0.83, 0.77)))
    # The tunnel beyond: dark walls and a darker back, so the opening reads as a way through.
    s.put(opening & (z <= -0.35) & (z > -0.5), pack("stone", (0.07, 0.05, 0.04)))
    s.put(opening & (np.abs(x) >= hw - 0.1) & (z > -0.5) & (z < 0.45), pack("stone", (0.25, 0.21, 0.17)))
    # The portcullis raised into the arch: an iron grid, its spiked foot over the way.
    bars = opening & (y > 2.75) & (z > -0.05) & (z < 0.05) & ((np.abs(np.mod(x + hw, 0.3) - 0.15) < 0.04) | (np.abs(np.mod(y, 0.3) - 0.15) < 0.035))
    s.put(bars, rusty(IRON, seed=303, amount=0.38))
    s.put(opening & (y > 2.7) & (y < 2.8) & (np.abs(np.mod(x + hw, 0.3) - 0.15) < 0.04) & (np.abs(z) < 0.05), pack("iron", (0.3, 0.29, 0.27)))
    # The oak leaves swung back against the tunnel walls.
    for sx in (-1, 1):
        leaf = (np.abs(x - sx * (hw - 0.17)) < 0.06) & (y < spring - 0.1) & (z > -0.3) & (z < 0.35)
        s.put(leaf, planks("wood", WOOD, along=1, width=0.2, seed=304 + (sx > 0)))
        s.put(leaf & ((np.abs(y - 0.5) < 0.08) | (np.abs(y - 1.9) < 0.08)), rusty(IRON, seed=306))
    # A worn step at the threshold, and wear on the stone.
    s.put((np.abs(x) < hw + 0.1) & (y < 0.08) & (z > -0.5) & (z < 0.75), pack("stone", (0.62, 0.56, 0.46)))
    chip = (hash3(np.floor(x / 0.05).astype(np.int64), np.floor(y / 0.05).astype(np.int64), np.floor(z / 0.05).astype(np.int64), 307) < 0.05) & body & ~opening & (z > 0.4) & (np.abs(x) > 1.75)
    s.carve(chip)


# ====================================================================== the forge's smithy

# The room the forge's anvil stands in (scripts/ui/forge.gd uses the same numbers): its floor's top
# at y = 0, the anvil over its middle, north toward -z. The floor, each wall and the roof are
# models of their own in forge_room.glb, so the game can put a wall away while the camera is out
# beyond it.
FORGE_HX, FORGE_HZ = 4.8, 4.4            # the inside: half its width (x), half its depth (z)
FORGE_T = 0.5                             # the walls' thickness
FORGE_H = 4.0                             # the underside of the beams
FORGE_TOP = 4.5                           # the top of the walls: the roof's planks lie on them
FORGE_PIERS_X = (-3.6, -1.2, 1.2, 3.6)    # piers on the north and south walls, the beams on them
FORGE_PIERS_Z = (-2.8, 2.8)               # piers on the east and west walls
FORGE_DOOR = 1.1                          # the east door: half its width, its arch's radius
FORGE_HEARTH_X = -2.4                     # the hearth's middle, on the north wall

TUFA = (0.47, 0.42, 0.35)
BRICK = (0.50, 0.285, 0.21)
PLASTER = (0.60, 0.51, 0.39)
BASALT = (0.215, 0.205, 0.20)
TIMBER = (0.27, 0.18, 0.11)
STEEL = (0.50, 0.51, 0.53)


def _put(s, mask, col):
    """Sculpt.put for a mask that leaves an axis out (it is spread over the whole grid)."""
    s.put(np.broadcast_to(mask, s.c.shape), col)


def _carve(s, mask):
    s.c[np.broadcast_to(mask, s.c.shape)] = 0


def _rgb(p):
    return np.stack([(p >> 16) & 255, (p >> 8) & 255, p & 255], 1).astype(np.float32)


def shaded(fn, k_of, cell=(0.25, 0.1, 0.25), step=0.04):
    """The colours of `fn` (a packed value or a colour function) times k_of(x, y, z): worked out
    block by block (`cell`, metres) and in steps, so a block stays one colour and flat runs of it
    still merge into big quads."""
    def f(ix, iy, iz, x, y, z):
        p = fn(ix, iy, iz, x, y, z) if callable(fn) else np.full(len(x), fn, np.uint32)
        q = [(np.floor(v / c) + 0.5) * c for v, c in zip((x, y, z), cell)]
        k = np.asarray(k_of(*q), np.float32) + np.zeros(len(x), np.float32)
        k = np.round(k / step) * step
        b = np.clip(np.round(_rgb(p) * k[:, None]), 0, 255).astype(np.uint32)
        return (p & np.uint32(0xFF000000)) | (b[:, 0] << 16) | (b[:, 1] << 8) | b[:, 2]
    return f


def blocks(mat, base, size=(0.5, 0.25, 0.5), var=0.08, seed=1):
    """Pieces of `size` (boards, beams, slabs), each its own shade and nothing more: the shader
    adds the grain, and a piece is one quad a face."""
    def f(ix, iy, iz, x, y, z):
        b = [np.floor(v / c + 1e-6).astype(np.int64) for v, c in zip((x, y, z), size)]
        return pack(mat, tint(base, var, hash3(b[0], b[1], b[2], seed)))
    return f


def _stamp(s, u, y, depth, u0, ytop, rows, pal):
    """Pixel art laid on a face: `rows` (strings, the top row first), a voxel a letter coloured by
    `pal` (a space or a dot: nothing), its left edge at u0 and its top at ytop, through the cells
    of `depth` (a mask). `u` runs along the face."""
    h, w = len(rows), max(len(r) for r in rows)
    grid = np.array([list(r.ljust(w)) for r in rows])
    col = np.floor((u - u0) / s.vs + 1e-6).astype(np.int64)
    row = np.floor((ytop - y) / s.vs - 1e-6).astype(np.int64)
    ok = (col >= 0) & (col < w) & (row >= 0) & (row < h)
    cc = np.clip(col, 0, w - 1)
    rr = np.clip(row, 0, h - 1)
    for ch in sorted(set("".join(rows)) - {" ", "."}):
        _put(s, (grid == ch)[rr, cc] & ok & depth, pal[ch])


# ---------------------------------------------------------------- its floor

def forge_floor(s):
    """The smithy's floor, its top at y = 0: the anvil's dark hearthstone in the middle and a ring
    of basalt slabs round it, a pale band with bronze set in its corners, brick laid herringbone
    out to a border of stone slabs along the walls. Worn pale where feet go (from the door to the
    anvil, from the anvil to the hearth), black with soot before the hearth, cracked and chipped;
    hammer scale round the anvil, crumbs of charcoal by the coal, straw by the door. A layer of
    dark stone under it shows in the chips; the third layer holds what lies on the floor."""
    vs = s.vs
    nx, ny, nz = s.c.shape
    ix, iz = np.meshgrid(np.arange(nx), np.arange(nz), indexing="ij")
    X = s.lo[0] + (ix + 0.5) * vs
    Z = s.lo[2] + (iz + 0.5) * vs
    gx = np.floor(X / vs + 1e-6).astype(np.int64)      # voxel columns, counted from the middle
    gz = np.floor(Z / vs + 1e-6).astype(np.int64)
    m = np.maximum(np.abs(X), np.abs(Z))
    HX, HZ = FORGE_HX, FORGE_HZ
    hearth = (FORGE_HEARTH_X, -HZ + 1.3)

    def soot_at(x, z):
        """How black with soot and ash (0..1): before the hearth, and by the coal in the corner."""
        d = np.sqrt(((x - hearth[0]) / 1.5) ** 2 + ((z - hearth[1]) / 1.15) ** 2)
        k = np.clip(1.3 - d, 0, 1) ** 1.3
        d2 = np.sqrt((x + HX - 0.5) ** 2 + (z + 3.0) ** 2)
        k = np.maximum(k, 0.75 * np.clip(1.0 - d2 / 1.4, 0, 1))
        return k * (0.7 + 0.5 * vnoise(x, 0 * x, z, 0.5, 431))

    def wear_at(x, z):
        """How worn and dusty (0..1): the ways feet go."""
        w = np.exp(-(z / 0.6) ** 2) * np.clip((x - 1.6) / 0.6, 0, 1)                      # from the door
        ax, az, bx, bz = -0.5, -0.9, hearth[0] + 0.3, hearth[1] + 0.1                      # to the hearth
        t = np.clip(((x - ax) * (bx - ax) + (z - az) * (bz - az)) / ((bx - ax) ** 2 + (bz - az) ** 2), 0, 1)
        d = np.sqrt((x - (ax + (bx - ax) * t)) ** 2 + (z - (az + (bz - az) * t)) ** 2)
        w = np.maximum(w, np.exp(-(d / 0.5) ** 2))
        ring = np.maximum(np.abs(x), np.abs(z))                                            # round the anvil
        w = np.maximum(w, 0.7 * np.exp(-((ring - 2.2) / 0.5) ** 2))
        return w * (0.55 + 0.6 * vnoise(x, 0 * x, z, 0.7, 432))

    def weather(c, x, z):
        """A piece's colour where it lies (x, z: its middle): sooted, worn."""
        k = soot_at(x, z)[..., None]
        c = c * (1 - 0.62 * k) + np.array([0.05, 0.045, 0.04]) * (0.3 * k)
        w = np.round(wear_at(x, z) * 4)[..., None] / 4
        return c * (1 + 0.1 * w) + np.array([0.035, 0.03, 0.022]) * w

    rgb = np.zeros((nx, nz, 3), np.float32)
    mat = np.full((nx, nz), V.MAT_ID["stone"], np.uint32)
    joint = np.zeros((nx, nz), bool)
    corner = np.zeros((nx, nz), bool)      # where four pieces meet: a chip, often

    # -- brick laid herringbone: bricks 10 x 30 cm, two voxels wide.
    U = np.floor_divide(gx, 2)
    W = np.floor_divide(gz, 2)
    k6 = np.mod(U - W, 6)
    flat = k6 < 3
    bu = np.where(flat, U - k6, U)
    bw = np.where(flat, W, W - (5 - k6))
    bcx = (bu + np.where(flat, 1.5, 0.5)) * 0.1
    bcz = (bw + np.where(flat, 0.5, 1.5)) * 0.1
    hb = hash3(bu, bw, flat.astype(np.int64), 433)
    hb2 = hash3(bu, bw, flat.astype(np.int64) + 2, 434)
    brick = np.array([0.31, 0.2, 0.155])[None, None, :] * (0.8 + 0.4 * hb)[..., None] * np.where(flat, 1.0, 0.9)[..., None]
    brick[hb2 < 0.07] *= 0.6                                               # burnt black in the kiln
    pale = hb2 > 0.95
    brick[pale] = brick[pale] * 0.5 + np.array([0.2, 0.17, 0.135])        # a paler clay
    rgb[:] = weather(brick, bcx, bcz)

    # -- the border along the walls: slabs 40 cm wide, 80 long, and the stone under the walls.
    inside = (np.abs(X) < HX) & (np.abs(Z) < HZ)
    ns = np.abs(Z) >= HZ - 0.4
    border = inside & (ns | (np.abs(X) >= HX - 0.4))
    along = np.where(ns, X + 0.4 * (Z > 0), Z + 0.4 * (X > 0))
    bi = np.floor(along / 0.8).astype(np.int64)
    side = np.where(ns, np.where(Z > 0, 0, 1), np.where(X > 0, 2, 3))
    hs = hash3(bi, side, 0, 435)
    slab = np.array(TUFA)[None, None, :] * 0.78 * (0.86 + 0.28 * hs)[..., None]
    scx = np.where(ns, (bi + 0.5) * 0.8 - 0.4 * (Z > 0), np.sign(X) * (HX - 0.2))
    scz = np.where(ns, np.sign(Z) * (HZ - 0.2), (bi + 0.5) * 0.8 - 0.4 * (X > 0))
    rgb[border] = weather(slab, scx, scz)[border]
    edge = border & np.where(ns, (np.abs(Z) - (HZ - 0.4)) < vs * 0.99, (np.abs(X) - (HX - 0.4)) < vs * 0.99)
    jb = border & ((along - bi * 0.8) < vs * 0.99)
    joint |= edge | jb
    corner |= edge & jb
    under = ~inside
    rgb[under] = np.array(TUFA) * 0.5 * (0.9 + 0.2 * hash3(np.floor(X / 0.6).astype(np.int64), np.floor(Z / 0.6).astype(np.int64), 0, 436))[under][:, None]

    # -- the threshold of the east door: one long worn slab.
    sill = (X >= HX - 0.4) & (np.abs(Z) < FORGE_DOOR)
    rgb[sill] = np.array([0.42, 0.38, 0.31]) * (0.92 + 0.12 * vnoise(X, 0 * X, Z, 0.4, 437))[sill][:, None]
    joint[sill] = False
    joint |= sill & ((np.abs(np.abs(Z) - FORGE_DOOR) < vs * 1.01) | ((X - (HX - 0.4)) < vs * 0.99))

    # -- round the anvil: a band of pale stone, a ring of basalt slabs, the hearthstone.
    band = (m >= 1.6) & (m < 1.8)
    tb = np.abs(Z) >= np.abs(X)
    al = np.where(tb, X, Z)
    pi_ = np.floor((al + 0.2) / 0.4).astype(np.int64)
    hp = hash3(pi_, tb.astype(np.int64) + 2 * (np.where(tb, Z, X) > 0), 0, 438)
    rgb[band] = (np.array([0.40, 0.36, 0.30])[None, None, :] * (0.86 + 0.24 * hp)[..., None])[band]
    joint[band] = ((al + 0.2) - pi_ * 0.4 < vs * 0.99)[band]
    stud = band & (np.abs(X) >= 1.6) & (np.abs(Z) >= 1.6)
    rgb[stud] = np.array([0.48, 0.33, 0.17])
    mat[stud] = V.MAT_ID["bronze"]
    joint[stud] = False

    ring = m < 1.6
    sx = np.floor(X / 0.8).astype(np.int64)
    sz = np.floor(Z / 0.8).astype(np.int64)
    hr = hash3(sx, sz, 0, 439)
    warm = np.where((hash3(sx, sz, 1, 439) < 0.4)[..., None], np.array([1.05, 1.0, 0.93])[None, None, :], np.array([1.0, 1.0, 1.0])[None, None, :])
    slabc = np.array(BASALT)[None, None, :] * (0.84 + 0.36 * hr)[..., None] * warm
    rgb[ring] = weather(slabc, (sx + 0.5) * 0.8, (sz + 0.5) * 0.8)[ring]
    jr = (X - sx * 0.8 < vs * 0.99) | (Z - sz * 0.8 < vs * 0.99)
    joint[ring] = jr[ring]
    corner |= ring & (X - sx * 0.8 < vs * 0.99) & (Z - sz * 0.8 < vs * 0.99)
    joint |= ((m >= 1.55) & (m < 1.6)) | ((m >= 1.8) & (m < 1.85))

    mid = m < 0.8
    r = np.sqrt(X * X + Z * Z)
    scorch = 0.7 + 0.3 * np.round(np.clip(r / 0.85, 0, 1) * 5) / 5
    rgb[mid] = (np.array(BASALT)[None, None, :] * 0.95 * scorch[..., None])[mid]
    joint[mid] = ((X < -0.8 + vs * 0.99) | (Z < -0.8 + vs * 0.99))[mid]

    # -- cracks across some of the big slabs.
    for (cx, cz, half, ang, seed) in ((0.0, 0.0, 0.8, 0.5, 1), (-1.2, 0.4, 0.4, 2.2, 2), (0.4, 1.2, 0.4, 1.0, 3), (1.2, -1.2, 0.4, 2.7, 4), (-0.4, -1.2, 0.4, 0.2, 5)):
        inslab = (np.abs(X - cx) < half - vs) & (np.abs(Z - cz) < half - vs)
        a, b = math.cos(ang), math.sin(ang)
        tt = (X - cx) * a + (Z - cz) * b
        dd = -(X - cx) * b + (Z - cz) * a + 0.07 * np.sin(tt * 9.0 + seed) + 0.1 * (seed % 3 - 1)
        crack = inslab & (np.abs(dd) < vs * 0.55)
        rgb[crack] *= 0.5
        corner |= crack & (hash3(ix, iz, 0, 440 + seed) < 0.3)

    # -- joints darker; hammer scale and rust flecks round the anvil; chips.
    rgb[joint] *= 0.52
    fleck = (r < 1.25) & ~((np.abs(X) < 0.3) & (np.abs(Z) < 0.2)) & (hash3(ix, iz, 0, 441) < 0.03 * np.clip(1.3 - r, 0, 1))
    rusty_f = fleck & (hash3(ix, iz, 1, 441) < 0.3)
    rgb[fleck] = np.array([0.1, 0.1, 0.11])
    rgb[rusty_f] = np.array([0.2, 0.115, 0.07])
    mat[rusty_f] = V.MAT_ID["rust"]

    packed = (mat << np.uint32(24)) | (np.round(np.clip(rgb, 0, 1) * 255).astype(np.uint32) @ np.array([65536, 256, 1], np.uint32)).astype(np.uint32)
    pit = (corner & (hash3(ix, iz, 2, 442) < 0.4)) | (inside & ~mid & (hash3(ix, iz, 3, 442) < 0.0025))
    s.c[:, 0, :] = pack("stone", (0.085, 0.075, 0.065))
    top = packed.copy()
    top[pit] = 0
    s.c[:, 1, :] = top

    # -- what lies on it: charcoal by the coal and the hearth, straw by the door, grit along the walls.
    lie = np.zeros((nx, nz), np.uint32)
    hd = hash3(ix, iz, 4, 443)
    coal_d = np.minimum(np.sqrt((X + HX - 0.7) ** 2 + (Z + 2.9) ** 2), np.sqrt((X - hearth[0]) ** 2 + ((Z - hearth[1] + 0.5) * 1.6) ** 2))
    coal = inside & (hd < 0.1 * np.clip(1.25 - coal_d, 0, 1)) & (m > 1.9)
    lie[coal] = pack("stone", np.array([0.07, 0.065, 0.065])[None, :] * (0.7 + 0.8 * hash3(ix, iz, 5, 443)[coal])[:, None])
    straw = inside & (X > 2.9) & (np.abs(Z) < 1.6) & (hd < 0.012 * np.clip((X - 2.7) / 1.5, 0, 1)) & ~sill
    lie[straw] = pack("straw", np.array([0.5, 0.41, 0.23])[None, :] * (0.55 + 0.4 * hash3(ix, iz, 6, 443)[straw])[:, None])
    grit = inside & (np.minimum(HX - np.abs(X), HZ - np.abs(Z)) < 0.3) & (hd > 0.985)
    lie[grit] = pack("stone", (0.3, 0.27, 0.23))
    s.c[:, 2, :] = lie


# ---------------------------------------------------------------- its walls

def _wall_frame(s, side):
    """A wall's own coordinates: u along it (the world's x for the north and south walls, z for
    the east and west), d into it from its inner face (negative: out into the room), y up."""
    x, y, z = s.grids()
    if side == "n":
        return x, -FORGE_HZ - z, y
    if side == "s":
        return x, z - FORGE_HZ, y
    if side == "w":
        return z, -FORGE_HX - x, y
    return z, x - FORGE_HX, y


def _smoke(side):
    """How dark a wall's face has gone: with height (the smoke gathers under the roof), and over
    the hearth on the north wall."""
    def k(x, y, z):
        d = 1.0 - 0.3 * np.clip((y - 1.6) / 2.4, 0, 1)
        if side == "n":
            d = d - 0.38 * np.exp(-((x - FORGE_HEARTH_X) / 1.5) ** 2) * np.clip((y - 0.6) / 1.6, 0, 1)
        return d * (0.93 + 0.14 * vnoise(x + z, y, 0 * y, 0.9, 450))
    return k


def _forge_plaster(seed, brick):
    """Rough plaster gone dark, in blotches of a few tones, fallen away in patches to the brick."""
    def f(ix, iy, iz, x, y, z):
        a = x + z
        tone = np.round(vnoise(a, y, 0 * y, 0.8, seed) * 3) / 3
        out = pack("plaster", tint(PLASTER, 0.1, tone))
        gone = vnoise(a, y, 0 * y + 5.0, 0.5, seed + 1) > 0.74
        if gone.any():
            out[gone] = brick(ix[gone], iy[gone], iz[gone], x[gone], y[gone], z[gone])
        return out
    return f


def _mixtum(seed):
    """A wall's field as the Romans built it (opus mixtum): bands of small tufa blocks, two courses
    of them, between bands of two courses of brick."""
    tufa = ashlar("stone", (0.55, 0.49, 0.40), 0.4, 0.2, 0.09, seed=seed, radial=False, mortar=0.78, vs=0.05)
    brick = ashlar("stone", BRICK, 0.25, 0.1, 0.11, seed=seed + 1, radial=False, mortar=0.72, vs=0.05)

    def f(ix, iy, iz, x, y, z):
        stone = np.mod(y - 1.15, 0.6) < 0.4
        out = brick(ix, iy, iz, x, y - 0.05, z)
        if stone.any():
            out[stone] = tufa(ix[stone], iy[stone], iz[stone], x[stone], y[stone] - 0.15, z[stone])
        return out
    return f


def _forge_wall(s, side, piers, seed, opening=None):
    """A wall of the smithy as every wall of it is built: a dado of big tufa blocks on a plinth, a
    string course, bands of tufa and of brick above it, plaster under the roof, and piers of
    travertine standing out of it. Returns its (u, d, y)."""
    u, d, y = _wall_frame(s, side)
    T = FORGE_T
    half = FORGE_HX if side in "ns" else FORGE_HZ
    span = np.abs(u) < half + (T if side in "ns" else 0.0)       # (north and south take the corners)
    room = np.abs(u) < half
    hole = np.zeros(1, bool) if opening is None else opening
    body = (d >= 0) & (d < T) & (y >= 0) & (y < FORGE_TOP) & span & ~hole
    smoke = _smoke(side)
    dado = ashlar("stone", TUFA, 0.6, 0.3, 0.08, seed=seed, radial=False, mortar=0.78, vs=0.05, damp=0.5)
    field = _mixtum(seed + 1)
    _put(s, body & (y < 1.05), dado)
    _put(s, body & (y >= 1.05) & (y < 3.1), shaded(field, smoke, cell=(0.2, 0.1, 0.2)))
    _put(s, body & (y >= 3.1), shaded(_forge_plaster(seed + 2, field), smoke, cell=(0.1, 0.1, 0.1)))
    proud = (d >= -0.05) & (d < 0) & room & ~hole
    _put(s, proud & (y < 0.2), ashlar("stone", (0.33, 0.30, 0.26), 0.9, 0.2, 0.06, seed=seed + 3, radial=False, mortar=0.8, vs=0.05))
    _put(s, proud & (y >= 1.05) & (y < 1.15), ashlar("stone", (0.58, 0.52, 0.43), 0.75, 0.1, 0.06, seed=seed + 4, radial=False, mortar=0.82, vs=0.05))
    stone = shaded(ashlar("stone", (0.60, 0.54, 0.44), 0.5, 0.3, 0.07, seed=seed + 5, radial=False, mortar=0.8, vs=0.05), smoke)
    for pu in piers:
        near = np.abs(u - pu)
        _put(s, (near < 0.25) & (d >= -0.1) & (d < 0) & (y < FORGE_H), stone)
        _put(s, (near < 0.3) & (d >= -0.15) & (d < 0) & (y < 0.25), pack("stone", (0.36, 0.33, 0.28)))
        _put(s, (near < 0.3) & (d >= -0.15) & (d < 0) & (y >= FORGE_H - 0.2) & (y < FORGE_H), pack("stone", (0.46, 0.41, 0.34)))
        _put(s, (near < 0.35) & (d >= -0.2) & (d < 0) & (y >= FORGE_H - 0.1) & (y < FORGE_H), pack("stone", (0.42, 0.38, 0.31)))
    return u, d, y


def _torch(s, u, d, y, pu, yy=2.15):
    """A torch burning in an iron cup on an arm out from a pier, the stone over it black."""
    near = np.abs(u - pu)
    iron = pack("iron", (0.13, 0.125, 0.12))
    _put(s, (near < 0.05) & (d >= -0.35) & (d < -0.1) & (y >= yy - 0.05) & (y < yy), iron)
    _put(s, (near < 0.1) & (d >= -0.4) & (d < -0.2) & (y >= yy) & (y < yy + 0.1), iron)
    _put(s, (near < 0.05) & (d >= -0.35) & (d < -0.25) & (y >= yy + 0.1) & (y < yy + 0.35), pack("wood", (0.2, 0.13, 0.08)))
    _put(s, (near < 0.1) & (d >= -0.4) & (d < -0.2) & (y >= yy + 0.3) & (y < yy + 0.45), pack("ember", (1.0, 0.5, 0.12)))
    _put(s, (near < 0.05) & (d >= -0.35) & (d < -0.25) & (y >= yy + 0.35) & (y < yy + 0.6), pack("ember", (1.0, 0.78, 0.32)))
    soot = (near < 0.25) & (d >= -0.1) & (d < 0) & (y >= yy + 0.45) & (y < yy + 1.3)
    s.recolor(np.broadcast_to(soot, s.c.shape) & (hash3(*np.indices(s.c.shape), 451) < 0.8), pack("stone", (0.17, 0.15, 0.13)))


def _tool_pal():
    return {
        "i": pack("iron", (0.17, 0.165, 0.16)), "I": pack("iron", (0.3, 0.3, 0.31)), "s": pack("iron", STEEL),
        "w": pack("wood", (0.46, 0.31, 0.18)), "W": pack("wood", (0.3, 0.2, 0.12)), "b": pack("bronze", (0.66, 0.47, 0.23)),
        "g": pack("gold", GOLD), "r": pack("plaster", (0.5, 0.11, 0.08)), "R": pack("plaster", (0.36, 0.08, 0.06)),
        "u": pack("plaster", (0.16, 0.24, 0.42)), "o": pack("plaster", (0.62, 0.47, 0.2)), "l": pack("cloth", (0.33, 0.22, 0.13)),
        "e": pack("ember", (1.0, 0.72, 0.3)), "t": pack("terracotta", TERRA), "k": pack("rust", RUST),
    }


TONGS = ["i.i", "i.i", "i.i", ".i.", ".I.", "i.i", "i.i", "i.i", "i.i", "i.i", "i.i", "i.i", "i.i", "i.i"]
TONGS_WIDE = ["ii.ii", "i...i", "i...i", ".i.i.", "..I..", ".i.i.", ".i.i.", ".i.i.", ".i.i.", ".i.i.", ".i.i.", ".i.i.", ".i.i."]
HAMMER = ["IIII", "IIII", ".w..", ".w..", ".w..", ".w..", ".w..", ".w..", ".w..", ".w.."]
SLEDGE = ["IIIIII", "IIIIII", "IIIIII", "..ww..", "..ww..", "..ww..", "..ww..", "..ww..", "..ww..", "..ww..", "..ww..", "..ww..", "..ww..", "..ww.."]
FILE_ = ["s", "s", "s", "s", "s", "s", "s", "w", "w", "w"]
CHISEL = ["I", "I", "I", "I", "I", "s"]
POKER = ["i.", "i.", "i.", "i.", "i.", "i.", "i.", "i.", "i.", "i.", "i.", "i.", "i.", "i.", "i.", "i.", "i.", "ii"]
RAKE = [".i.", ".i.", ".i.", ".i.", ".i.", ".i.", ".i.", ".i.", ".i.", ".i.", ".i.", ".i.", ".i.", ".i.", ".i.", ".i.", "iii", "i.i"]
SHOVEL = [".w.", ".w.", ".w.", ".w.", ".w.", ".w.", ".w.", ".w.", ".w.", ".w.", ".w.", ".w.", ".w.", "III", "III", "III", "III", ".I."]
GLADIUS = [".g.", ".W.", ".W.", ".W.", "bbb", ".s.", ".s.", ".s.", ".s.", ".s.", ".s.", ".s.", ".s.", ".s.", ".s.", ".s.", ".s."]
BLANK = [".k.", ".I.", ".I.", ".I.", ".I.", ".I.", ".I.", ".I.", ".I.", ".I.", ".I.", ".I.", ".I."]
SPATHA = [".b.", ".W.", ".W.", ".W.", "bbb", ".s.", ".s.", ".s.", ".s.", ".s.", ".s.", ".s.", ".s.", ".s.", ".s.", ".s.", ".s.", ".s.", ".s.", ".s.", ".s."]


def _shield(s, u, d, y, uc, yc, face, rad=0.45):
    """A round shield hung on a wall: its face painted, a bronze rim and boss."""
    rr = np.sqrt((u - uc) ** 2 + (y - yc) ** 2)
    _put(s, (rr < rad) & (d >= -0.1) & (d < 0), face)
    _put(s, (rr < rad) & (rr >= rad - 0.07) & (d >= -0.1) & (d < 0), pack("bronze", (0.6, 0.42, 0.21)))
    _put(s, (rr < 0.14) & (d >= -0.15) & (d < 0), pack("bronze", (0.72, 0.52, 0.27)))
    _put(s, (rr < 0.07) & (d >= -0.2) & (d < 0), pack("bronze", (0.78, 0.58, 0.3)))


def forge_wall_n(s):
    """The north wall: the hearth stands against it between two piers (a model of its own, the
    wall behind it black with its smoke); to its right the smith's tools on their board, then a
    niche of shelves (helmets, bars of bronze and iron, a lamp), a shield in the corner."""
    u, d, y = _forge_wall(s, "n", FORGE_PIERS_X, 460)
    pal = _tool_pal()
    for pu in (1.2, 3.6):
        _torch(s, u, d, y, pu)
    # The tools' board, between the piers either side of the wall's middle.
    board = (np.abs(u) < 0.9) & (y >= 1.3) & (y < 2.4) & (d >= -0.05) & (d < 0)
    _put(s, board, blocks("wood", (0.3, 0.2, 0.12), size=(100.0, 0.2, 100.0), var=0.14, seed=461))
    s.recolor(np.broadcast_to(board & (np.mod(y, 0.2) < 0.049), s.c.shape), pack("wood", (0.17, 0.11, 0.07)))
    hang = (d >= -0.1) & (d < -0.05)
    _put(s, (np.abs(u) < 0.85) & (y >= 2.25) & (y < 2.3) & hang, pack("iron", (0.2, 0.19, 0.18)))
    for (u0, rows) in ((-0.8, TONGS), (-0.55, TONGS_WIDE), (-0.2, HAMMER), (0.1, SLEDGE), (0.5, TONGS), (0.7, FILE_), (0.8, CHISEL)):
        _stamp(s, u, y, hang, u0, 2.25, rows, pal)
    # A niche in the wall, arched, shelved.
    uc = 2.4
    spring = 2.0
    arch = (np.abs(u - uc) < 0.6) & (((y >= 1.15) & (y < spring)) | (((u - uc) ** 2 + (y - spring) ** 2 < 0.6 ** 2) & (y >= spring)))
    ring = (np.abs(u - uc) < 0.75) & (((y >= 1.15) & (y < spring)) | (((u - uc) ** 2 + (y - spring) ** 2 < 0.75 ** 2) & (y >= spring))) & ~arch
    seg = np.floor(np.arctan2(y - spring, u - uc) / math.pi * 9).astype(np.int64)
    face = (d >= 0) & (d < 0.05)
    s.recolor(np.broadcast_to(ring & face & (y >= spring) & (np.mod(seg, 2) == 0), s.c.shape), pack("stone", (0.6, 0.54, 0.44)))
    s.recolor(np.broadcast_to(ring & face & (y >= spring) & (np.mod(seg, 2) == 1), s.c.shape), pack("stone", (0.5, 0.45, 0.37)))
    _carve(s, arch & (d >= -0.05) & (d < 0.3) & (y >= 1.15))
    _put(s, arch & (d >= 0.3) & (d < 0.35), shaded(pack("plaster", (0.42, 0.12, 0.09)), lambda a, b, c: 0.75 + 0.35 * vnoise(a, b, 0 * b, 0.4, 462), cell=(0.05, 0.05, 0.05), step=0.08))
    _put(s, (np.abs(u - uc) < 0.6) & (d >= -0.05) & (d < 0.3) & (y >= 1.75) & (y < 1.8), pack("wood", (0.3, 0.2, 0.12)))
    x, yy, z = s.grids()
    zc = -FORGE_HZ - 0.15
    # (The lower shelf: a bronze helmet with its crest, an iron one.)
    for (hx, metal, crest) in ((uc - 0.28, pack("bronze", (0.68, 0.49, 0.24)), pack("plaster", (0.55, 0.1, 0.08))), (uc + 0.28, pack("iron", (0.33, 0.33, 0.35)), 0)):
        dome = ((x - hx) ** 2 + ((yy - 1.3) * 1.05) ** 2 + (z - zc) ** 2 < 0.17 ** 2) & (yy >= 1.15)
        s.put(np.broadcast_to(dome, s.c.shape), metal)
        s.put(np.broadcast_to((np.abs(x - hx) < 0.2) & (yy >= 1.15) & (yy < 1.2) & (np.abs(z - zc) < 0.2), s.c.shape), metal)
        if crest:
            s.put(np.broadcast_to((np.abs(x - hx) < 0.05) & (yy >= 1.4) & (yy < 1.55) & (np.abs(z - zc) < 0.2), s.c.shape) & ~np.broadcast_to(dome, s.c.shape), crest)
        else:
            s.put(np.broadcast_to((np.abs(x - hx) < 0.05) & (yy >= 1.2) & (yy < 1.35) & (z >= zc + 0.1) & (z < zc + 0.2), s.c.shape), pack("iron", (0.1, 0.1, 0.1)))
    # (The upper shelf: bars of bronze and of iron stacked, a lamp burning.)
    for (bx, by, metal) in ((uc - 0.4, 1.8, "b"), (uc - 0.25, 1.8, "b"), (uc - 0.325, 1.9, "b"), (uc + 0.05, 1.8, "I"), (uc + 0.2, 1.8, "I")):
        s.put(np.broadcast_to((x >= bx) & (x < bx + 0.1) & (yy >= by) & (yy < by + 0.1) & (z >= zc - 0.1) & (z < zc + 0.15), s.c.shape), pal[metal])
    s.put(np.broadcast_to((x >= uc + 0.35) & (x < uc + 0.5) & (yy >= 1.8) & (yy < 1.85) & (np.abs(z - zc) < 0.05), s.c.shape), pal["t"])
    s.put(np.broadcast_to((x >= uc + 0.45) & (x < uc + 0.5) & (yy >= 1.85) & (yy < 1.95) & (np.abs(z - zc) < 0.03), s.c.shape), pal["e"])
    # A shield in the east corner, a chain on a ring in the west one.
    _shield(s, u, d, y, 4.3, 1.9, blocks("plaster", (0.5, 0.1, 0.08), size=(0.3, 0.3, 0.3), var=0.1, seed=463), rad=0.4)
    _stamp(s, u, y, hang, -4.45, 2.6, ["III", "I.I", "III", ".i.", ".I.", ".i.", ".I.", ".i.", ".I.", ".i.", ".I.", ".i.", ".I.", "iIi", "i.i", ".ii"], pal)


def forge_wall_w(s):
    """The west wall: fire irons over the coal, a row of blades hung over the rack of arms, and a
    little shrine to Vulcan in a niche, its lamp burning."""
    u, d, y = _forge_wall(s, "w", FORGE_PIERS_Z, 470)
    pal = _tool_pal()
    _torch(s, u, d, y, 2.8)
    hang = (d >= -0.1) & (d < -0.05)
    # Fire irons in the corner by the hearth.
    _put(s, (u > -4.25) & (u < -3.1) & (y >= 2.5) & (y < 2.55) & hang, pack("iron", (0.2, 0.19, 0.18)))
    for (u0, rows) in ((-4.15, POKER), (-3.9, RAKE), (-3.6, SHOVEL), (-3.35, TONGS_WIDE)):
        _stamp(s, u, y, hang, u0, 2.5, rows, pal)
    # Blades on a rail over the rack: finished ones and blanks.
    _put(s, (u > -2.4) & (u < -0.2) & (y >= 3.0) & (y < 3.1) & (d >= -0.1) & (d < 0), blocks("wood", (0.3, 0.2, 0.12), size=(0.5, 1.0, 0.5), var=0.12, seed=471))
    for (u0, rows) in ((-2.3, GLADIUS), (-1.95, SPATHA), (-1.6, BLANK), (-1.25, GLADIUS), (-0.9, BLANK), (-0.55, SPATHA)):
        _stamp(s, u, y, hang, u0, 3.0, rows, pal)
    # The shrine: a little temple front, Vulcan in bronze, a lamp at his feet.
    uc = 3.7
    niche = (np.abs(u - uc) < 0.35) & (y >= 1.35) & (y < 2.15)
    _carve(s, niche & (d >= -0.05) & (d < 0.25))
    _put(s, niche & (d >= 0.25) & (d < 0.3), pack("plaster", (0.4, 0.11, 0.08)))
    marble = pack("marble", (0.8, 0.77, 0.7))
    _put(s, (np.abs(u - uc) < 0.5) & (y >= 1.25) & (y < 1.35) & (d >= -0.15) & (d < 0.25), marble)
    for su in (-1, 1):
        _put(s, (np.abs(u - (uc + su * 0.4)) < 0.05) & (y >= 1.35) & (y < 2.15) & (d >= -0.1) & (d < 0), pack("marble", (0.86, 0.83, 0.77)))
    _put(s, (np.abs(u - uc) < 0.5) & (y >= 2.15) & (y < 2.25) & (d >= -0.15) & (d < 0), marble)
    ped = (y >= 2.25) & (y < 2.25 + (0.5 - np.abs(u - uc)) * 0.55) & (np.abs(u - uc) < 0.5) & (d >= -0.1) & (d < 0)
    _put(s, ped, pack("marble", (0.84, 0.81, 0.74)))
    _put(s, ped & (y >= 2.3) & (np.abs(u - uc) < 0.3 - (y - 2.3)) & (d >= -0.1) & (d < -0.05), pack("plaster", (0.42, 0.11, 0.08)))
    inner = (d >= 0.1) & (d < 0.2)
    _stamp(s, u, y, inner, uc - 0.15, 1.75, [".bb...", ".bb..I", "bbbbbI", ".bb..w", ".bb..w", ".bb...", "b..b..", "b..b.."], pal)
    _stamp(s, u, y, (d >= 0.0) & (d < 0.1), uc + 0.15, 1.45, ["e.", "tt"], pal)


def forge_wall_e(s):
    """The east wall: the way out to the yard, a round arch of travertine with its oak leaves
    swung back; a shelf of bars and jars over the bench."""
    u0_, d0_, y0_ = _wall_frame(s, "e")
    R = FORGE_DOOR
    spring = 2.1
    way = (np.abs(u0_) < R) & ((y0_ < spring) | (u0_ ** 2 + (y0_ - spring) ** 2 < R * R))
    u, d, y = _forge_wall(s, "e", FORGE_PIERS_Z, 480, opening=way & (d0_ > -1.0))
    pal = _tool_pal()
    # The arch: wedge stones round it and blocks down its sides, standing a little out of the wall.
    rr = np.sqrt(u ** 2 + (y - spring) ** 2)
    ringm = (((rr >= R) & (rr < R + 0.35) & (y >= spring)) | ((np.abs(u) >= R) & (np.abs(u) < R + 0.35) & (y < spring))) & (d >= -0.05) & (d < FORGE_T)
    seg = np.floor(np.arctan2(y - spring, u) / math.pi * 11).astype(np.int64)
    course = np.floor(y / 0.3).astype(np.int64)
    tone = np.where(y >= spring, np.mod(seg, 2), np.mod(course, 2))
    _put(s, ringm & (tone == 0), pack("stone", (0.66, 0.6, 0.49)))
    _put(s, ringm & (tone == 1), pack("stone", (0.56, 0.5, 0.41)))
    _put(s, (np.abs(u) < 0.15) & (y >= spring + R - 0.05) & (y < spring + R + 0.45) & (d >= -0.1) & (d < FORGE_T), pack("stone", (0.7, 0.64, 0.52)))
    _put(s, (np.abs(u) < 0.1) & (np.abs(y - (spring + R + 0.2)) < 0.1) & (d >= -0.15) & (d < -0.1), pack("bronze", (0.66, 0.47, 0.23)))
    # The oak leaves swung back flat against the wall inside, iron bands and studs on them.
    for su in (-1, 1):
        foot = (np.abs(u - su * (R + 0.875)) < 0.525) & (y >= 0.05) & (y < 2.9)
        _put(s, foot & (d >= -0.15) & (d < -0.05), blocks("wood", (0.36, 0.24, 0.14), size=(100.0, 100.0, 0.2), var=0.14, seed=481 + su))
        s.recolor(np.broadcast_to(foot & (np.mod(u, 0.2) < 0.049) & (d >= -0.15) & (d < -0.05), s.c.shape), pack("wood", (0.2, 0.13, 0.08)))
        band = foot & ((np.abs(y - 0.5) < 0.075) | (np.abs(y - 1.5) < 0.075) | (np.abs(y - 2.5) < 0.075))
        _put(s, band & (d >= -0.2) & (d < -0.15), pack("iron", (0.16, 0.155, 0.15)))
        stud = band & (np.abs(np.mod(u, 0.2) - 0.1) < 0.03) & (np.abs(np.mod(y, 1.0) - 0.5) < 0.03)
        _put(s, stud & (d >= -0.25) & (d < -0.2), pack("iron", (0.3, 0.29, 0.28)))
    _torch(s, u, d, y, -2.8)
    _torch(s, u, d, y, 2.8)


def forge_wall_s(s):
    """The south wall: two barred windows high up, between them a shield over crossed swords,
    chains on rings in the corners."""
    us, ds, ys = _wall_frame(s, "s")
    wins = np.zeros(1, bool)
    for uc in (-2.4, 2.4):
        wins = wins | ((np.abs(us - uc) < 0.45) & (ys >= 2.3) & (ys < 3.25))
    u, d, y = _forge_wall(s, "s", FORGE_PIERS_X, 490, opening=wins & (ds > -1.0))
    pal = _tool_pal()
    for uc in (-2.4, 2.4):
        near = np.abs(u - uc)
        _put(s, (near < 0.6) & (y >= 2.2) & (y < 2.3) & (d >= -0.1) & (d < FORGE_T), pack("stone", (0.6, 0.54, 0.44)))
        _put(s, (near < 0.6) & (y >= 3.25) & (y < 3.4) & (d >= -0.05) & (d < FORGE_T), pack("stone", (0.55, 0.5, 0.41)))
        bars = (near < 0.45) & (y >= 2.3) & (y < 3.25) & (d >= 0.2) & (d < 0.25) & ((np.abs(np.mod(u - uc + 0.45, 0.2) - 0.1) < 0.026) | (np.abs(y - 2.775) < 0.026))
        _put(s, bars, pack("iron", (0.12, 0.115, 0.11)))
    # The trophy: two swords crossed behind a shield.
    hang = (d >= -0.05) & (d < 0)
    for sg in (-1, 1):
        t = (y - 2.05) / 0.8
        blade = (np.abs((u - sg * 0.55 * t)) < 0.04) & (y >= 1.3) & (y < 2.8) & hang
        _put(s, blade, pack("iron", STEEL))
        _put(s, (np.abs((u - sg * 0.55 * t)) < 0.04) & (y >= 2.8) & (y < 3.0) & hang, pack("wood", (0.3, 0.2, 0.12)))
        _put(s, (np.abs((u - sg * 0.55 * 0.94)) < 0.15) & (y >= 2.75) & (y < 2.8) & hang, pack("bronze", (0.66, 0.47, 0.23)))
    def ringed(ix, iy, iz, x, yy, z):
        rr = np.sqrt(x * x + (yy - 2.05) ** 2)
        return np.where((rr > 0.24) & (rr < 0.33), pack("plaster", (0.62, 0.47, 0.2)), pack("plaster", (0.5, 0.1, 0.08))).astype(np.uint32)
    _shield(s, u, d, y, 0.0, 2.05, ringed, rad=0.5)
    # A shelf over the bench (under the west window): bars of iron and of bronze, jars.
    _put(s, (u > -3.25) & (u < -1.55) & (y >= 1.6) & (y < 1.65) & (d >= -0.3) & (d < 0), pack("wood", (0.3, 0.2, 0.12)))
    for bu in (-3.1, -1.7):
        _put(s, (np.abs(u - bu) < 0.05) & (y >= 1.4) & (y < 1.6) & (d >= -0.25 + (1.6 - y)) & (d < 0), pack("iron", (0.16, 0.155, 0.15)))
    onshelf = (d >= -0.25) & (d < -0.05)
    _stamp(s, u, y, onshelf, -3.0, 1.8, ["..II..", ".IIII.", "IIIIII"], pal)
    _stamp(s, u, y, onshelf, -2.55, 1.8, ["..bb..", ".bbbb.", "bbbbbb"], pal)
    _stamp(s, u, y, (d >= -0.25) & (d < -0.1), -2.1, 1.95, [".tt.", ".tt.", "tttt", "tttt", "tttt", ".tt."], pal)
    _stamp(s, u, y, (d >= -0.2) & (d < -0.1), -1.85, 1.8, ["tt", "tt", "tt"], pal)
    for u0 in (-4.45, 4.3):
        _stamp(s, u, y, (d >= -0.1) & (d < -0.05), u0, 2.6, ["III", "I.I", "III", ".i.", ".I.", ".i.", ".I.", ".i.", ".I.", ".i.", ".I.", ".i."], pal)
    _torch(s, u, d, y, -1.2)
    _torch(s, u, d, y, 1.2)


# ---------------------------------------------------------------- its roof

def forge_roof(s):
    """The roof from under it: four great beams across the room on the piers, joists over them,
    boards over the joists, all dark with smoke; the hearth's chimney goes up through it. Chains
    with hooks hang from the beams by the walls."""
    x, y, z = s.grids()
    H = FORGE_H
    beam = blocks("wood", TIMBER, size=(100.0, 100.0, 1.6), var=0.16, seed=500)
    for px in FORGE_PIERS_X:
        s.put(np.broadcast_to((np.abs(x - px) < 0.15) & (y >= H) & (y < H + 0.3) & (np.abs(z) < FORGE_HZ + 0.25), s.c.shape), beam)
    for k in range(-5, 6):
        zk = k * 0.8
        s.put(np.broadcast_to((np.abs(z - zk) < 0.075) & (y >= H + 0.3) & (y < H + 0.45) & (np.abs(x) < FORGE_HX + 0.25), s.c.shape), blocks("wood", (0.23, 0.155, 0.095), size=(1.2, 100.0, 100.0), var=0.16, seed=501 + k))
    chimney = (np.abs(x - FORGE_HEARTH_X) < 0.45) & (z < -FORGE_HZ + 0.5)
    boards = (y >= H + 0.45) & (y < H + 0.5) & (np.abs(x) < FORGE_HX + FORGE_T) & (np.abs(z) < FORGE_HZ + FORGE_T) & ~chimney
    s.put(np.broadcast_to(boards, s.c.shape), blocks("wood", (0.2, 0.135, 0.085), size=(0.25, 100.0, 1.7), var=0.2, seed=520))
    iron = pack("iron", (0.13, 0.125, 0.12))
    for (cx, cz, n) in ((3.6, -3.2, 14), (-3.6, 3.0, 18), (1.2, 3.6, 12)):
        for k in range(n):
            w = 0.05 if k % 2 == 0 else 0.025
            s.put(np.broadcast_to((np.abs(x - cx) < w) & (np.abs(z - cz) < (0.025 if k % 2 == 0 else 0.05)) & (y >= H - 0.05 * (k + 1)) & (y < H - 0.05 * k), s.c.shape), iron)
        yb = H - 0.05 * n
        s.put(np.broadcast_to((np.abs(x - cx - 0.05) < 0.075) & (np.abs(z - cz) < 0.025) & (y >= yb - 0.05) & (y < yb), s.c.shape), iron)
        s.put(np.broadcast_to((np.abs(x - cx - 0.1) < 0.026) & (np.abs(z - cz) < 0.025) & (y >= yb - 0.15) & (y < yb), s.c.shape), iron)
        s.put(np.broadcast_to((np.abs(x - cx - 0.025) < 0.076) & (np.abs(z - cz) < 0.025) & (y >= yb - 0.2) & (y < yb - 0.15), s.c.shape), iron)


def build_forge_room():
    """forge_room.glb: the floor, the four walls and the roof, each a node of its own."""
    HX, HZ, T = FORGE_HX, FORGE_HZ, FORGE_T
    was = PER_VOX[0]
    PER_VOX[0] = False
    t0 = time.time()
    parts = (
        ("floor", (-HX - T, -0.1, -HZ - T), (HX + T, 0.05, HZ + T), forge_floor, None),
        ("wall_n", (-HX - T, 0.0, -HZ - T), (HX + T, FORGE_TOP, -HZ + 0.45), forge_wall_n, (2, -1, -HZ - T)),
        ("wall_s", (-HX - T, 0.0, HZ - 0.45), (HX + T, FORGE_TOP, HZ + T), forge_wall_s, (2, 1, HZ + T)),
        ("wall_w", (-HX - T, 0.0, -HZ), (-HX + 0.45, FORGE_TOP, HZ), forge_wall_w, (0, -1, -HX - T)),
        ("wall_e", (HX - 0.45, 0.0, -HZ), (HX + T, FORGE_TOP, HZ), forge_wall_e, (0, 1, HX + T)),
        ("roof", (-HX - T, FORGE_H - 1.2, -HZ - T), (HX + T, FORGE_TOP, HZ + T), forge_roof, (1, 1, FORGE_TOP)),
    )
    meshes = {}
    for name, lo, hi, build, hidden in parts:
        s = V.Sculpt(0.05, lo, hi)
        build(s)
        pos, nrm, col, ao = V.mesh(s, 0.0, -0.099 if name == "floor" else -1e9)
        if hidden is not None:
            # The face nobody sees: a wall's outside (the wall is put away while the camera is out
            # beyond it), the roof's top (put away while the camera is over it).
            ax, sg, plane = hidden
            keep = ~((nrm[:, 0] == ax) & (nrm[:, 1] == sg) & (np.abs(pos[:, 0, ax] - plane) < 1e-4))
            pos, nrm, col, ao = pos[keep], nrm[keep], col[keep], ao[keep]
        if name.startswith("wall"):
            keep = ~((nrm[:, 0] == 1) & (nrm[:, 1] == -1) & (pos[:, 0, 1] < 1e-4))      # (its foot, on the floor)
            pos, nrm, col, ao = pos[keep], nrm[keep], col[keep], ao[keep]
        meshes[name] = {m: arr for (g, m), arr in V.primitives((pos, nrm, col, ao)).items()}
    tris = V.write_glb(os.path.join(OUT, "forge_room.glb"), meshes, 0.05)
    PER_VOX[0] = was
    print("forge_room.glb: %d triangles (%.1fs)" % (tris, time.time() - t0))


# ---------------------------------------------------------------- what stands in it

def _coal(seed, lump=0.1):
    """Charcoal: lumps of black, some with a grey bloom of ash, some with a dull blue sheen."""
    def f(ix, iy, iz, x, y, z):
        b = [np.floor(v / lump).astype(np.int64) for v in (x + 0.031, y + 0.017, z + 0.043)]
        h = hash3(b[0], b[1], b[2], seed)
        c = np.array([0.075, 0.07, 0.07])[None, :] * (0.55 + 1.1 * h)[:, None]
        ash = hash3(b[0], b[1], b[2], seed + 1) > 0.88
        c[ash] = np.array([0.23, 0.22, 0.21])
        c *= (0.85 + 0.3 * hash3(ix, iy, iz, seed + 2))[:, None]
        return pack("stone", c)
    return f


def _fire(cx, cz, reach, seed):
    """Live coals: white-yellow at the heart (cx, cz), orange, dull red, black at the edge."""
    def f(ix, iy, iz, x, y, z):
        r = np.sqrt((x - cx) ** 2 + ((z - cz) * 1.2) ** 2)
        h = hash3(ix, iy, iz, seed)
        heat = np.clip(1.0 - r / reach, 0, 1) * (0.5 + 1.0 * h)
        c = np.tile(np.array([0.09, 0.07, 0.06], np.float32), (len(x), 1)) * (0.6 + 0.8 * hash3(ix, iy, iz, seed + 1))[:, None]
        for lim, col in ((0.16, (0.42, 0.09, 0.04)), (0.28, (0.85, 0.24, 0.06)), (0.46, (1.0, 0.52, 0.13)), (0.7, (1.0, 0.84, 0.44))):
            c[heat > lim] = np.array(col)
        out = pack("stone", c)
        hot = heat > 0.16
        out[hot] = pack("ember", c[hot])
        return out
    return f


def forge_hearth(s):
    """The smithy's hearth, built against the wall behind it (2 m wide, its front toward +z): a
    brick table with an arched store of charcoal and split logs under it, a bed of live coals in
    its top with a blade heating in them, brick cheeks and a plastered hood that draws the smoke
    up a chimney through the roof; pokers hung on its cheeks, tongs laid on its rim."""
    x, y, z = s.grids()
    was = PER_VOX[0]
    PER_VOX[0] = False        # (a brick one shade: the shader's grain is enough, and its faces merge)
    brick = ashlar("stone", BRICK, 0.25, 0.1, 0.11, seed=410, radial=False, mortar=0.72, vs=0.05)
    black = shaded(brick, lambda a, b, c: 0.34 + 0 * a)
    rim = ashlar("stone", (0.36, 0.33, 0.30), 0.5, 0.1, 0.08, seed=411, radial=False, mortar=0.8, vs=0.05)
    s.box((-1.0, 0, -0.6), (1.0, 0.85, 0.6), brick)
    s.box((-1.05, 0.85, -0.6), (1.05, 0.95, 0.65), rim)
    # The store under it.
    arch = (np.abs(x) < 0.45) & ((y < 0.3) | (x * x + (y - 0.3) ** 2 < 0.45 ** 2))
    store = arch & (z > -0.15)
    ring = (np.abs(x) < 0.6) & ((y < 0.3) | (x * x + (y - 0.3) ** 2 < 0.6 ** 2)) & ~arch & (z >= 0.55) & (y < 0.85)
    seg = np.floor(np.arctan2(y - 0.3, x) / math.pi * 7).astype(np.int64)
    s.recolor(np.broadcast_to(ring & (y >= 0.3) & (np.mod(seg, 2) == 0), s.c.shape), pack("stone", (0.6, 0.34, 0.25)))
    s.recolor(np.broadcast_to(ring & (y >= 0.3) & (np.mod(seg, 2) == 1), s.c.shape), pack("stone", (0.42, 0.22, 0.16)))
    s.recolor(np.broadcast_to((np.abs(x) < 0.55) & (y < 0.8) & (z > -0.2) & (z < 0.55), s.c.shape), black)
    _carve(s, store)
    lumps = store & (z < 0.5) & (y < 0.16 + 0.14 * vnoise(x, 0 * x, z, 0.14, 412) - 0.25 * np.clip(z - 0.2, 0, 1))
    _put(s, lumps, _coal(413))
    for (lx, ly, r) in ((-0.22, 0.3, 0.075), (0.02, 0.31, 0.07), (0.25, 0.28, 0.075), (-0.1, 0.43, 0.07), (0.14, 0.42, 0.065)):
        log = ((x - lx) ** 2 + (y - ly) ** 2 < r * r) & (z > -0.1) & (z < 0.45)
        _put(s, log, pack("wood", (0.25, 0.17, 0.1)))
        _put(s, log & (z >= 0.4), pack("wood", (0.62, 0.47, 0.28)))
    # The bed of coals in its top, a blade heating in them.
    bed = (np.abs(x) < 0.75) & (z > -0.45) & (z < 0.4)
    _carve(s, bed & (y >= 0.8) & (y < 0.95))
    heap = 0.87 + 0.06 * vnoise(x, 0 * x, z, 0.13, 414) + 0.09 * np.exp(-((x + 0.2) ** 2 + (z + 0.1) ** 2) / 0.12)
    _put(s, bed & (y >= 0.8) & (y < heap), _fire(-0.2, -0.1, 0.72, 415))

    def hot_iron(ix, iy, iz, xx, yy, zz):
        t = np.clip((xx + 0.25) / 0.85, 0, 1)        # 0 in the fire, 1 at the end the smith holds
        c = np.tile(np.array([0.2, 0.2, 0.21], np.float32), (len(xx), 1))
        out = pack("iron", c)
        for lim, col in ((0.62, (0.5, 0.11, 0.05)), (0.48, (0.95, 0.34, 0.08)), (0.3, (1.0, 0.72, 0.3))):
            m = t < lim
            out[m] = pack("ember", np.tile(np.array(col, np.float32), (int(m.sum()), 1))) if m.any() else out[m]
        return out
    s.seg((-0.25, 0.99, -0.1), (0.6, 1.02, 0.42), 0.036, hot_iron)
    s.seg((0.55, 1.02, 0.4), (0.75, 1.02, 0.52), 0.045, pack("wood", (0.3, 0.2, 0.12)))
    iron = pack("iron", (0.15, 0.145, 0.14))
    s.seg((-0.95, 0.975, 0.5), (-0.35, 0.975, 0.56), 0.027, iron)                     # tongs on the rim
    s.seg((-0.95, 0.975, 0.58), (-0.35, 0.975, 0.5), 0.027, iron)
    s.seg((-1.08, 0.97, -0.1), (-0.7, 0.93, -0.1), 0.055, pack("terracotta", (0.5, 0.3, 0.2)))   # the bellows' pipe
    # The cheeks, the fire back, the hood and the chimney.
    for sx in (-1, 1):
        s.box((min(sx * 0.8, sx * 1.0), 0.95, -0.6), (max(sx * 0.8, sx * 1.0), 2.0, 0.15), brick)
        s.box((sx * 0.9 - 0.025, 1.25, 0.15), (sx * 0.9 + 0.025, 1.9, 0.2), iron)                  # a poker hung on it
        s.box((sx * 0.9 - 0.025, 1.9, 0.15), (sx * 0.9 + 0.075, 1.95, 0.2), iron)
        s.box((sx * 0.9 - 0.025, 1.2, 0.15), (sx * 0.9 + (0.075 if sx > 0 else 0.025), 1.25, 0.25), iron)
    s.box((-0.8, 0.95, -0.6), (0.8, 2.0, -0.5), black)
    inner = (np.abs(x) < 0.85) & (np.abs(x) >= 0.8) & (y >= 0.95) & (y < 2.0) & (z > -0.6) & (z < 0.15)
    s.recolor(np.broadcast_to(inner, s.c.shape), black)
    s.box((-1.1, 1.9, -0.6), (1.1, 2.05, 0.25), ashlar("stone", (0.55, 0.5, 0.41), 0.55, 0.15, 0.06, seed=416, radial=False, mortar=0.82, vs=0.05))
    t = np.clip((y - 2.05) / 1.25, 0, 1)
    hood = (y >= 2.05) & (y < 3.3) & (np.abs(x) < 1.05 - 0.65 * t) & (z >= -0.6) & (z < 0.2 - 0.35 * t)

    def hood_c(ix, iy, iz, xx, yy, zz):
        tone = np.round(vnoise(xx + zz, yy, 0 * yy, 0.6, 417) * 3) / 3
        c = tint(PLASTER, 0.1, tone) * (0.62 + 0.22 * np.clip((yy - 2.05) / 1.2, 0, 1))[:, None]
        out = pack("plaster", c)
        low = yy < 2.2
        if low.any():
            out[low] = brick(ix[low], iy[low], iz[low], xx[low], yy[low], zz[low])
        return out
    _put(s, hood, hood_c)
    _put(s, (np.abs(x) < 0.4) & (z >= -0.6) & (z < -0.15) & (y >= 3.3) & (y < 4.6), shaded(brick, lambda a, b, c: 0.7 + 0 * a))
    # (Under the hood, looking up: black.)
    under = (y >= 2.0) & (y < 2.1) & (np.abs(x) < 0.8) & (z > -0.5) & (z < 0.15)
    _carve(s, under & (y < 2.05))
    s.recolor(np.broadcast_to(under, s.c.shape), pack("stone", (0.06, 0.05, 0.045)))
    PER_VOX[0] = was


def forge_bellows(s):
    """The hearth's bellows on its trestles (the nozzle toward +x, 0.9 m up): two pear-shaped
    boards with pleated leather between, studded with bronze; a post beside it carries the pole
    that works it, a rope from the pole's one end to the upper board, a pull hanging from the
    other."""
    x, y, z = s.grids()
    wd = blocks("wood", (0.33, 0.22, 0.13), size=(0.4, 0.4, 0.4), var=0.14, seed=420)
    for xx in (-0.45, 0.15):
        for zz in (-0.25, 0.25):
            s.box((xx - 0.05, 0, zz - 0.05), (xx + 0.05, 0.7, zz + 0.05), wd)
        s.box((xx - 0.05, 0.6, -0.3), (xx + 0.05, 0.7, 0.3), wd)
    for zz in (-0.25, 0.25):
        s.box((-0.5, 0.25, zz - 0.025), (0.2, 0.35, zz + 0.025), wd)
    t = np.clip((x + 0.6) / 0.9, 0, 1)                       # 0 at its broad back, 1 at the nozzle's root
    halfw = 0.05 + 0.3 * np.sqrt(np.clip(1.0 - t ** 2.4, 0, 1)) * np.clip((x + 0.64) / 0.12, 0, 1)
    lift = np.round(0.3 * (1.0 - t) / 0.05) * 0.05          # open at the back, hinged at the nozzle
    plan = (x >= -0.6) & (x < 0.3) & (np.abs(z) < halfw)
    board = blocks("wood", (0.4, 0.27, 0.15), size=(100.0, 100.0, 0.15), var=0.12, seed=421)
    _put(s, plan & (y >= 0.7) & (y < 0.75), board)
    _put(s, plan & (y >= 0.8 + lift) & (y < 0.85 + lift), board)
    layer = np.floor((y - 0.75) / 0.05 + 1e-6).astype(np.int64)
    fold = np.where(np.mod(layer, 2) == 0, 0.05, 0.0)
    leather = (x >= -0.57) & (x < 0.27) & (np.abs(z) < halfw - 0.02 - fold) & (y >= 0.75) & (y < 0.8 + lift)
    _put(s, leather & (np.mod(layer, 2) == 0), pack("cloth", (0.2, 0.125, 0.075)))
    _put(s, leather & (np.mod(layer, 2) == 1), pack("cloth", (0.33, 0.21, 0.12)))
    studs = plan & (np.abs(z) > halfw - 0.06) & (np.mod(np.floor(x / 0.05), 3) == 0) & (y >= 0.85 + lift) & (y < 0.9 + lift)
    _put(s, studs, pack("bronze", (0.7, 0.5, 0.25)))
    s.seg((0.25, 0.8, 0.0), (0.56, 0.9, 0.0), 0.055, pack("iron", (0.17, 0.165, 0.16)))
    s.seg((0.45, 0.87, 0.0), (0.63, 0.93, 0.0), 0.035, pack("iron", (0.12, 0.115, 0.11)))
    # The post beside it, the pole on the post, the rope down to the upper board, the pull.
    rope = pack("straw", (0.5, 0.42, 0.26))
    s.box((-0.25, 0, 0.36), (-0.15, 1.75, 0.46), wd)
    s.seg((-0.58, 1.7, 0.41), (0.5, 1.55, 0.41), 0.04, pack("wood", (0.4, 0.27, 0.15)))
    s.box((-0.6, 1.65, 0.0), (-0.5, 1.7, 0.41), pack("wood", (0.4, 0.27, 0.15)))
    s.box((-0.575, 1.2, 0.0), (-0.525, 1.65, 0.05), rope)
    s.box((0.45, 1.1, 0.385), (0.5, 1.55, 0.435), rope)
    s.box((0.4, 1.05, 0.385), (0.55, 1.1, 0.435), pack("wood", (0.3, 0.2, 0.12)))


def forge_coal(s):
    """The charcoal: a bin of dark boards against the wall (its open front toward +z), heaped,
    spilling out onto the floor, a shovel stuck in the heap and a basket of it before the bin."""
    x, y, z = s.grids()
    bd = blocks("wood", (0.3, 0.2, 0.12), size=(100.0, 0.2, 100.0), var=0.16, seed=425)
    post = pack("wood", (0.2, 0.13, 0.08))
    s.box((-0.55, 0, -0.5), (0.55, 0.95, -0.45), bd)
    for sx in (-0.55, 0.5):
        side = (x >= sx) & (x < sx + 0.05) & (z >= -0.5) & (z < 0.35) & (y < 0.9 - 0.75 * np.clip((z + 0.45) / 0.8, 0, 1))
        _put(s, side, bd)
        s.box((sx, 0, -0.5), (sx + 0.05, 1.0, -0.4), post)
        s.box((sx, 0, 0.3), (sx + 0.05, 0.3, 0.4), post)
    s.box((-0.55, 0, 0.3), (0.55, 0.2, 0.35), bd)
    hill = 0.72 - 0.75 * np.clip((z + 0.45) / 0.9, 0, 1) - 0.25 * np.abs(x) + 0.1 * vnoise(x, 0 * x, z, 0.16, 426)
    heap = (x >= -0.5) & (x < 0.5) & (z >= -0.45) & (z < 0.3) & (y < hill)
    _put(s, heap, _coal(427))
    spill = (x >= -0.55) & (x < 0.1) & (z >= 0.35) & (z < 0.75) & (y < 0.02 + 0.12 * vnoise(x, 0 * x, z, 0.1, 428) - 0.28 * (z - 0.35))
    _put(s, spill, _coal(429))
    s.seg((-0.2, 0.4, -0.1), (0.05, 1.25, -0.4), 0.03, pack("wood", (0.45, 0.31, 0.18)))
    s.box((-0.32, 0.25, -0.15), (-0.1, 0.45, -0.05), pack("iron", (0.2, 0.195, 0.19)))
    # The basket.
    bx, bz = 0.33, 0.6
    d = np.sqrt((x - bx) ** 2 + (z - bz) ** 2)
    wall = (d < 0.2 + 0.04 * np.clip(y / 0.3, 0, 1)) & (y < 0.32)
    weave = np.mod(np.floor(y / 0.05) + np.floor(np.arctan2(z - bz, x - bx) * 5), 2)
    _put(s, wall & (weave == 0), pack("straw", (0.55, 0.43, 0.24)))
    _put(s, wall & (weave == 1), pack("straw", (0.42, 0.32, 0.17)))
    _carve(s, (d < 0.15) & (y >= 0.2))
    _put(s, (d < 0.15) & (y >= 0.2) & (y < 0.27 + 0.06 * vnoise(x, 0 * x, z, 0.08, 430)), _coal(431, 0.05))


def forge_trough(s):
    """The quenching trough, cut from one block of grey stone, dark water in it; a blade cooling
    against its rim, a ladle hung on its end, and a bucket by it."""
    x, y, z = s.grids()
    st = ashlar("stone", (0.4, 0.385, 0.36), 0.75, 0.25, 0.06, seed=435, radial=False, mortar=0.88, vs=0.05, damp=0.8)
    s.box((-0.75, 0, -0.3), (0.75, 0.55, 0.3), st)
    basin = (np.abs(x) < 0.65) & (np.abs(z) < 0.2)
    _carve(s, basin & (y >= 0.15))
    _put(s, basin & (y >= 0.15) & (y < 0.45), pack("glow", (0.05, 0.085, 0.1)))
    chips = (hash3(*np.indices(s.c.shape), 436) < 0.1) & np.broadcast_to((y >= 0.5) & ~basin, s.c.shape)
    s.c[chips] = 0
    s.seg((-0.35, 0.3, -0.05), (0.15, 0.82, 0.24), 0.03, pack("iron", (0.33, 0.33, 0.35)))
    s.seg((0.15, 0.82, 0.24), (0.24, 0.92, 0.28), 0.035, pack("rust", RUST))
    s.box((0.75, 0.3, -0.025), (0.8, 0.6, 0.025), pack("iron", (0.17, 0.165, 0.16)))
    s.box((0.65, 0.55, -0.025), (0.8, 0.6, 0.025), pack("iron", (0.17, 0.165, 0.16)))
    s.box((0.75, 0.2, -0.075), (0.85, 0.3, 0.075), pack("iron", (0.2, 0.195, 0.19)))
    # The bucket: staves, two hoops, a rope handle.
    d = np.sqrt((x + 1.05) ** 2 + (z - 0.1) ** 2)
    stave = np.floor(np.arctan2(z - 0.1, x + 1.05) / (2 * math.pi) * 12).astype(np.int64)
    _put(s, (d < 0.2) & (y < 0.36), blocks("wood", (0.42, 0.29, 0.17), size=(0.07, 100.0, 0.07), var=0.2, seed=437))
    _put(s, (d < 0.21) & (d >= 0.15) & ((np.abs(y - 0.08) < 0.026) | (np.abs(y - 0.28) < 0.026)), pack("iron", (0.17, 0.165, 0.16)))
    _carve(s, (d < 0.15) & (y >= 0.1))
    _put(s, (d < 0.15) & (y >= 0.1) & (y < 0.27), pack("glow", (0.05, 0.085, 0.1)))


def forge_bench(s):
    """The work bench against the wall (its front toward +z): a thick top on four legs, a vise at
    its corner; on it a helmet being raised, a blade, a hammer, bars of bronze, a lamp burning;
    a box and bars of iron on the shelf under it."""
    x, y, z = s.grids()
    wd = blocks("wood", (0.36, 0.24, 0.14), size=(0.4, 0.4, 0.4), var=0.14, seed=440)
    s.box((-0.9, 0.78, -0.35), (0.9, 0.88, 0.35), blocks("wood", (0.4, 0.27, 0.155), size=(100.0, 100.0, 0.175), var=0.16, seed=441))
    s.recolor(np.broadcast_to((np.mod(z + 0.35, 0.175) < 0.049) & (y >= 0.78) & (y < 0.88) & (np.abs(x) < 0.9), s.c.shape), pack("wood", (0.22, 0.145, 0.085)))
    for sx in (-0.8, 0.8):
        for sz in (-0.27, 0.27):
            s.box((sx - 0.05, 0, sz - 0.05), (sx + 0.05, 0.78, sz + 0.05), wd)
        s.box((sx - 0.05, 0.22, -0.3), (sx + 0.05, 0.3, 0.3), wd)
    s.box((-0.85, 0.3, -0.3), (0.85, 0.35, 0.3), blocks("wood", (0.33, 0.22, 0.13), size=(100.0, 100.0, 0.2), var=0.16, seed=442))
    iron = pack("iron", (0.17, 0.165, 0.16))
    # The vise.
    s.box((-0.9, 0.62, 0.35), (-0.7, 1.0, 0.4), iron)
    s.box((-0.9, 0.62, 0.45), (-0.7, 1.0, 0.5), iron)
    s.seg((-0.8, 0.72, 0.3), (-0.8, 0.72, 0.62), 0.03, pack("iron", (0.3, 0.3, 0.31)))
    s.seg((-0.92, 0.72, 0.6), (-0.68, 0.72, 0.6), 0.026, pack("iron", (0.3, 0.3, 0.31)))
    # On it.
    bz = pack("bronze", (0.72, 0.52, 0.26))
    dome = ((x + 0.4) ** 2 + ((y - 0.88) * 0.95) ** 2 + (z + 0.02) ** 2 < 0.165 ** 2) & (y >= 0.88)
    _put(s, dome, bz)
    _put(s, (np.abs(x + 0.4) < 0.2) & (np.abs(z + 0.02) < 0.2) & (y >= 0.88) & (y < 0.93) & ((x + 0.4) ** 2 + (z + 0.02) ** 2 < 0.21 ** 2), pack("bronze", (0.62, 0.44, 0.22)))
    s.box((0.0, 0.88, -0.2), (0.6, 0.93, -0.15), pack("iron", STEEL))
    s.box((0.05, 0.88, -0.25), (0.6, 0.93, -0.1), pack("iron", STEEL))
    s.box((-0.15, 0.88, -0.2), (0.0, 0.93, -0.15), pack("iron", (0.3, 0.3, 0.31)))
    s.box((0.55, 0.88, 0.05), (0.7, 0.98, 0.15), pack("iron", (0.2, 0.2, 0.21)))
    s.seg((0.62, 0.93, 0.1), (0.25, 0.92, 0.25), 0.026, pack("wood", (0.46, 0.31, 0.18)))
    for (bx, by) in ((-0.05, 0.88), (0.08, 0.88), (0.015, 0.93)):
        s.box((bx, by, 0.05), (bx + 0.1, by + 0.05, 0.3), pack("bronze", (0.66, 0.47, 0.23)))
    s.box((0.7, 0.88, -0.3), (0.85, 0.93, -0.2), pack("terracotta", TERRA))
    s.box((0.8, 0.93, -0.275), (0.85, 1.03, -0.225), pack("ember", (1.0, 0.72, 0.3)))
    # Under it.
    s.box((-0.6, 0.35, -0.2), (-0.15, 0.65, 0.2), blocks("wood", (0.44, 0.31, 0.18), size=(100.0, 0.1, 100.0), var=0.14, seed=443))
    s.box((-0.62, 0.35, -0.22), (-0.13, 0.4, 0.22), pack("wood", (0.22, 0.145, 0.085)))
    s.box((-0.62, 0.6, -0.22), (-0.13, 0.65, 0.22), pack("wood", (0.22, 0.145, 0.085)))
    for k in range(5):
        s.box((0.1 + 0.11 * k, 0.35, -0.2), (0.2 + 0.11 * k - 0.01, 0.4 + 0.05 * (k % 2), 0.25), pack("iron", (0.24 + 0.03 * (k % 3), 0.24 + 0.03 * (k % 3), 0.25 + 0.03 * (k % 3))))


def forge_grindstone(s):
    """The grindstone: a wheel of pale stone on an iron axle between two trestles, a crank on its
    end, and a trough of water under it."""
    x, y, z = s.grids()
    wd = blocks("wood", (0.36, 0.24, 0.14), size=(0.4, 0.4, 0.4), var=0.14, seed=445)
    for zf in (-0.25, 0.25):
        for sx in (-1, 1):
            s.seg((sx * 0.45, 0.0, zf), (sx * 0.06, 0.82, zf), 0.05, wd)
        s.box((-0.3, 0.25, zf - 0.025), (0.3, 0.33, zf + 0.025), wd)
    s.seg((0, 0.78, -0.34), (0, 0.78, 0.38), 0.03, pack("iron", (0.2, 0.195, 0.19)))
    rr = np.sqrt(x * x + (y - 0.78) ** 2)
    wheel = (rr < 0.43) & (np.abs(z) < 0.1)

    def stone_c(ix, iy, iz, xx, yy, zz):
        r = np.sqrt(xx * xx + (yy - 0.78) ** 2)
        band = np.floor(r / 0.1).astype(np.int64)
        c = tint((0.56, 0.54, 0.49), 0.07, hash3(band, 0, 0, 446)) * tint((1, 1, 1), 0.05, hash3(ix, iy, iz, 447))
        c[r > 0.38] *= 0.86
        return pack("stone", c)
    _put(s, wheel, stone_c)
    _put(s, (rr < 0.1) & (np.abs(z) < 0.15), pack("wood", (0.3, 0.2, 0.12)))
    s.seg((0, 0.78, 0.38), (0.2, 0.7, 0.38), 0.027, pack("iron", (0.2, 0.195, 0.19)))
    s.seg((0.2, 0.7, 0.36), (0.2, 0.7, 0.5), 0.03, pack("wood", (0.46, 0.31, 0.18)))
    s.box((-0.4, 0.12, -0.15), (0.4, 0.33, 0.15), blocks("wood", (0.33, 0.22, 0.13), size=(100.0, 0.1, 100.0), var=0.14, seed=448))
    _carve(s, (np.abs(x) < 0.35) & (np.abs(z) < 0.1) & (y >= 0.17) & (y < 0.33) & (rr >= 0.43))
    _put(s, (np.abs(x) < 0.35) & (np.abs(z) < 0.1) & (y >= 0.17) & (y < 0.28) & (rr >= 0.43), pack("glow", (0.05, 0.085, 0.1)))


def forge_stump(s):
    """The smith's own anvil: a block of iron with a horn, on an oak stump bound with iron; his
    hammer left on its face, tongs leant against it."""
    x, y, z = s.grids()
    d = np.sqrt(x * x + z * z)
    ang = np.arctan2(z, x)
    bark = np.floor(ang / (2 * math.pi) * 22).astype(np.int64)

    def stump_c(ix, iy, iz, xx, yy, zz):
        dd = np.sqrt(xx * xx + zz * zz)
        b = np.floor(np.arctan2(zz, xx) / (2 * math.pi) * 22).astype(np.int64)
        c = tint((0.24, 0.165, 0.1), 0.2, hash3(b, 0, 0, 450))
        top = yy > 0.5
        ringc = np.where(np.mod(np.floor(dd / 0.05), 2) == 0, 1.0, 0.86)
        c[top] = (np.array([0.55, 0.41, 0.25])[None, :] * ringc[top][:, None])
        c[top & (dd > 0.25)] = np.array([0.24, 0.165, 0.1])
        return pack("wood", c)
    _put(s, (d < 0.3 + 0.02 * (np.mod(bark, 3) == 0)) & (y < 0.55), stump_c)
    _put(s, (d < 0.33) & (d >= 0.27) & (np.abs(y - 0.42) < 0.026), rusty(IRON, seed=451, amount=0.4))
    _put(s, (d < 0.33) & (d >= 0.27) & (np.abs(y - 0.12) < 0.026), rusty(IRON, seed=452, amount=0.4))
    ir = pack("iron", (0.19, 0.19, 0.2))
    s.box((-0.15, 0.55, -0.1), (0.15, 0.6, 0.1), ir)
    s.box((-0.1, 0.6, -0.075), (0.1, 0.7, 0.075), ir)
    s.box((-0.2, 0.7, -0.1), (0.2, 0.85, 0.1), ir)
    s.box((-0.2, 0.8, -0.1), (0.2, 0.85, 0.1), pack("iron", (0.4, 0.4, 0.42)))
    s.box((0.2, 0.75, -0.075), (0.3, 0.85, 0.075), ir)
    s.box((0.3, 0.775, -0.05), (0.4, 0.85, 0.05), ir)
    s.box((0.4, 0.8, -0.025), (0.45, 0.85, 0.025), ir)
    s.box((-0.15, 0.85, -0.05), (0.0, 0.95, 0.05), pack("iron", (0.26, 0.26, 0.27)))
    s.seg((-0.075, 0.9, 0.0), (0.3, 0.9, -0.3), 0.026, pack("wood", (0.46, 0.31, 0.18)))
    s.seg((-0.42, 0.0, 0.18), (-0.3, 0.78, 0.04), 0.026, pack("iron", (0.15, 0.145, 0.14)))
    s.seg((-0.36, 0.0, 0.26), (-0.32, 0.78, 0.1), 0.026, pack("iron", (0.15, 0.145, 0.14)))


def forge_barrel(s):
    """A barrel of blanks: staves and three iron hoops, bars for blades and shafts for spears
    stood in it."""
    x, y, z = s.grids()
    prof = lambda t: 0.25 + 0.06 * np.sin(np.clip(t, 0, 1) * math.pi)
    body = s.lathe_mask((0, 0, 0), prof, 0, 0.85)
    _put(s, body, blocks("wood", (0.4, 0.28, 0.16), size=(0.08, 100.0, 0.08), var=0.2, seed=455))
    d = np.sqrt(x * x + z * z)
    for hy in (0.1, 0.42, 0.74):
        rr_ = 0.25 + 0.06 * math.sin(hy / 0.85 * math.pi)
        _put(s, (d < rr_ + 0.02) & (d >= rr_ - 0.05) & (np.abs(y - hy) < 0.026), rusty(IRON, seed=456, amount=0.35))
    _carve(s, (d < 0.2) & (y >= 0.6))
    for (ax, az, bx, bz, top, kind) in ((0.05, 0.0, 0.16, 0.05, 1.45, "s"), (-0.08, 0.06, -0.2, 0.14, 1.3, "i"), (0.0, -0.1, 0.04, -0.22, 1.55, "w"),
                                                       (-0.1, -0.06, -0.24, -0.1, 1.2, "i"), (0.1, 0.1, 0.22, 0.2, 1.1, "s"), (0.02, 0.04, -0.05, 0.02, 1.5, "w")):
        col = {"s": pack("iron", STEEL), "i": pack("iron", (0.22, 0.22, 0.23)), "w": pack("wood", (0.5, 0.36, 0.2))}[kind]
        s.seg((ax, 0.3, az), (bx, top, bz), 0.026, col)
        if kind == "w":
            s.seg((bx, top - 0.02, bz), (bx + (bx - ax) * 0.12, top + 0.2, bz + (bz - az) * 0.12), 0.036, pack("iron", STEEL))


def forge_sacks(s):
    """Sacks of ore piled against a wall, one tipped over and spilling."""
    x, y, z = s.grids()

    def sack(c, r, sq, seed, tied=True):
        m = (((x - c[0]) / r[0]) ** 2 + ((y - c[1]) / r[1]) ** 2 + ((z - c[2]) / r[2]) ** 2 < 1.0) & (y >= 0)
        tone = (0.56 + 0.1 * (seed % 3), 0.48 + 0.08 * (seed % 3), 0.34 + 0.06 * (seed % 3))
        _put(s, m, blocks("cloth", tone, size=(0.15, 0.1, 0.15), var=0.08, seed=seed))
        if tied:
            _put(s, (np.abs(x - c[0]) < 0.06) & (np.abs(z - c[2]) < 0.06) & (y >= c[1] + r[1] - 0.05) & (y < c[1] + r[1] + 0.1), pack("cloth", (0.45, 0.38, 0.27)))
            _put(s, (np.abs(x - c[0]) < 0.08) & (np.abs(z - c[2]) < 0.08) & (y >= c[1] + r[1]) & (y < c[1] + r[1] + 0.05), pack("straw", (0.4, 0.3, 0.16)))
    sack((-0.3, 0.22, -0.1), (0.27, 0.3, 0.22), 0, 460)
    sack((0.25, 0.2, -0.12), (0.26, 0.28, 0.22), 0, 461)
    sack((-0.02, 0.62, -0.14), (0.26, 0.24, 0.2), 0, 462)
    sack((0.1, 0.13, 0.28), (0.3, 0.15, 0.17), 0, 463, tied=False)
    ore = (x > 0.3) & (x < 0.62) & (np.abs(z - 0.28) < 0.14) & (y < 0.03 + 0.1 * vnoise(x, 0 * x, z, 0.09, 464) - 0.25 * (x - 0.3))

    def ore_c(ix, iy, iz, xx, yy, zz):
        h = hash3(ix, iy, iz, 465)
        c = np.tile(np.array([0.3, 0.19, 0.14], np.float32), (len(xx), 1)) * (0.7 + 0.6 * h)[:, None]
        c[h > 0.8] = np.array([0.42, 0.4, 0.38])
        return pack("stone", c)
    _put(s, ore, ore_c)


PROPS = {
    "brazier": ((-0.45, 0, -0.45), (0.45, 1.6, 0.45), brazier),
    "gate_door": ((-0.25, 0, -0.05), (0.25, 2.45, 2.65), gate_door),
    "ludus_gate": ((-2.1, 0, -0.65), (2.1, 4.45, 0.8), ludus_gate),
    "statue": ((-0.5, 0, -0.5), (0.5, 3.0, 0.5), statue),
    "amphora": ((-0.24, 0, -0.24), (0.24, 0.84, 0.24), amphora, 0.04),
    "amphora_wide": ((-0.32, 0, -0.32), (0.32, 0.68, 0.32), lambda s: amphora(s, True), 0.04),
    "crate": ((-0.32, 0, -0.32), (0.32, 0.62, 0.32), crate),
    "weapon_rack": ((-1.05, 0, -0.4), (1.05, 2.0, 0.4), weapon_rack),
    "throne": ((-0.55, 0, -0.45), (0.55, 1.7, 0.45), throne),
    "sign_post": ((-0.55, 0, -0.15), (0.55, 2.25, 0.15), sign_post),
    "target": ((-0.6, -1.5, -0.12), (0.6, 0.6, 0.45), target),
    "smithy": ((-1.5, 0, -0.7), (1.5, 3.05, 0.5), smithy),
    "market_stall": ((-1.35, 0, -0.75), (1.35, 2.3, 1.0), market_stall),
    "notice_board": ((-1.0, 0, -0.15), (1.0, 2.1, 0.2), notice_board),
    "physician": ((-0.95, 0, -0.45), (0.95, 1.7, 0.45), physician),
    "column": ((-0.5, 0, -0.5), (0.5, 6.0, 0.5), column),
    "banner": ((-0.75, 0, -0.1), (0.75, 2.45, 0.1), banner),
    "spike_plate": ((-0.55, 0, -0.55), (0.55, 0.05, 0.55), spike_plate),
    "bomb": ((-0.16, -0.16, -0.16), (0.16, 0.25, 0.16), bomb, 0.025),
    "forge_anvil": ((-0.3, -0.15, -0.2), (0.3, 0.15, 0.2), forge_anvil),
    "forge_hearth": ((-1.15, 0, -0.6), (1.15, 4.6, 0.7), forge_hearth),
    "forge_bellows": ((-0.65, 0, -0.4), (0.65, 1.8, 0.5), forge_bellows),
    "forge_coal": ((-0.6, 0, -0.5), (0.6, 1.3, 0.85), forge_coal),
    "forge_trough": ((-1.3, 0, -0.35), (0.9, 1.0, 0.35), forge_trough),
    "forge_bench": ((-0.95, 0, -0.4), (0.95, 1.1, 0.65), forge_bench),
    "forge_grindstone": ((-0.55, 0, -0.4), (0.55, 1.25, 0.55), forge_grindstone),
    "forge_stump": ((-0.5, 0, -0.4), (0.5, 1.0, 0.4), forge_stump),
    "forge_barrel": ((-0.4, 0, -0.4), (0.4, 1.8, 0.4), forge_barrel),
    "forge_sacks": ((-0.65, 0, -0.4), (0.7, 1.0, 0.5), forge_sacks),
}


# ====================================================================== the sand

def sand_texture():
    """The arena floor as a 10 cm voxel grid seen from above (320 px for 32 m): grains, raked
    rings, a laurel wreath raked in the middle, the trodden paths from the two gates, drag marks,
    damp dark sand at the foot of the wall, flat stones half buried, pebbles and old stains."""
    n = 320
    ii, jj = np.meshgrid(np.arange(n), np.arange(n), indexing="ij")
    x = -16 + (ii + 0.5) * 0.1
    z = -16 + (jj + 0.5) * 0.1
    r = np.sqrt(x * x + z * z)
    ang = np.arctan2(z, x)
    c = np.tile(np.array(SAND, np.float32), (n, n, 1))
    c *= (1 + 0.12 * (hash3(ii, jj, 0, 200) - 0.5) * 2)[..., None]
    c *= (1 + 0.08 * (vnoise(x, 0, z, 1.6, 201) - 0.5) * 2)[..., None]
    # Raked rings: a ridge every 40 cm (the rake's teeth), its furrow a shade darker.
    ridge = np.mod(r, 0.4) / 0.4
    c *= (1 + 0.05 * (ridge < 0.25) - 0.04 * ((ridge > 0.5) & (ridge < 0.75)))[..., None]
    # The laurel raked in the middle: a ring of leaves round a bare disc.
    leaf = (r > 2.0) & (r < 3.1) & (np.mod(ang * 12 / np.pi + 0.5 * np.sin((r - 2.0) * 5.7), 2.0) < 0.75)
    c[leaf] *= 0.8
    c[(np.abs(r - 3.25) < 0.08) | (np.abs(r - 1.85) < 0.08)] *= 0.82
    c[(r > 0.0) & (r < 1.6)] *= 1.04
    # The paths trodden from the gates (east and west, along x), darker and packed down.
    for gx in (-1.0, 1.0):
        lane = np.exp(-((z + 0.25 * np.sin(x * 0.7)) ** 2) / 0.9) * np.clip((x * gx - 2.0) / 4.0, 0, 1)
        c *= (1 - 0.1 * lane)[..., None]
        steps = (hash3(np.floor(x / 0.3), np.floor(z / 0.2), gx, 210) < 0.35 * lane) & (np.abs(z) < 1.3)
        c[steps] *= 0.9
    # Drag marks: a few long furrows where a body was hauled off.
    for k in range(5):
        a0 = 0.6 + k * 1.21
        along = x * np.cos(a0) + z * np.sin(a0)
        d = np.abs((x * np.sin(a0) - z * np.cos(a0)) - (k - 2) * 1.7 - 0.25 * np.sin(along * 1.3 + k))
        mark = (d < 0.1) & (along > 4.0 + k * 0.6) & (along < 7.0 + k * 0.6) & (r < 13.5)
        c[mark] *= 0.92
    # Damp and dark at the foot of the wall, where the sand is not raked.
    edge = np.clip((r - 13.0) / 2.0, 0, 1) ** 1.3
    c = c * (1 - 0.32 * edge)[..., None] + np.array([0.45, 0.36, 0.26]) * (0.32 * edge)[..., None]
    # Old stains.
    stain = vnoise(x, 5, z, 0.9, 202) * vnoise(x, 9, z, 2.5, 203)
    k = np.clip((stain - 0.42) * 6, 0, 1) * 0.35
    c = c * (1 - k)[..., None] + np.array([0.42, 0.22, 0.15]) * k[..., None]
    # Flat stones half buried, in a few clusters, and pebbles.
    cluster = vnoise(x, 13, z, 0.45, 207) > 0.84
    stone = cluster & (hash3(np.floor(x / 0.3), np.floor(z / 0.3), 3, 208) < 0.22) & (r < 14.0) & (r > 3.4)
    c[stone] = np.array([0.72, 0.64, 0.52]) * (0.85 + 0.2 * hash3(ii, jj, 2, 209)[stone])[:, None]
    peb = hash3(ii, jj, 0, 204) < (0.006 + 0.02 * cluster)
    c[peb] = np.array([0.55, 0.52, 0.48]) * (0.8 + 0.4 * hash3(ii, jj, 1, 205)[peb])[:, None]
    scuff = (vnoise(x, 2, z, 0.35, 206) > 0.78) & (r < 13)
    c[scuff] *= 0.9
    img = Image.fromarray((np.clip(c, 0, 1) * 255).astype(np.uint8))
    path = os.path.join(ROOT, "art", "textures", "sand_voxel.png")
    img.save(path, optimize=True)
    print("sand_voxel.png")


def main():
    os.makedirs(OUT, exist_ok=True)
    only = set(sys.argv[1:])
    if not only or "sand" in only:
        sand_texture()
    for name, spec in PROPS.items():
        if not only or name in only:
            prop(name, *spec)
    if not only or "forge_room" in only:
        build_forge_room()
    if not only or "arena" in only:
        build_arena()


if __name__ == "__main__":
    main()
