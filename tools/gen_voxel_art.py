"""Makes the arena's voxel art (art/voxel/*.glb, art/textures/sand_voxel.png): the bowl itself
(podium wall, stands, aisles, the two gatehouses, the Emperor's box, the arcade) as world-aligned
10 cm voxels, and the props (braziers, gates, statues, amphorae, the yard's stations...) as
5 cm voxels. Every model is built from code, so it can be changed and rebuilt:

    pip install numpy numba pillow
    python3 tools/gen_voxel_art.py            # everything
    python3 tools/gen_voxel_art.py brazier    # one model

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


def ashlar(mat, base, bl=0.6, bh=0.3, var=0.07, seed=1, dirt=0.0, mortar=0.84, vs=0.1, radial=True):
    """Dressed stone: staggered blocks bl x bh, each its own shade, darker mortar joints,
    blotches of weathering, and (dirt) sand splashed up the lowest half metre."""
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
        return pack(mat, c)
    return f


PER_VOX = [True]   # off for the bowl: the shader's grain is enough there, and quads merge


def plain(mat, base, var=0.04, big=0.05, seed=2):
    def f(ix, iy, iz, x, y, z):
        if not PER_VOX[0]:
            n = vnoise(np.floor(x / 0.5), np.floor(y / 0.5), np.floor(z / 0.5), 1.0, seed)
            return pack(mat, tint(base, big + var, np.round(n * 4) / 4))
        c = tint(base, var, hash3(ix, iy, iz, seed)) * tint((1, 1, 1), big, vnoise(x, y, z, 0.9, seed))
        return pack(mat, c)
    return f


def planks(mat, base, along=1, width=0.15, var=0.12, seed=4, vs=0.05):
    """Boards running along axis `along`, `width` wide across the other horizontal axis, each
    its own shade, with darker grain streaks and a dark seam between boards."""
    def f(ix, iy, iz, x, y, z):
        idx = (ix, iy, iz)
        pos = (x, y, z)
        across = pos[2] if along != 2 else pos[0]
        if along == 2:
            across = pos[0] + pos[1] * 0.0
        b = np.floor(across / width)
        n_b = hash3(b.astype(np.int64), 0, 0, seed)
        lane = idx[2] if along != 2 else idx[0]
        grain = hash3(lane, 0, b.astype(np.int64), seed + 1)
        streak = (grain < 0.25).astype(np.float32)
        c = tint(base, var, n_b) * (1 - 0.12 * streak)[:, None] * tint((1, 1, 1), 0.03, hash3(*idx, seed + 2))
        seam = (across - b * width) < vs * 0.99
        c[seam] *= 0.7
        return pack(mat, c)
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
        s.put(band(r0, r1) & (Y < top - vs), ashlar("stone", TRAV_DARK, 1.0, 0.35, seed=10 + t))
        # The seat: a lighter slab with its own joints, a worn front edge.
        s.put(band(r0, r1) & (Y >= top - vs) & (Y < top), ashlar("stone", (0.86, 0.80, 0.68), 0.9, 1.0, 0.05, seed=20 + t, mortar=0.9))
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
    s.put(wall, ashlar("stone", TRAVERTINE, 0.6, 0.3, seed=1, dirt=0.55))
    s.put(band(14.9, 15.0) & (Y < 0.3), ashlar("stone", (0.62, 0.56, 0.47), 0.8, 0.3, seed=2, dirt=0.4))
    s.put(band(14.9, 15.9) & (Y >= 1.8) & (Y < 2.0), ashlar("marble", MARBLE, 1.2, 0.2, 0.04, seed=3, mortar=0.9))
    arc = th * 15.0
    pil_d = np.abs(dang(th, math.radians(15))) * 15.0
    pilaster = band(14.9, 15.0) & (Y >= 0.3) & (Y < 1.8) & (pil_d < 0.25)
    s.put(pilaster, ashlar("marble", MARBLE, 2.0, 0.5, 0.04, seed=4, dirt=0.3, mortar=0.92))
    s.put(band(14.85, 14.9) & (Y >= 1.6) & (Y < 1.8) & (pil_d < 0.3), pack("marble", MARBLE))
    # Painted panels between the pilasters, gold-edged; on every other one a hanging banner.
    panel = band(15.0, 15.1) & (Y >= 0.5) & (Y < 1.6) & (pil_d > 0.35)
    edge = (Y < 0.6) | (Y >= 1.5) | (pil_d < 0.45)
    s.put(panel & ~edge, plain("plaster", RED, 0.03, 0.08, seed=5))
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
        s.put(block, ashlar("stone", TRAVERTINE, 0.6, 0.3, seed=40, dirt=0.5))
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
    s.put(archband & ~hole, ashlar("marble", (0.88, 0.85, 0.78), 0.5, 0.25, 0.05, seed=61, mortar=0.88))
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
    br = plain("bronze", BRONZE, 0.05, 0.12, seed=70)
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
    s.box((-0.12, 0, 0), (0.12, 2.4, 2.6), planks("wood", WOOD, along=1, width=0.433, seed=80))
    x, y, z = s.grids()
    for by in (0.45, 1.75):
        strap = (y >= by) & (y < by + 0.2) & (z >= 0.05) & (z < 2.55) & (np.abs(x) < 0.17)
        s.put(strap, plain("iron", IRON, 0.05, 0.15, seed=81))
        stud = (np.abs(x) < 0.22) & (np.abs(y - by - 0.1) < 0.05) & (np.abs(np.mod(z - 0.216, 0.433) - 0.216) > 0.17)
        s.put(stud & (z > 0.1) & (z < 2.5), pack("iron", (0.30, 0.29, 0.27)))
    s.box((-0.17, 0, 0), (0.17, 2.4, 0.08), plain("iron", IRON, 0.05, 0.1, seed=82))
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
        c = tint((0.66, 0.5, 0.31), 0.12, hash3(b.astype(np.int64), np.floor((xx + zz) * 3).astype(np.int64), 0, 110))
        c[(yy - b * 0.1) < 0.049] *= 0.72
        return pack("wood", c)
    s.put(boards, board)
    frame = (((np.abs(x) > 0.25).astype(int) + (np.abs(z) > 0.25) + ((y < 0.08) | (y > 0.52))) >= 2) & (np.maximum(np.abs(x), np.abs(z)) < 0.31) & (y < 0.6)
    s.put(frame, plain("wood", WOOD_DARK, 0.06, 0.1, seed=111))
    brace = (np.abs((y - 0.3) - np.where(np.abs(x) > 0.28, z, x) * 0.9) < 0.04) & (np.maximum(np.abs(x), np.abs(z)) > 0.27) & (np.maximum(np.abs(x), np.abs(z)) < 0.31) & (y > 0.05) & (y < 0.55)
    s.put(brace, plain("wood", WOOD_DARK, 0.06, 0.1, seed=112))


def weapon_rack(s):
    """A rack of spears and two shields, 2 m wide."""
    wd = planks("wood", WOOD, along=0, width=2.0, seed=120)
    s.box((-1.0, 0, -0.1), (-0.9, 1.4, 0.1), wd)
    s.box((0.9, 0, -0.1), (1.0, 1.4, 0.1), wd)
    s.box((-1.0, 1.3, -0.1), (1.0, 1.4, 0.1), wd)
    s.box((-1.0, 0.25, -0.15), (1.0, 0.35, 0.15), wd)
    for k in range(7):
        xx = -0.725 + k * 0.25
        s.seg((xx, 0.3, 0.025), (xx, 1.75, -0.025), 0.04, plain("wood", (0.6, 0.45, 0.28), seed=121))
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
    s.box((-0.05, 0, -0.05), (0.05, 2.2, 0.05), plain("wood", WOOD_DARK, seed=140))
    s.box((-0.5, 1.75, -0.05), (0.5, 2.05, 0.05), planks("wood", (0.62, 0.46, 0.28), along=0, width=0.1, seed=141))
    s.box((-0.05, 1.75, -0.1), (0.05, 2.05, -0.05), pack("iron", IRON))


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
        s.seg((sx * 0.3, -0.35, 0.08), (sx * 0.4, -1.5, 0.35), 0.035, plain("wood", WOOD, seed=153))
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
    s.box((-1.42, 0.8, -0.62), (-1.32, 1.6, -0.52), plain("wood", WOOD_DARK, seed=163))
    s.box((-0.28, 0.8, -0.62), (-0.18, 1.6, -0.52), plain("wood", WOOD_DARK, seed=164))
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
    s.cyl((1.15, 0, -0.3), 0.28, 0.12, 0.17, pack("iron", IRON))
    s.cyl((1.15, 0, -0.3), 0.28, 0.55, 0.6, pack("iron", IRON))
    s.cyl((1.15, 0, -0.3), 0.22, 0.6, 0.7, pack("glow", (0.12, 0.2, 0.22)))


def market_stall(s):
    """A market stall 2.4 m wide: posts, a striped awning, a counter of bread, fruit and jars."""
    wd = plain("wood", WOOD, 0.06, 0.1, seed=170)
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
    wd = plain("wood", WOOD_DARK, 0.06, 0.1, seed=180)
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
            s.box((sx, 0, sz), (sx + 0.08, 0.75, sz + 0.08), plain("wood", WOOD_DARK, seed=191))
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


PROPS = {
    "brazier": ((-0.45, 0, -0.45), (0.45, 1.6, 0.45), brazier),
    "gate_door": ((-0.25, 0, -0.05), (0.25, 2.45, 2.65), gate_door),
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
}


# ====================================================================== the sand

def sand_texture():
    """The arena floor as a 10 cm voxel grid seen from above (320 px for 32 m): grains, raked
    rings, darker sand at the foot of the wall, pebbles and old stains."""
    n = 320
    ii, jj = np.meshgrid(np.arange(n), np.arange(n), indexing="ij")
    x = -16 + (ii + 0.5) * 0.1
    z = -16 + (jj + 0.5) * 0.1
    r = np.sqrt(x * x + z * z)
    c = np.tile(np.array(SAND, np.float32), (n, n, 1))
    c *= (1 + 0.12 * (hash3(ii, jj, 0, 200) - 0.5) * 2)[..., None]
    c *= (1 + 0.07 * (vnoise(x, 0, z, 1.6, 201) - 0.5) * 2)[..., None]
    c *= (1 + 0.04 * (np.mod(np.floor(r / 0.1), 4) < 1))[..., None]   # raked rings, a voxel wide
    edge = np.clip((r - 13.2) / 1.8, 0, 1) ** 1.5
    c = c * (1 - 0.25 * edge)[..., None] + np.array([0.5, 0.4, 0.3]) * (0.25 * edge)[..., None]
    stain = vnoise(x, 5, z, 0.9, 202) * vnoise(x, 9, z, 2.5, 203)
    k = np.clip((stain - 0.42) * 6, 0, 1) * 0.35
    c = c * (1 - k)[..., None] + np.array([0.42, 0.22, 0.15]) * k[..., None]
    peb = hash3(ii, jj, 0, 204) < 0.006
    c[peb] = np.array([0.55, 0.52, 0.48]) * (0.8 + 0.4 * hash3(ii, jj, 1, 205)[peb])[:, None]
    scuff = (vnoise(x, 2, z, 0.35, 206) > 0.78) & (r < 13)
    c[scuff] *= 0.9
    img = Image.fromarray((np.clip(c, 0, 1) * 255).astype(np.uint8))
    path = os.path.join(ROOT, "art", "textures", "sand_voxel.png")
    img.save(path, optimize=True)
    print("sand_voxel.png")


def flagstone_texture():
    """The forge's floor: flagstones in 10 cm voxels seen from above (64 px for 6.4 m, tiling):
    slabs of a few sizes, each its own shade, dark joints, soot and grit."""
    n = 64
    ii, jj = np.meshgrid(np.arange(n), np.arange(n), indexing="ij")
    c = np.zeros((n, n, 3), np.float32)
    row = jj // 6
    off = (row % 2) * 4
    slab = (ii + off) // 8 % 8
    shade = 0.85 + 0.3 * hash3(slab, row, 0, 260)
    base = np.array([0.36, 0.31, 0.27])
    c[:] = base
    c *= shade[..., None]
    c *= (1 + 0.1 * (hash3(ii, jj, 0, 261) - 0.5) * 2)[..., None]
    joint = ((jj % 6) == 0) | (((ii + off) % 8) == 0)
    c[joint] *= 0.45
    soot = vnoise(ii * 0.1, 0, jj * 0.1, 1.3, 262)
    c *= (0.8 + 0.25 * soot)[..., None]
    img = Image.fromarray((np.clip(c, 0, 1) * 255).astype(np.uint8))
    img.save(os.path.join(ROOT, "art", "textures", "flagstone_voxel.png"), optimize=True)
    print("flagstone_voxel.png")


def main():
    os.makedirs(OUT, exist_ok=True)
    only = set(sys.argv[1:])
    if not only or "sand" in only:
        sand_texture()
    if not only or "flagstone" in only:
        flagstone_texture()
    for name, spec in PROPS.items():
        if not only or name in only:
            prop(name, *spec)
    if not only or "arena" in only:
        build_arena()


if __name__ == "__main__":
    main()
