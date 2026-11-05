#!/usr/bin/env python3
"""The giants' heads in the new look (drawing only, as tools/gen_fine_head.py is the men's): the
Cyclops' and Polyphemus' one great eye under one brow, the Minotaur's bull head with its horns
and the ring through its nose, the Troll's nose, ears and tusks, the bronze Titan's crowned,
bearded head. Sculpted in the fine head's cells (three to each of the head's voxels), each cell
with its own colour and stuff, over the head's own voxels (it goes with the one it lies on).

    python3 tools/gen_fine_giant_heads.py data

-> data/fine_head_<kind>.json, in FineHead's own form (data/fine_head.json) with each cell's colour
and kind after it. Face toward +z. numpy."""
import json, math, os, sys
import numpy as np

RES = 3
GX, GY, GZ = 10, 12, 10
HX, HY, HZ = GX * RES / 2.0, GY * RES / 2.0, GZ * RES / 2.0
AO_FACES = [((1, 0, 0), 1, 2), ((-1, 0, 0), 1, 2), ((0, 1, 0), 0, 2), ((0, -1, 0), 0, 2), ((0, 0, 1), 0, 1), ((0, 0, -1), 0, 1)]
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gen_fine_head as GH


def smin(a, b, k):
    h = np.clip(k - np.abs(a - b), 0.0, None) / k
    return np.minimum(a, b) - h * h * k * 0.25


def smax(a, b, k):
    return -smin(-a, -b, k)


def e3(u, v, w, c, r):
    x, y, z = (u - c[0]) / r[0], (v - c[1]) / r[1], (w - c[2]) / r[2]
    return (np.sqrt(x * x + y * y + z * z) - 1.0) * min(r)


def c3(u, v, w, a, b, ra, rb=None):
    rb = ra if rb is None else rb
    a = np.asarray(a, float)
    b = np.asarray(b, float)
    ab = b - a
    L2 = float(ab @ ab)
    t = np.clip(((u - a[0]) * ab[0] + (v - a[1]) * ab[1] + (w - a[2]) * ab[2]) / L2, 0.0, 1.0)
    dx, dy, dz = u - (a[0] + ab[0] * t), v - (a[1] + ab[1] * t), w - (a[2] + ab[2] * t)
    return np.sqrt(dx * dx + dy * dy + dz * dz) - (ra + (rb - ra) * t)


def bez(p0, p1, p2, p3, n):
    t = np.linspace(0, 1, n)[:, None]
    p0, p1, p2, p3 = (np.asarray(p, float) for p in (p0, p1, p2, p3))
    return [tuple(x) for x in (1 - t) ** 3 * p0 + 3 * (1 - t) ** 2 * t * p1 + 3 * (1 - t) * t * t * p2 + t ** 3 * p3]


def chain(u, v, w, pts, r0, r1):
    d = np.full(np.shape(u), 1e9)
    n = len(pts) - 1
    for i in range(n):
        d = np.minimum(d, c3(u, v, w, pts[i], pts[i + 1], r0 + (r1 - r0) * i / n, r0 + (r1 - r0) * (i + 1) / n))
    return d


# --- the heads (as the concepts drew them) -----------------------------------------------------
def cyclops(u, v, w, old=False):
    d = smin(e3(u, v, w, (0, 3.5, -1.5), (14.8, 16.2, 14.8)), e3(u, v, w, (0, -4.5, 1.2), (13.6, 13.0, 12.2)), 6.0)
    d = smin(d, e3(u, v, w, (0, -11.2, 3.8), (12.4, 7.2, 10.2)), 5.0)
    d = smin(d, e3(u, v, w, (0, 7.2, 11.4), (10.0, 2.8, 3.6)), 2.6)
    d = smax(d, -e3(u, v, w, (0, 2.6, 14.6), (5.6, 4.4, 3.8)), 1.6)
    d = np.minimum(d, e3(u, v, w, (0, 2.5, 10.6), (4.8, 3.9, 4.0)))
    nose = smin(e3(u, v, w, (0, -3.8, 13.2), (3.6, 2.6, 2.8)), e3(u, v, w, (0, -1.0, 12.6), (2.2, 2.8, 1.9)), 1.5)
    for sx in (-1, 1):
        nose = smin(nose, e3(u, v, w, (sx * 3.0, -4.6, 12.6), (1.7, 1.4, 1.5)), 1.0)
        d = smin(d, e3(u, v, w, (sx * 9.2, -2.0, 9.6), (4.0, 2.8, 2.8)), 2.5)
        d = smin(d, e3(u, v, w, (sx * 14.6, 0.0, -1.0), (1.7, 3.6, 2.5)), 1.2)
    d = smin(d, nose, 1.4)
    d = smin(d, e3(u, v, w, (0, -8.9, 12.2), (5.4, 1.3, 1.7)), 1.0)
    d = smin(d, e3(u, v, w, (0, -10.7, 12.8), (5.2, 1.5, 1.9)), 1.0)
    for sx in (-1, 1):
        d = np.minimum(d, c3(u, v, w, (sx * 2.0, -10.4, 13.6), (sx * 2.3, -8.4, 14.1), 0.85, 0.6))
    d = smin(d, e3(u, v, w, (0, -14.8, 10.2), (6.2, 3.3, 3.3)), 2.0)
    if old:
        beard = smin(e3(u, v, w, (0, -15.5, 9.0), (11.0, 7.5, 6.5)), c3(u, v, w, (0, -16.0, 10.0), (0, -31.0, 9.5), 7.0, 3.0), 3.0)
        beard = beard + 0.9 * np.sin(np.abs(u) * 1.7) * np.sin(v * 1.3 + w * 0.4)
        d = smin(d, beard, 1.5)
        d = smin(d, e3(u, v, w, (0, -8.0, -9.5), (13.0, 19.0, 6.0)) + 0.8 * np.sin(np.abs(u) * 1.5 + v * 0.4), 3.0)
    return d


def minotaur(u, v, w):
    d = e3(u, v, w, (0, 5.0, -2.0), (12.0, 12.0, 12.5))
    d = smin(d, c3(u, v, w, (0, 2.0, 5.0), (0, -4.5, 16.0), 8.0, 6.4), 4.0)
    d = smin(d, e3(u, v, w, (0, -6.2, 18.0), (6.8, 4.8, 3.4)), 2.0)
    d = smin(d, e3(u, v, w, (0, -10.0, 9.5), (7.6, 4.2, 8.0)), 3.0)
    d = smin(d, e3(u, v, w, (0, -6.0, -2.0), (10.5, 12.0, 10.0)), 5.0)
    for sx in (-1, 1):
        d = smax(d, -e3(u, v, w, (sx * 2.9, -5.6, 21.0), (1.3, 1.1, 1.6)), 0.8)
        d = smin(d, e3(u, v, w, (sx * 8.6, 4.4, 8.4), (2.6, 2.2, 2.4)), 1.5)
        d = np.minimum(d, e3(u, v, w, (sx * 8.9, 2.6, 8.6), (1.9, 1.8, 1.8)))
        d = smin(d, e3(u, v, w, (sx * 14.5, 7.5, -2.0), (4.2, 1.6, 2.4)), 1.0)
        d = np.minimum(d, chain(u, v, w, bez((sx * 9.0, 10.5, 1.0), (sx * 19.0, 12.0, 4.0), (sx * 25.0, 18.0, 9.0), (sx * 24.0, 27.0, 13.0), 12), 3.3, 0.6))
    ring = np.abs(np.sqrt(u * u + (v + 9.4) ** 2) - 2.6)
    d = np.minimum(d, np.sqrt(ring ** 2 + (w - 20.6) ** 2) - 0.75)
    d = smin(d, e3(u, v, w, (0, 13.5, 4.5), (5.0, 3.0, 4.0)), 2.0)
    return d


def troll(u, v, w):
    d = smin(e3(u, v, w, (0, 1.5, -3.0), (13.4, 13.6, 14.0)), e3(u, v, w, (0, -5.0, 2.0), (12.8, 12.0, 12.0)), 6.0)
    d = smin(d, e3(u, v, w, (0, -12.0, 4.5), (13.4, 6.8, 10.8)), 5.0)
    d = smin(d, e3(u, v, w, (0, 4.6, 11.2), (10.6, 2.4, 3.2)), 2.4)
    for sx in (-1, 1):
        d = smax(d, -e3(u, v, w, (sx * 4.6, 2.0, 13.8), (2.6, 2.0, 2.4)), 1.2)
        d = np.minimum(d, e3(u, v, w, (sx * 4.6, 1.9, 10.8), (1.8, 1.6, 1.8)))
        d = smin(d, chain(u, v, w, bez((sx * 12.0, 1.0, -1.5), (sx * 18.0, 3.0, -3.0), (sx * 24.0, 8.0, -4.0), (sx * 28.0, 14.0, -4.5), 10), 3.4, 0.5), 1.0)
        d = np.minimum(d, c3(u, v, w, (sx * 4.4, -12.0, 13.4), (sx * 5.2, -5.6, 15.4), 1.35, 0.45))
    d = smin(d, c3(u, v, w, (0, 3.0, 12.0), (0, -5.0, 20.5), 2.8, 4.0), 1.5)
    d = smin(d, e3(u, v, w, (0, -6.4, 20.8), (4.4, 4.2, 4.0)), 1.5)
    d = smin(d, e3(u, v, w, (0, -9.6, 13.4), (6.6, 1.6, 2.0)), 1.2)
    for (a, b, c) in ((7.5, -2.0, 11.0), (-3.0, 7.0, 12.5), (2.0, -4.0, 20.6), (-9.0, -8.0, 9.5)):
        d = smin(d, e3(u, v, w, (a, b, c), (1.1, 1.1, 1.1)), 0.6)
    return d


def titan(u, v, w):
    d = np.vectorize(lambda a, b, c: GH.sdf((a, b, c)), otypes=[float])(u, v, w)
    beard = smin(e3(u, v, w, (0, -13.5, 7.5), (11.2, 6.5, 6.8)), c3(u, v, w, (0, -16.0, 9.5), (0, -27.0, 10.0), 3.4, 1.8), 2.0)
    d = smin(d, beard + 0.7 * np.sin(np.abs(u) * 2.2) * np.sin(v * 2.0), 1.0)
    for k in range(10):
        a = k / 10.0 * math.tau
        d = smin(d, e3(u, v, w, (math.cos(a) * 11.5, 11.5, math.sin(a) * 11.0 - 1.5), (3.6, 3.0, 3.6)), 1.5)
    crown = np.maximum(np.abs(np.sqrt((u / 14.2) ** 2 + ((w + 0.5) / 14.0) ** 2) - 1.0) * 14.0 - 1.0, np.abs(v - 10.5) - 1.6)
    spikes = np.full(np.shape(u), 1e9)
    # (spikes all the way round, the same both sides: they stood on his left only)
    for k in range(12):
        a = k / 12.0 * math.tau
        cx, cz = math.sin(a) * 14.0, math.cos(a) * 13.8 - 0.5
        spikes = np.minimum(spikes, c3(u, v, w, (cx, 11.0, cz), (cx * 1.02, 17.0, cz * 1.02), 1.5, 0.3))
    return np.minimum(d, np.minimum(crown, spikes))


HEADS = {"cyclops": cyclops, "polyphemus": lambda u, v, w: cyclops(u, v, w, True), "minotaur": minotaur, "troll": troll, "titan": titan}
# Each giant's skin (MonsterLook.SKIN) and hair, for the colours worked out here.
SKIN = {"cyclops": 0xb88a68, "polyphemus": 0xb88a68, "minotaur": 0x6a4430, "troll": 0x6f8458, "titan": 0xb98a4a}
HAIR = {"cyclops": (0.13, 0.09, 0.06), "polyphemus": (0.42, 0.38, 0.34), "minotaur": (0.16, 0.1, 0.07), "troll": (0.24, 0.36, 0.16), "titan": (0.12, 0.08, 0.04)}


def colours(kind, u, v, w, noise):
    """Each surface cell's colour (0..1) and kind (the shader's): as the concepts painted them."""
    s = SKIN[kind]
    skin = np.array([(s >> 16 & 255) / 255.0, (s >> 8 & 255) / 255.0, (s & 255) / 255.0])
    hair = np.array(HAIR[kind])
    n = u.shape[0]
    col = np.tile(skin, (n, 1))
    knd = np.zeros(n, np.int64)

    def put(m, c, k=None, var=None):
        col[m] = np.asarray(c, float)[None, :] * (var[m][:, None] if var is not None else 1.0)
        if k is not None:
            knd[m] = k
    if kind in ("cyclops", "polyphemus"):
        eye_r = (u / 4.8) ** 2 + ((v - 2.5) / 3.9) ** 2
        eye = (eye_r < 1.05) & (w > 12.0)
        put(eye, (0.92, 0.9, 0.84) if kind == "cyclops" else (0.86, 0.86, 0.84))
        iris = eye & ((u / 2.4) ** 2 + ((v - 2.3) / 2.4) ** 2 < 1.0)
        put(iris, (0.55, 0.3, 0.08) if kind == "cyclops" else (0.72, 0.76, 0.78))
        put(eye & ((u / 1.0) ** 2 + ((v - 2.3) / 1.1) ** 2 < 1.0), (0.04, 0.03, 0.03))
        put((eye_r < 1.6) & ~eye & (v > 4.6) & (w > 11.0), skin * 0.8)
        put((np.abs(v - 7.6) < 1.6) & (np.abs(u) < 9.0) & (w > 12.0), hair * 0.9, 2)
        put((v < -8.0) & (v > -11.8) & (np.abs(u) < 5.4) & (w > 12.0), skin * 0.55 + np.array([0.55, 0.28, 0.24]) * 0.45)
        put((np.abs(v + 9.8) < 0.5) & (np.abs(u) < 4.6) & (w > 12.6), (0.2, 0.07, 0.06))
        put((v > -10.6) & (v < -8.0) & (np.abs(np.abs(u) - 2.15) < 0.95) & (w > 13.2), (0.9, 0.86, 0.72), 6)
        put((np.abs(np.abs(u) - 3.0) < 1.1) & (np.abs(v + 4.9) < 0.8) & (w > 12.0), skin * 0.35)
        back = (w < 4.0) & (v > -6.0) & ~((np.abs(u) < 9.0) & (v > 8.0) & (w > -6.0))
        put(back & (noise < 0.85), hair, 2, 0.8 + 0.4 * noise)
        put((v < -6.0) & (w > 2.0) & ~((np.abs(u) < 5.6) & (v > -12.0) & (w > 11.0)) & (noise < 0.45), skin * 0.72 + hair * 0.28)
        if kind == "polyphemus":
            beard = (v < -12.0) | ((v < -6.0) & (np.abs(u) > 6.0)) | ((w < -4.0) & (v < 6.0))
            put(beard, hair, 2, 0.75 + 0.45 * noise)
    elif kind == "minotaur":
        put(np.ones(n, bool), skin * 0.8, 8, 0.8 + 0.35 * noise)
        put((w > 15.0) & (v < -2.0) & (v > -10.5), (0.36, 0.25, 0.23), 0, 0.9 + 0.2 * noise)
        put((np.abs(np.abs(u) - 2.9) < 1.4) & (np.abs(v + 5.6) < 1.3) & (w > 19.4), (0.08, 0.05, 0.05))
        horn = (np.abs(u) > 9.5) & (v > 9.0)
        put(horn, (0.9, 0.85, 0.72), 6)
        put(horn & (v > 22.0), (0.3, 0.26, 0.2), 6)
        put((np.abs(np.abs(u) - 8.9) < 2.2) & (np.abs(v - 2.6) < 2.0) & (w > 7.0) & (w < 11.0) & (np.abs(u) > 10.0), (0.8, 0.12, 0.08), 12)
        put((np.abs(np.sqrt(u * u + (v + 9.4) ** 2) - 2.6) < 1.2) & (np.abs(w - 20.6) < 1.2), (0.86, 0.68, 0.25), 4)
        put((v > 11.0) & (np.abs(u) < 5.5) & (w > 1.0), (0.1, 0.07, 0.05), 2)
    elif kind == "troll":
        put(np.ones(n, bool), skin, 0, 0.88 + 0.2 * noise)
        eye = (np.abs(np.abs(u) - 4.6) < 1.9) & (np.abs(v - 1.9) < 1.7) & (w > 11.8)
        put(eye, (0.9, 0.84, 0.5))
        put(eye & ((np.abs(u) - 4.6) ** 2 + (v - 1.9) ** 2 < 0.9), (0.95, 0.82, 0.2), 12)
        put((np.abs(v - 4.8) < 1.4) & (np.abs(u) < 9.5) & (w > 12.0), skin * 0.6)
        tusk = (np.abs(np.abs(u) - 4.8) < 1.6) & (v > -12.5) & (v < -5.0) & (w > 13.0)
        put(tusk, (0.9, 0.86, 0.72), 6)
        put((np.abs(v + 9.6) < 0.7) & (np.abs(u) < 5.5) & (w > 13.5) & ~tusk, (0.18, 0.08, 0.06))
        put((v > 9.0) & (noise < 0.75) & (np.abs(u) < 12.0), (0.25, 0.37, 0.15), 8, 0.8 + 0.4 * noise)
        put((np.abs(u) > 16.0) & (np.abs(u) < 26.0), skin * 0.9)
        put((w > 15.0) & (v > -10.5) & (v < 4.0) & (np.abs(u) < 5.0), skin * np.array([1.12, 0.9, 0.86]))
        put((np.abs(np.abs(u) - 2.2) < 1.1) & (np.abs(v + 8.6) < 0.9) & (w > 19.0), skin * 0.35)
    elif kind == "titan":
        put(np.ones(n, bool), skin, 4)
        for sx in (-1, 1):
            put((np.abs(u - sx * 5.2) < 2.2) & (np.abs(v - 2.2) < 1.5) & (w > 10.0), (1.0, 0.72, 0.22), 12)
        put((np.abs(v + 9.5) < 0.6) & (np.abs(u) < 3.0) & (w > 10.6), (0.32, 0.18, 0.1), 4)
        put((v < -7.0) & ~((np.abs(u) < 3.6) & (v > -11.0) & (w > 10.0)), hair, 2, 0.8 + 0.5 * noise)
        ring = np.sqrt((u / 14.2) ** 2 + ((w + 0.5) / 14.0) ** 2)
        crown = ((np.abs(v - 10.5) < 1.7) & (ring > 0.9)) | ((v > 12.2) & (ring > 0.92))
        put((v > 7.0) & ~crown, hair, 2, 0.8 + 0.5 * noise)
        put(crown, (0.95, 0.76, 0.28), 4)
    return np.clip(col, 0, 1), knd


def build(kind):
    f = HEADS[kind]
    # The lattice (fine cells from the head's middle), room for the horns, the ears, a beard.
    xs = np.arange(-31, 31) + 0.5
    ys = np.arange(-int(HY) - (15 if kind in ("polyphemus", "titan") else 0), 33) + 0.5
    zs = np.arange(-21, 27) + 0.5
    U, V, W = np.meshgrid(xs, ys, zs, indexing="ij")
    D = f(U, V, W)
    occ = D <= 0.0
    # (Below the head's box only what hangs from the chin: a beard, the hair down the back.)
    occ &= (V >= -HY) | ((np.abs(W) > 5.0) & (kind in ("polyphemus", "titan")))
    shift = lambda a, d: np.roll(np.roll(np.roll(a, -d[0], 0), -d[1], 1), -d[2], 2)
    surf = np.zeros_like(occ)
    for ax in range(3):
        for dl in (-1, 1):
            dd = [0, 0, 0]
            dd[ax] = dl
            surf |= occ & ~shift(occ, dd)
    idx = np.argwhere(surf)
    u, v, w = U[surf], V[surf], W[surf]
    e = 0.3
    n = np.stack([f(u + e, v, w) - f(u - e, v, w), f(u, v + e, w) - f(u, v - e, w), f(u, v, w + e) - f(u, v, w - e)], 1)
    n /= np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-9)
    # (each cell's fleck the same as its mirror's: the face is the same both sides)
    iu, iv, iw = np.floor(np.abs(u)).astype(np.int64), np.floor(v).astype(np.int64), np.floor(w).astype(np.int64)
    hh = (iu * 73856093) ^ (iv * 19349663) ^ (iw * 83492791) ^ 5
    hh = (hh ^ (hh >> 13)) * 1274126177
    noise = ((hh ^ (hh >> 16)) & 0xFFFF).astype(np.float64) / 65536.0
    col, knd = colours(kind, u, v, w, noise)
    # The head's voxel each lies on: out along its normal to the last of the head's voxels.
    q = np.stack([np.clip(u, -HX + 0.01, HX - 0.01), np.clip(v, -HY + 0.01, HY - 0.01), np.clip(w, -HZ + 0.01, HZ - 0.01)], 1)
    last = q.copy()
    alive = np.ones(q.shape[0], bool)
    for st in range(1, 40):
        r = q + n * 0.5 * st
        inb = (np.abs(r[:, 0]) < HX) & (np.abs(r[:, 1]) < HY) & (np.abs(r[:, 2]) < HZ) & alive
        last[inb] = r[inb]
        alive &= inb
    par = np.stack([((last[:, 0] + HX) // RES), ((last[:, 1] + HY) // RES), ((last[:, 2] + HZ) // RES)], 1).astype(int)
    par[:, 0] = np.clip(par[:, 0], 0, GX - 1)
    par[:, 1] = np.clip(par[:, 1], 0, GY - 1)
    par[:, 2] = np.clip(par[:, 2], 0, GZ - 1)
    # Corner shading.
    ao = np.zeros(occ.shape, np.int64)
    for fi, (fn, ua, va) in enumerate(AO_FACES):
        open_face = ~shift(occ, fn)
        for c in range(4):
            du = [0, 0, 0]
            du[ua] = 1 if c & 1 else -1
            dv = [0, 0, 0]
            dv[va] = 1 if c & 2 else -1
            a1 = shift(occ, (fn[0] + du[0], fn[1] + du[1], fn[2] + du[2]))
            b1 = shift(occ, (fn[0] + dv[0], fn[1] + dv[1], fn[2] + dv[2]))
            c1 = shift(occ, (fn[0] + du[0] + dv[0], fn[1] + du[1] + dv[1], fn[2] + du[2] + dv[2]))
            ao |= np.where(surf & open_face & (a1 | b1 | c1), 1 << (fi * 4 + c), 0)
    rgb = ((col[:, 0] * 255).astype(int) << 16) | ((col[:, 1] * 255).astype(int) << 8) | (col[:, 2] * 255).astype(int)
    cells = []
    for i in range(idx.shape[0]):
        cells.append([int(round(u[i] - 0.5 + HX)), int(round(v[i] - 0.5 + HY)), int(round(w[i] - 0.5 + HZ)), 0, 0, 1.0,
                      int(par[i, 0]), int(par[i, 1]), int(par[i, 2]), int(ao[surf][i]), int(rgb[i]), int(knd[i])])
    # The head's voxels wholly inside it (drawn as they are, seen only through a wound).
    keep = []
    for cx in range(GX):
        for cy in range(GY):
            for cz in range(GZ):
                pts = np.array([[cx * RES + a - HX + 0.5, cy * RES + b - HY + 0.5, cz * RES + c - HZ + 0.5] for a in range(RES) for b in range(RES) for c in range(RES)])
                if (f(pts[:, 0], pts[:, 1], pts[:, 2]) <= -0.6).all():
                    keep.append([cx, cy, cz])
    return {"res": RES, "grid": [GX, GY, GZ], "eye": [0.0, 2.5], "cells": cells, "keep": keep, "giant": kind}


def main(out_dir):
    for kind in HEADS:
        data = build(kind)
        path = os.path.join(out_dir, "fine_head_%s.json" % kind)
        with open(path, "w") as fh:
            json.dump(data, fh, separators=(",", ":"))
        print(kind, len(data["cells"]), "cells", len(data["keep"]), "kept ->", path, flush=True)


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "data")
