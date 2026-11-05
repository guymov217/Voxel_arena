"""The beasts sculpted for the new look (drawing only), each over its own parts in data/beasts.json
as they stand at rest: a signed distance (metres, < 0 inside), a colour and a kind (the voxel
shader's: 8 fur, 7 wet or glossy, 6 bone, 10 scales, 12 a glowing eye) for every cell of a grid
round the beast. tools/gen_fine_beasts.py lays the cells on the beast's own voxels. numpy.

So far the big cats (the lion and the tiger): a deep chest and a tucked waist, shoulder blades and
haunches, legs tapering to broad paws with toes and claws, a skull with cheeks, a muzzle and
whisker pads, a nose, brows over the eyes, round ears; the lion's mane in tufts, the tiger's
stripes."""
import math
import numpy as np


# ---------- distances on a grid ----------

class Grid:
    def __init__(self, lo, n, cell):
        self.lo = np.asarray(lo, float)
        self.cell = float(cell)
        self.shape = tuple(int(v) for v in n)
        xs = self.lo[0] + (np.arange(self.shape[0]) + 0.5) * cell
        ys = self.lo[1] + (np.arange(self.shape[1]) + 0.5) * cell
        zs = self.lo[2] + (np.arange(self.shape[2]) + 0.5) * cell
        self.X, self.Y, self.Z = np.meshgrid(xs, ys, zs, indexing="ij")


def ell(g, c, r):
    x = (g.X - c[0]) / r[0]
    y = (g.Y - c[1]) / r[1]
    z = (g.Z - c[2]) / r[2]
    return (np.sqrt(x * x + y * y + z * z) - 1.0) * min(r)


def cap(g, a, b, ra, rb=None):
    rb = ra if rb is None else rb
    a = np.asarray(a, float)
    b = np.asarray(b, float)
    ab = b - a
    L2 = float(ab @ ab)
    t = np.clip(((g.X - a[0]) * ab[0] + (g.Y - a[1]) * ab[1] + (g.Z - a[2]) * ab[2]) / L2, 0.0, 1.0)
    dx, dy, dz = g.X - (a[0] + ab[0] * t), g.Y - (a[1] + ab[1] * t), g.Z - (a[2] + ab[2] * t)
    return np.sqrt(dx * dx + dy * dy + dz * dz) - (ra + (rb - ra) * t)


def smin(a, b, k):
    h = np.clip(k - np.abs(a - b), 0.0, None) / k
    return np.minimum(a, b) - h * h * k * 0.25


def smax(a, b, k):
    return -smin(-a, -b, k)


def hash3(ix, iy, iz, seed=0):
    h = (np.asarray(ix, np.int64) * 73856093) ^ (np.asarray(iy, np.int64) * 19349663) ^ \
        (np.asarray(iz, np.int64) * 83492791) ^ (seed * 2654435761)
    h = (h ^ (h >> 13)) * 1274126177
    h = h ^ (h >> 16)
    return (h & 0xFFFF).astype(np.float32) / 65536.0


def vnoise(x, y, z, scale, seed=0):
    px, py, pz = np.asarray(x) / scale, np.asarray(y) / scale, np.asarray(z) / scale
    ix, iy, iz = np.floor(px).astype(np.int64), np.floor(py).astype(np.int64), np.floor(pz).astype(np.int64)
    fx, fy, fz = px - ix, py - iy, pz - iz
    fx, fy, fz = fx * fx * (3 - 2 * fx), fy * fy * (3 - 2 * fy), fz * fz * (3 - 2 * fz)
    out = 0.0
    for dx in (0, 1):
        for dy in (0, 1):
            for dz in (0, 1):
                w = (fx if dx else 1 - fx) * (fy if dy else 1 - fy) * (fz if dz else 1 - fz)
                out = out + w * hash3(ix + dx, iy + dy, iz + dz, seed)
    return out


def hexc(h):
    return np.array([(h >> 16 & 255) / 255.0, (h >> 8 & 255) / 255.0, (h & 255) / 255.0])


def quat_m(q):
    x, y, z, w = q
    return np.array([[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
                     [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
                     [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]])


def parts_of(sp):
    """Each part as it stands at rest: (its turn, its middle, its half size), metres."""
    out = {}
    for p in sp["parts"]:
        v = 0.0275 * float(p["scale"])
        out[p["name"]] = (quat_m(p["rot"]), np.array(p["pos"], float), np.array(p["grid"]) * v * 0.5)
    return out


# ---------- the big cats ----------

FUR, WET, BONE = 8, 7, 6

CATS = {
    "lion": dict(fur=0xc8913f, light=0xead09a, dark=0x9c6a2c, mane=0x84461c, mane2=0x5e2c10, nose=0x4a2a24, eye=0xd8a030, ear=0x6a4420, mane_on=True, stripes=False, head=1.2, leg=1.08),
    "tiger": dict(fur=0xd98a2b, light=0xf2ead8, dark=0xb06a1e, mane=None, mane2=None, nose=0xb06a6a, eye=0xe0b030, ear=0x2a2018, mane_on=False, stripes=True, head=1.08, leg=1.0),
}


def cat(sp, g, P):
    """A big cat over the parts of `sp` (data/beasts.json's): (distance, colour, kind) on `g`."""
    K = parts_of(sp)
    _, body, bh = K["beastBody"]
    _, head, hh = K["beastHead"]
    top = body[1] + bh[1]
    bot = body[1] - bh[1]
    zf = body[2] + bh[2]
    zb = body[2] - bh[2]
    W, Hh, L = bh
    # The trunk: a deep chest, ribs, a waist tucked up under the loins, the rump.
    d = ell(g, (0, body[1] - 0.02 * Hh, body[2] + 0.42 * L), (0.9 * W, 0.94 * Hh, 0.62 * L))
    d = smin(d, ell(g, (0, body[1] + 0.06 * Hh, body[2]), (0.86 * W, 0.84 * Hh, 0.8 * L)), 0.12)
    d = smin(d, ell(g, (0, body[1] + 0.2 * Hh, body[2] - 0.45 * L), (0.72 * W, 0.66 * Hh, 0.42 * L)), 0.14)
    d = smin(d, ell(g, (0, body[1] + 0.16 * Hh, body[2] - 0.7 * L), (0.82 * W, 0.78 * Hh, 0.36 * L)), 0.14)
    for sx in (-1, 1):
        d = smin(d, ell(g, (sx * 0.42 * W, top - 0.36 * Hh, body[2] + 0.56 * L), (0.32 * W, 0.36 * Hh, 0.26 * L)), 0.1)
        d = smin(d, ell(g, (sx * 0.5 * W, body[1] + 0.05 * Hh, body[2] - 0.66 * L), (0.42 * W, 0.62 * Hh, 0.3 * L)), 0.12)
    # The legs, from the shoulder and the hip down to the paw, its toes and claws forward.
    legs = None
    claws = None
    for fb, up, lo_n in (("F", "legFL", "legFLLo"), ("F", "legFR", "legFRLo"), ("B", "legBL", "legBLLo"), ("B", "legBR", "legBRLo")):
        _, pu, hu = K[up]
        _, pl, hl = K[lo_n]
        x = pu[0]
        sx = 1 if x > 0 else -1
        ground = pl[1] - hl[1]
        knee = pu[1] - hu[1]
        hip = pu[1] + hu[1]
        zc = pu[2]
        r0 = hu[0] * 0.92 * P.get("leg", 1.0)
        if fb == "F":
            l = cap(g, (x, hip, zc), (x, knee + 0.02, pl[2] - 0.01), r0 * 1.02, r0 * 0.66)
            l = smin(l, ell(g, (x + sx * 0.02, hip - 0.04, zc + 0.01), (r0 * 1.05, (hip - knee) * 0.62, r0 * 1.25)), 0.08)
            l = smin(l, cap(g, (x, knee + 0.02, pl[2] - 0.01), (x, ground + 0.09, pl[2] - 0.02), r0 * 0.62, r0 * 0.52), 0.06)
        else:
            l = ell(g, (x, hip - 0.02, zc + 0.02), (r0 * 1.12, (hip - knee) * 0.72, r0 * 1.5))
            l = smin(l, cap(g, (x, knee + 0.1, zc - 0.03), (x, knee - 0.02, pl[2] - 0.17), r0 * 0.8, r0 * 0.55), 0.07)
            l = smin(l, cap(g, (x, knee - 0.02, pl[2] - 0.17), (x, ground + 0.09, pl[2] - 0.02), r0 * 0.5, r0 * 0.5), 0.05)
        pz = pl[2] + 0.06
        l = smin(l, ell(g, (x, ground + 0.055, pz), (r0 * 0.78, 0.062, r0 * 1.0)), 0.05)
        for tx in (-0.55, -0.18, 0.18, 0.55):
            tc = (x + tx * r0 * 0.95, ground + 0.045, pz + r0 * 0.78)
            l = smin(l, ell(g, tc, (r0 * 0.26, 0.045, r0 * 0.3)), 0.02)
            cl = cap(g, (tc[0], ground + 0.03, tc[2] + r0 * 0.2), (tc[0], ground + 0.012, tc[2] + r0 * 0.36), 0.014, 0.008)
            claws = cl if claws is None else np.minimum(claws, cl)
        legs = l if legs is None else np.minimum(legs, l)
    d = smin(d, legs, 0.1)
    d = np.minimum(d, claws)
    # The neck and the head: a skull, cheeks, a muzzle with whisker pads, the bridge of the nose,
    # a chin, brows; the eyes sit in under the brow; round ears.
    hs = P["head"]
    hc = np.array([0.0, head[1] + 0.07, head[2] + 0.06])
    d = smin(d, cap(g, (0, top - 0.3 * Hh, zf - 0.3 * L), (0, hc[1] - 0.06, hc[2] - 0.08), 0.26 * hs + 0.04, 0.2 * hs), 0.14)
    sk = ell(g, hc, np.array([0.25, 0.22, 0.26]) * hs)
    for sx in (-1, 1):
        sk = smin(sk, ell(g, hc + np.array([sx * 0.15, -0.09, 0.12]) * hs, np.array([0.135, 0.12, 0.14]) * hs), 0.05)
    mz = hc + np.array([0.0, -0.15, 0.25]) * hs
    sk = smin(sk, ell(g, mz, np.array([0.155, 0.125, 0.16]) * hs), 0.06)
    for sx in (-1, 1):
        sk = smin(sk, ell(g, mz + np.array([sx * 0.07, -0.015, 0.08]) * hs, np.array([0.085, 0.075, 0.075]) * hs), 0.03)
        sk = smin(sk, ell(g, hc + np.array([sx * 0.1, 0.075, 0.19]) * hs, np.array([0.085, 0.04, 0.06]) * hs), 0.03)
    sk = smin(sk, cap(g, hc + np.array([0, 0.02, 0.18]) * hs, mz + np.array([0, 0.07, 0.1]) * hs, 0.055 * hs, 0.05 * hs), 0.04)
    chin = mz + np.array([0.0, -0.11, -0.03]) * hs
    sk = smin(sk, ell(g, chin, np.array([0.11, 0.065, 0.12]) * hs), 0.04)
    eyes = []
    for sx in (-1, 1):
        ec = hc + np.array([sx * 0.105, 0.02, 0.215]) * hs
        eyes.append(ec)
        sk = smax(sk, -ell(g, ec + np.array([0, 0, 0.03]) * hs, np.array([0.05, 0.035, 0.04]) * hs), 0.015)
    ears = None
    for sx in (-1, 1):
        e = ell(g, hc + np.array([sx * 0.19, 0.2, -0.04]) * hs, np.array([0.085, 0.08, 0.035]) * hs)
        ears = e if ears is None else np.minimum(ears, e)
    sk = smin(sk, ears, 0.03)
    d = smin(d, sk, 0.08)
    # The lion's mane: a ruff of tufts round the face and down the chest.
    mane = None
    if P["mane_on"]:
        n1 = vnoise(np.abs(g.X), g.Y, g.Z, 0.07, 3)
        n2 = vnoise(np.abs(g.X), g.Y, g.Z, 0.03, 5)
        m = ell(g, hc + np.array([0, -0.1, -0.24]), (0.5, 0.6, 0.44))
        m = smin(m, ell(g, (0, bot + 0.3, zf - 0.08), (0.3, 0.36, 0.22)), 0.12)
        m = smin(m, ell(g, (0, top - 0.05, zf - 0.32), (0.3, 0.2, 0.4)), 0.12)
        m = m - 0.07 * (n1 - 0.5) - 0.035 * (n2 - 0.5)
        face = ell(g, mz + np.array([0, 0.06, 0.02]) * hs, np.array([0.33, 0.36, 0.3]) * hs)
        mane = smax(m, -face, 0.05)
        d = np.minimum(d, mane)
    # The tail along its parts, the lion's tuft at its end.
    pts = []
    for n in ("tail", "tailTip"):
        if n in K:
            R, pos, half = K[n]
            pts.append(pos + R @ np.array([0, 0, half[2]]))
            pts.append(pos - R @ np.array([0, 0, half[2]]))
    tail = None
    for a, b in zip(pts[0::2], pts[1::2]):
        t = cap(g, a, b, 0.055, 0.045)
        tail = t if tail is None else smin(tail, t, 0.04)
    if tail is not None:
        d = smin(d, tail, 0.05)
    tuft = None
    if "tuft" in K:
        R, pos, half = K["tuft"]
        tuft = ell(g, pos, (0.1, 0.1, 0.13)) - 0.03 * (vnoise(np.abs(g.X), g.Y, g.Z, 0.03, 9) - 0.5)
        d = np.minimum(d, tuft)
    occ = d < 0
    # Colours and kinds.
    col = np.zeros(g.shape + (3,))
    kind = np.full(g.shape, FUR, np.uint8)
    fur = hexc(P["fur"])
    light = hexc(P["light"])
    clump = vnoise(np.abs(g.X), g.Y, g.Z, 0.045, 1)
    fine = hash3(np.floor(np.abs(g.X) / g.cell * 0.5), np.floor(g.Y / g.cell * 0.5), np.floor(g.Z / g.cell * 0.5), 2)
    base = fur[None, None, None, :] * (1.0 + 0.16 * (clump - 0.5) + 0.06 * (fine - 0.5))[..., None]
    back = np.clip((g.Y - (top - 0.25)) / 0.25, 0, 1) * (np.abs(g.X) < 0.25)
    base = base * (1 - 0.18 * back)[..., None]
    belly = np.clip((bot + 0.25 - g.Y) / 0.25, 0, 1) * (g.Z < zf) * (g.Z > zb + 0.2) * (g.Y > 0.8)
    inner = (np.abs(g.X) < 0.16) & (g.Y < 1.0) & (g.Y > 0.3)
    lt = np.maximum(belly, inner * 0.7)
    col[:] = base * (1 - lt[..., None]) + light[None, None, None, :] * (1.0 + 0.08 * (clump - 0.5))[..., None] * lt[..., None]
    near_mz = ell(g, mz + np.array([0, -0.02, 0.06]) * hs, np.array([0.15, 0.12, 0.14]) * hs) < 0.01
    near_ch = ell(g, chin, np.array([0.12, 0.075, 0.13]) * hs) < 0.01
    col[near_mz | near_ch] = light * (0.98 + 0.06 * (fine[near_mz | near_ch] - 0.5))[:, None]
    nose = ell(g, mz + np.array([0, 0.07, 0.13]) * hs, np.array([0.06, 0.045, 0.06]) * hs) < 0
    col[nose] = hexc(P["nose"])
    kind[nose] = WET
    mouth = (np.abs(g.Y - (mz[1] - 0.075 * hs)) < 0.012) & (g.Z > mz[2] - 0.02) & (np.abs(g.X) < 0.12 * hs)
    col[mouth & occ] = (0.16, 0.08, 0.06)
    for ec in eyes:
        e = ell(g, ec, np.array([0.05, 0.035, 0.045]) * hs) < 0.004
        col[e] = hexc(P["eye"])
        kind[e] = WET
        pupil = e & (np.abs(g.X - ec[0]) < 0.012) & (np.abs(g.Y - ec[1]) < 0.03)
        col[pupil] = (0.04, 0.03, 0.02)
        rim = (ell(g, ec, np.array([0.065, 0.048, 0.055]) * hs) < 0.004) & ~e
        col[rim & (g.Z > ec[2] - 0.02)] = (0.18, 0.1, 0.06)
    col[ears < 0.004] = hexc(P["ear"])
    inner_e = (ears < 0.004) & (g.Z > hc[2] - 0.04 * hs + 0.015)
    col[inner_e] = light * 0.85
    if mane is not None:
        # (All of the mane's own room, not only where it is the outermost: the head and the chest
        # come through its tufts here and there, and stayed golden flecks in the dark mane.)
        mk = mane < 0.012
        mn = vnoise(np.abs(g.X), g.Y, g.Z, 0.035, 7)
        mc = hexc(P["mane"])[None, :] * (1 - mn[mk])[:, None] + hexc(P["mane2"])[None, :] * mn[mk][:, None]
        col[mk] = mc * (1.0 + 0.1 * (fine[mk] - 0.5))[:, None]
    if tuft is not None:
        col[tuft < 0.004] = hexc(P["mane2"] or P["dark"])
    if P["stripes"]:
        wv = vnoise(np.abs(g.X), g.Y, g.Z, 0.12, 4)
        s1 = np.sin((g.Z * 9.5 + (g.Y - 1.3) * 3.0 + wv * 2.4) * math.pi)
        st = (s1 > 0.8) & (g.Y > bot + 0.1) & ~(belly > 0.4) & (sk >= 0.004)
        legst = (np.sin((g.Y * 11.0 + wv * 2.0) * math.pi) > 0.8) & (g.Y < 0.9) & (np.abs(g.X) > 0.2)
        facest = (np.sin(((g.Y - hc[1]) * 18.0 + np.abs(g.X) * 7.0 + wv) * math.pi) > 0.9) & (sk < 0.004) & (g.Z < mz[2] - 0.05) & ((np.abs(g.X) > 0.16 * hs) | (g.Y > hc[1] + 0.12 * hs))
        tailst = (np.sin(((g.Z + g.Y) * 10.0) * math.pi) > 0.6) & (tail < 0.004) if tail is not None else np.zeros_like(st)
        col[(st | legst | facest | tailst) & ~(ears < 0.004) & ~near_mz & ~near_ch & ~nose] = (0.09, 0.06, 0.04)
        for ec in eyes:
            col[(ell(g, ec + np.array([0, 0.055, -0.01]) * hs, np.array([0.05, 0.022, 0.05]) * hs) < 0.004)] = light
        cheek = (sk < 0.004) & (g.Y < hc[1] - 0.05) & (np.abs(g.X) > 0.1) & (g.Z > hc[2] - 0.02)
        col[cheek & ~near_mz] = light * 0.98
    ck = claws < 0.003
    col[ck] = (0.9, 0.86, 0.76)
    kind[ck] = BONE
    return d, np.clip(col, 0, 1), kind


SCULPTS = {name: (lambda sp, g, P=P: cat(sp, g, P)) for name, P in CATS.items()}


# ---------- the dogs, the bear and the boar ----------

QUADS = {
    "wolf": dict(head="dog", ears="pointed", tail="bushy", fur=0x8e8e96, light=0xd8d4cc, dark=0x55555d, nose=0x141214, eye=0xd8a030, leg=1.0, mark="saddle"),
    "hyena": dict(head="dog", ears="round", tail="tufted", fur=0xb89a6a, light=0xd8c49a, dark=0x3e2c1c, nose=0x141010, eye=0x8a5a20, leg=1.0, mark="spots", ridge=True),
    "bear": dict(head="bear", ears="round", tail="none", fur=0x7c4426, light=0xa47a4c, dark=0x4a2814, nose=0x120e0c, eye=0x2a1a10, leg=1.05, mark="none", hump=True, paw="bear", back=0.8),
    # A wild boar (user: it looked like a brown lump): a long wedge of a head ending in the disc of
    # its snout, small eyes, ears pricked; the trunk deep in the chest and narrow, the belly drawn
    # up to the hind legs; a crest of bristles down the spine (hair, not a hump); a coarse coat
    # grizzled grey over dark brown, the legs darker; the tusks long and white, curled up.
    "boar": dict(head="boar", ears="pointed", tail="thin", fur=0x58493f, light=0x84766a, dark=0x261d18, nose=0x7a5e58, eye=0x140c08, leg=0.9, mark="grizzle", ridge="crest", paw="hoof", trunk="boar", tusk_k=1.35, eye_r=0.055),
    "bull": dict(head="bovine", ears="side", tail="thin", fur=0x262020, light=0x4a3a34, dark=0x141010, nose=0x3e3232, eye=0x1a0e08, leg=1.0, mark="none", paw="hoof"),
    "goat": dict(head="bovine", ears="side", tail="short", fur=0xece6d6, light=0xf6f2ea, dark=0x8a8478, nose=0x6a5a54, eye=0xb08020, leg=0.9, mark="none", paw="hoof", snout=0.68),
    "rat": dict(head="dog", ears="big", tail="rat", fur=0x5a4a44, light=0x8a7a72, dark=0x3a2e2a, nose=0xd08a8a, eye=0x0a0606, leg=1.0, mark="none"),
    "rhino": dict(head="bovine", ears="side", tail="thin", fur=0x9a9288, light=0xaaa298, dark=0x6a645c, nose=0x6a645c, eye=0x1a1410, leg=1.05, mark="hide", paw="hoof"),
    "elephant": dict(head="elephant", ears="fan", tail="thin", fur=0x9a9a9e, light=0xaeaeb0, dark=0x6e6e74, nose=0x7a7a80, eye=0x1a1410, leg=1.0, mark="hide", paw="pillar", eye_r=0.06),
    "mammoth": dict(head="elephant", ears="small_fan", tail="thin", fur=0x8a5a32, light=0xa8784a, dark=0x4e301a, nose=0x5a3a22, eye=0x1a1008, leg=1.0, mark="shaggy", paw="pillar", back=0.92, eye_r=0.055),
}


def _tail_points(K, names):
    pts = []
    for n in names:
        if n in K:
            R, pos, half = K[n]
            pts.append((pos + R @ np.array([0, 0, half[2]]), pos - R @ np.array([0, 0, half[2]])))
    return pts


def quad(sp, g, P):
    """A dog, a bear or a boar over the parts of `sp`: (distance, colour, kind) on `g`."""
    K = parts_of(sp)
    _, body, bh = K["beastBody"]
    _, hp, hh = K["beastHead"]
    hx, hy, hz = hh
    top = body[1] + bh[1]
    bot = body[1] - bh[1]
    zf = body[2] + bh[2]
    zb = body[2] - bh[2]
    W, Hh, L = bh
    # The trunk (as the cats', its shoulders and haunches; a bear's low hump over the shoulders, its
    # back level behind it: the box it fills is taller than a bear's back is high).
    bk = P.get("back", 1.0)
    cy = body[1] - (1.0 - bk) * Hh * 0.8
    if P.get("trunk") == "boar":
        # Deep and narrow in the chest, the back level, the belly drawn up toward the hind legs,
        # the haunches smaller than the shoulders.
        # (The box it fills is deeper than a boar is: the belly drawn up off its bottom, so the
        # legs show long under it, more behind than in front.)
        # (Narrow, as a boar is from the side: deep, not broad.)
        d = ell(g, (0, cy + 0.08 * Hh, body[2] + 0.4 * L), (0.64 * W, 0.84 * Hh, 0.6 * L))
        d = smin(d, ell(g, (0, cy + 0.16 * Hh, body[2]), (0.6 * W, 0.72 * Hh, 0.78 * L)), 0.12)
        d = smin(d, ell(g, (0, cy + 0.26 * Hh, body[2] - 0.52 * L), (0.54 * W, 0.58 * Hh, 0.4 * L)), 0.14)
        d = smin(d, ell(g, (0, cy + 0.24 * Hh, body[2] - 0.74 * L), (0.54 * W, 0.56 * Hh, 0.28 * L)), 0.12)
        for sx in (-1, 1):
            d = smin(d, ell(g, (sx * 0.34 * W, cy + 0.12 * Hh, body[2] + 0.5 * L), (0.26 * W, 0.6 * Hh, 0.28 * L)), 0.1)
            d = smin(d, ell(g, (sx * 0.36 * W, cy + 0.16 * Hh, body[2] - 0.66 * L), (0.28 * W, 0.5 * Hh, 0.28 * L)), 0.1)
    else:
        d = ell(g, (0, cy - 0.02 * Hh, body[2] + 0.4 * L), (0.92 * W, 0.94 * Hh * bk, 0.62 * L))
        d = smin(d, ell(g, (0, cy + 0.04 * Hh * bk, body[2]), (0.88 * W, 0.86 * Hh * bk, 0.8 * L)), 0.12)
        d = smin(d, ell(g, (0, cy + 0.1 * Hh * bk, body[2] - 0.5 * L), (0.8 * W, 0.78 * Hh * bk, 0.42 * L)), 0.14)
        d = smin(d, ell(g, (0, cy + 0.08 * Hh * bk, body[2] - 0.72 * L), (0.84 * W, 0.8 * Hh * bk, 0.32 * L)), 0.14)
        for sx in (-1, 1):
            d = smin(d, ell(g, (sx * 0.44 * W, cy + (0.64 * Hh) * bk, body[2] + 0.52 * L), (0.34 * W, 0.38 * Hh * bk, 0.26 * L)), 0.1)
            d = smin(d, ell(g, (sx * 0.5 * W, cy + 0.02 * Hh * bk, body[2] - 0.66 * L), (0.42 * W, 0.6 * Hh * bk, 0.3 * L)), 0.12)
    if P.get("hump"):
        d = smin(d, ell(g, (0, cy + 0.72 * Hh * bk, body[2] + 0.46 * L), (0.5 * W, 0.2 * Hh, 0.26 * L)), 0.12)
    # The legs, down to the paw (a bear's broad, clawed; a boar's small cloven hoof).
    legs = None
    claws = None
    hooves = None
    paw = P.get("paw", "paw")
    for fb, up, lo_n in (("F", "legFL", "legFLLo"), ("F", "legFR", "legFRLo"), ("B", "legBL", "legBLLo"), ("B", "legBR", "legBRLo")):
        if up not in K or lo_n not in K:
            continue
        _, pu, hu = K[up]
        _, pl, hl = K[lo_n]
        x = pu[0]
        sx = 1 if x > 0 else -1
        ground = pl[1] - hl[1]
        knee = pu[1] - hu[1]
        hip = pu[1] + hu[1]
        zc = pu[2]
        r0 = hu[0] * 0.92 * P.get("leg", 1.0)
        if fb == "F":
            l = cap(g, (x, hip, zc), (x, knee + 0.02, pl[2] - 0.01), r0 * 1.02, r0 * 0.66)
            l = smin(l, ell(g, (x + sx * 0.01, hip - 0.04, zc + 0.01), (r0 * 0.9, (hip - knee) * 0.62, r0 * 1.2)), 0.08)
            l = smin(l, cap(g, (x, knee + 0.02, pl[2] - 0.01), (x, ground + 0.06, pl[2] - 0.02), r0 * 0.62, r0 * 0.5), 0.06)
        else:
            l = ell(g, (x, hip - 0.02, zc + 0.02), (r0 * 0.95, (hip - knee) * 0.72, r0 * 1.35))
            l = smin(l, cap(g, (x, knee + 0.06, zc - 0.03), (x, knee - 0.02, pl[2] - 0.6 * hl[2]), r0 * 0.8, r0 * 0.55), 0.07)
            l = smin(l, cap(g, (x, knee - 0.02, pl[2] - 0.6 * hl[2]), (x, ground + 0.06, pl[2] - 0.02), r0 * 0.5, r0 * 0.48), 0.05)
        pz = pl[2] + 0.2 * hl[2]
        if paw == "hoof":
            hf = ell(g, (x, ground + 0.04, pz), (r0 * 0.5, 0.045, r0 * 0.55))
            hooves = hf if hooves is None else np.minimum(hooves, hf)
            l = smin(l, hf, 0.03)
        elif paw == "pillar":
            l = smin(l, cap(g, (x, ground + 0.25, pl[2]), (x, ground + 0.08, pl[2]), r0 * 0.6, r0 * 0.66), 0.08)
            for tx in (-0.5, 0.0, 0.5):
                nl = ell(g, (x + tx * r0 * 0.55, ground + 0.06, pl[2] + r0 * 0.6), (r0 * 0.14, 0.05, r0 * 0.1))
                claws = nl if claws is None else np.minimum(claws, nl)
        else:
            big = 1.2 if paw == "bear" else 1.0
            l = smin(l, ell(g, (x, ground + 0.05 * big, pz), (r0 * 0.78 * big, 0.06 * big * big, r0 * 1.0 * big)), 0.05)
            for tx in (-0.55, -0.18, 0.18, 0.55):
                tc = (x + tx * r0 * 0.95 * big, ground + 0.04, pz + r0 * 0.8 * big)
                l = smin(l, ell(g, tc, (r0 * 0.26 * big, 0.045, r0 * 0.3 * big)), 0.02)
                cl = cap(g, (tc[0], ground + 0.03, tc[2] + r0 * 0.2 * big), (tc[0], ground + 0.01, tc[2] + r0 * (0.42 if paw == "bear" else 0.34) * big), 0.016 * big, 0.008)
                claws = cl if claws is None else np.minimum(claws, cl)
        legs = l if legs is None else np.minimum(legs, l)
    if legs is not None:
        d = smin(d, legs, 0.1)
    if claws is not None:
        d = np.minimum(d, claws)
    # The neck to the head.
    back = hp + np.array([0, 0.1 * hy, -0.75 * hz])
    d = smin(d, cap(g, (0, cy + 0.5 * Hh * bk, zf - 0.25 * L), back, min(W, Hh * bk) * 0.56, min(hx, hy) * 0.6), 0.14)
    # The head, by its kind.
    kind_h = P["head"]
    eyes = []
    if kind_h == "dog":
        hc = hp + np.array([0, 0.16 * hy, -0.22 * hz])
        sk = ell(g, hc, (0.6 * hx, 0.56 * hy, 0.5 * hz))
        for sx in (-1, 1):
            sk = smin(sk, ell(g, hp + np.array([sx * 0.3 * hx, -0.06 * hy, -0.05 * hz]), (0.34 * hx, 0.38 * hy, 0.42 * hz)), 0.05)
        mz_a = hp + np.array([0, -0.04 * hy, 0.1 * hz])
        mz_b = hp + np.array([0, -0.2 * hy, 0.86 * hz])
        sk = smin(sk, cap(g, mz_a, mz_b, 0.36 * hx, 0.22 * hx), 0.06)
        sk = smin(sk, cap(g, hp + np.array([0, -0.36 * hy, 0.05 * hz]), hp + np.array([0, -0.4 * hy, 0.72 * hz]), 0.25 * hx, 0.15 * hx), 0.05)
        nose_c = hp + np.array([0, -0.12 * hy, 0.93 * hz])
        nose_r = (0.16 * hx, 0.12 * hy, 0.08 * hz)
        for sx in (-1, 1):
            eyes.append(hp + np.array([sx * 0.32 * hx, 0.14 * hy, 0.28 * hz]))
        ear_c = [hp + np.array([sx * 0.42 * hx, 0.6 * hy, -0.3 * hz]) for sx in (-1, 1)]
    elif kind_h == "bear":
        hc = hp + np.array([0, 0.08 * hy, -0.18 * hz])
        sk = ell(g, hc, (0.56 * hx, 0.52 * hy, 0.5 * hz))
        for sx in (-1, 1):
            sk = smin(sk, ell(g, hp + np.array([sx * 0.3 * hx, -0.14 * hy, 0.0]), (0.36 * hx, 0.36 * hy, 0.4 * hz)), 0.06)
        sk = smin(sk, cap(g, hp + np.array([0, -0.1 * hy, 0.2 * hz]), hp + np.array([0, -0.22 * hy, 0.74 * hz]), 0.3 * hx, 0.22 * hx), 0.07)
        sk = smin(sk, ell(g, hp + np.array([0, -0.4 * hy, 0.45 * hz]), (0.2 * hx, 0.12 * hy, 0.28 * hz)), 0.05)
        nose_c = hp + np.array([0, -0.14 * hy, 0.82 * hz])
        nose_r = (0.14 * hx, 0.1 * hy, 0.07 * hz)
        for sx in (-1, 1):
            eyes.append(hp + np.array([sx * 0.26 * hx, 0.14 * hy, 0.28 * hz]))
        ear_c = [hp + np.array([sx * 0.44 * hx, 0.52 * hy, -0.28 * hz]) for sx in (-1, 1)]
    elif kind_h == "bovine":
        hc = hp + np.array([0, 0.16 * hy, -0.18 * hz])
        sk = ell(g, hc, (0.56 * hx, 0.56 * hy, 0.52 * hz))
        sn = P.get("snout", 1.0)
        sk = smin(sk, cap(g, hp + np.array([0, 0.05 * hy, 0.0]), hp + np.array([0, -0.18 * hy, (0.68 + 0.2 * (1.0 - sn)) * hz]), 0.4 * hx * sn, 0.36 * hx * sn), 0.08)
        sk = smin(sk, ell(g, hp + np.array([0, -0.4 * hy, 0.4 * hz]), (0.3 * hx, 0.16 * hy, 0.4 * hz)), 0.05)
        nose_c = hp + np.array([0, -0.2 * hy, (0.9 + 0.2 * (1.0 - sn)) * hz])
        nose_r = (0.36 * hx * sn, 0.3 * hy * sn, 0.08 * hz)
        for sx in (-1, 1):
            eyes.append(hp + np.array([sx * 0.44 * hx, 0.2 * hy, 0.12 * hz]))
        ear_c = [hp + np.array([sx * 0.5 * hx, 0.28 * hy, -0.3 * hz]) for sx in (-1, 1)]
    elif kind_h == "elephant":
        # (Its head's box is as wide as its ears: the skull goes by its height.)
        hc = hp + np.array([0, 0.18 * hy, -0.05 * hz])
        sk = ell(g, hc, (0.62 * hy, 0.74 * hy, 0.8 * hz))
        sk = smin(sk, ell(g, hp + np.array([0, -0.2 * hy, 0.45 * hz]), (0.42 * hy, 0.5 * hy, 0.5 * hz)), 0.12)
        nose_c = hp + np.array([0, -0.55 * hy, 0.75 * hz])
        nose_r = (0.22 * hy, 0.2 * hy, 0.2 * hz)
        for sx in (-1, 1):
            eyes.append(hp + np.array([sx * 0.41 * hy, 0.1 * hy, 0.42 * hz]))
        ear_c = [hp + np.array([sx * 0.55 * hy, 0.05 * hy, -0.35 * hz]) for sx in (-1, 1)]
    elif kind_h == "boar":
        # A long wedge: the brow running straight down to the snout, the jaw under it, the snout
        # ending flat in its disc; small eyes high and far back; the ears pricked.
        hc = hp + np.array([0, 0.1 * hy, -0.34 * hz])
        sk = ell(g, hc, (0.5 * hx, 0.54 * hy, 0.44 * hz))
        sk = smin(sk, cap(g, hp + np.array([0, 0.02 * hy, -0.12 * hz]), hp + np.array([0, -0.2 * hy, 0.9 * hz]), 0.4 * hx, 0.2 * hx), 0.1)
        sk = smin(sk, cap(g, hp + np.array([0, -0.3 * hy, -0.12 * hz]), hp + np.array([0, -0.38 * hy, 0.62 * hz]), 0.28 * hx, 0.15 * hx), 0.06)
        for sx in (-1, 1):
            sk = smin(sk, ell(g, hp + np.array([sx * 0.26 * hx, -0.12 * hy, -0.2 * hz]), (0.26 * hx, 0.3 * hy, 0.32 * hz)), 0.05)
        nose_c = hp + np.array([0, -0.2 * hy, 0.97 * hz])
        nose_r = (0.22 * hx, 0.19 * hy, 0.05 * hz)
        for sx in (-1, 1):
            eyes.append(hp + np.array([sx * 0.33 * hx, 0.2 * hy, -0.02 * hz]))
        ear_c = [hp + np.array([sx * 0.3 * hx, 0.46 * hy, -0.46 * hz]) for sx in (-1, 1)]
    else:   # "pig"
        hc = hp + np.array([0, 0.12 * hy, -0.28 * hz])
        sk = ell(g, hc, (0.6 * hx, 0.6 * hy, 0.54 * hz))
        sk = smin(sk, cap(g, hp + np.array([0, 0.02 * hy, -0.05 * hz]), hp + np.array([0, -0.2 * hy, 0.9 * hz]), 0.44 * hx, 0.3 * hx), 0.08)
        sk = smin(sk, ell(g, hp + np.array([0, -0.42 * hy, 0.3 * hz]), (0.3 * hx, 0.14 * hy, 0.4 * hz)), 0.05)
        nose_c = hp + np.array([0, -0.2 * hy, 0.96 * hz])
        nose_r = (0.32 * hx, 0.28 * hy, 0.07 * hz)
        for sx in (-1, 1):
            eyes.append(hp + np.array([sx * 0.4 * hx, 0.26 * hy, 0.08 * hz]))
        ear_c = [hp + np.array([sx * 0.44 * hx, 0.56 * hy, -0.4 * hz]) for sx in (-1, 1)]
    nose = ell(g, nose_c, nose_r)
    sk = smin(sk, nose, 0.02)
    er = P.get("eye_r", 0.09 * hx)
    for ec in eyes:
        sk = smax(sk, -ell(g, ec + np.array([0, 0, 0.6 * er]), (er, er * 0.75, er * 0.8)), 0.012)
    ears = None
    for sx, ec in zip((-1, 1), ear_c):
        if P["ears"] == "pointed":
            e = cap(g, ec, ec + np.array([sx * 0.1 * hx, 0.5 * hy, -0.1 * hz]), 0.2 * hx, 0.025)
        elif P["ears"] == "flap":
            e = cap(g, ec, ec + np.array([sx * 0.28 * hx, 0.32 * hy, -0.12 * hz]), 0.14 * hx, 0.03)
        elif P["ears"] == "side":
            e = cap(g, ec, ec + np.array([sx * 0.42 * hx, -0.04 * hy, -0.08 * hz]), 0.13 * hx, 0.05 * hx)
        elif P["ears"] == "big":
            e = ell(g, ec + np.array([sx * 0.05 * hx, 0.16 * hy, 0]), (0.3 * hx, 0.32 * hy, 0.07 * hz))
        elif P["ears"] in ("fan", "small_fan"):
            k_e = 1.0 if P["ears"] == "fan" else 0.45
            e = ell(g, ec + np.array([sx * 0.42 * hy * k_e, -0.05 * hy, 0.0]), (0.5 * hy * k_e, 0.72 * hy * k_e, 0.07 * hy))
        else:
            e = ell(g, ec + np.array([0, 0.1 * hy, 0]), (0.18 * hx, 0.2 * hy, 0.08 * hz))
        ears = e if ears is None else np.minimum(ears, e)
    sk = smin(sk, ears, 0.03)
    d = smin(d, sk, 0.06)
    # A ridge of bristles down the neck and the back (a boar's, a hyena's mane).
    ridge = None
    if P.get("ridge") == "crest":
        # A boar's: a narrow crest of long bristles standing up from the nape along the spine to
        # past the middle of the back, in tufts (each bristle a column).
        # (Along the top of the back from the shoulders, and on from the nape to them: from the head,
        # carried low, it ran under the back.)
        a0 = np.array([0, top - 0.04 * Hh, zf - 0.08 * L])
        a1 = np.array([0, top - 0.06 * Hh, body[2] - 0.3 * L])
        tuft = vnoise(np.abs(g.X), g.Y, g.Z, 0.025, 11)
        crest_spine = cap(g, a0, a1, 0.3 * W, 0.2 * W)
        crest_spine = np.minimum(crest_spine, cap(g, hc + np.array([0, 0.5 * hy, -0.3 * hz]), a0, 0.2 * W, 0.3 * W))
        crest_spine = crest_spine - 0.05 * (tuft - 0.3)
        slab = np.abs(g.X) - 0.07 * W
        ridge = np.maximum(crest_spine, slab)
        d = np.minimum(d, ridge)
    elif P.get("ridge"):
        n1 = vnoise(np.abs(g.X), g.Y, g.Z, 0.04, 11)
        ridge = cap(g, hc + np.array([0, 0.45 * hy, -0.1 * hz]), (0, top - 0.02, body[2] - 0.1 * L), 0.12 * W, 0.08 * W) - 0.05 * (n1 - 0.4)
        d = np.minimum(d, ridge)
    # The tail.
    tail = None
    segs = _tail_points(K, ("tail", "tailTip"))
    for a, b in segs:
        r_a, r_b = {"bushy": (0.1, 0.11), "tufted": (0.06, 0.08), "thin": (0.035, 0.025), "rat": (0.045, 0.012), "short": (0.04, 0.03)}.get(P["tail"], (0.05, 0.04))
        t = cap(g, a, b, r_a, r_b)
        if P["tail"] == "bushy":
            t = t - 0.03 * (vnoise(np.abs(g.X), g.Y, g.Z, 0.035, 13) - 0.5)
        tail = t if tail is None else smin(tail, t, 0.04)
    if tail is not None:
        d = smin(d, tail, 0.05)
    tuft = None
    if "tuft" in K and P["tail"] == "thin":
        R, pos, half = K["tuft"]
        tuft = ell(g, pos, (0.05, 0.06, 0.08)) - 0.02 * (vnoise(np.abs(g.X), g.Y, g.Z, 0.02, 9) - 0.5)
        d = np.minimum(d, tuft)
    if P["mark"] == "shaggy":
        d = d - 0.045 * (vnoise(np.abs(g.X), g.Y, g.Z, 0.05, 33) - 0.45)   # (a mammoth's coat, in locks)
    # Tusks and horns along their own parts, broad at the root (the end by what they grow from).
    tusks = None
    horns = None
    pmap = {p["name"]: p for p in sp["parts"]}
    for n in K:
        if not (n.startswith("tusk") or n.startswith("horn")):
            continue
        R, pos, half = K[n]
        e0 = pos - R @ np.array([0, half[1], 0])
        e1 = pos + R @ np.array([0, half[1], 0])
        par = pmap[n].get("parent")
        if par in K and np.linalg.norm(e1 - K[par][1]) < np.linalg.norm(e0 - K[par][1]):
            e0, e1 = e1, e0
        tip = "Tip" in n or n in ("horn", "hornSmall")
        ra = 0.75 * half[0] if not tip or n in ("horn", "hornSmall") else 0.55 * half[0]
        rb = 0.45 * half[0] if not tip else 0.12 * half[0]
        if n in ("horn", "hornSmall"):
            ra = 0.95 * half[0]
        tk = P.get("tusk_k", 1.0) if n.startswith("tusk") else 1.0
        if tk != 1.0:
            # (Longer at the tip, as thick as the scale at the root: a boar's are a hand long.)
            e1 = e0 + (e1 - e0) * (1.0 + 0.3 * (tk - 1.0) * (2.0 if tip else 1.0))
            ra *= tk
            rb *= tk if not tip else 1.4
        t = cap(g, e0, e1, ra, rb)
        if n.startswith("tusk"):
            tusks = t if tusks is None else np.minimum(tusks, t)
        else:
            horns = t if horns is None else np.minimum(horns, t)
    if tusks is not None:
        d = np.minimum(d, tusks)
    if horns is not None:
        d = smin(d, horns, 0.02)
    trunk = None
    for n in ("trunk", "trunkTip"):
        if n in K:
            R, pos, half = K[n]
            e0 = pos + R @ np.array([0, half[1], 0])
            e1 = pos - R @ np.array([0, half[1], 0])
            ra, rb = (0.85 * half[0], 0.62 * half[0]) if n == "trunk" else (0.8 * half[0], 0.5 * half[0])
            t = cap(g, e0, e1, ra, rb)
            trunk = t if trunk is None else smin(trunk, t, 0.06)
    if trunk is not None:
        d = smin(d, trunk, 0.1)
    extra = None
    if "dewlap" in K:
        R, pos, half = K["dewlap"]
        extra = ell(g, pos + np.array([0, 0.2 * half[1], 0]), (0.7 * half[0], 1.0 * half[1], 0.75 * half[2]))
        d = smin(d, extra, 0.08)
    beard = None
    if "beard" in K:
        R, pos, half = K["beard"]
        beard = cap(g, pos + R @ np.array([0, half[1], 0]), pos - R @ np.array([0, half[1] * 0.6, 0]), 0.75 * half[1] * 0.5, 0.2 * half[0]) - 0.012 * (vnoise(np.abs(g.X), g.Y, g.Z, 0.015, 5) - 0.5)
        d = smin(d, beard, 0.02)
    occ = d < 0
    # Colours and kinds.
    col = np.zeros(g.shape + (3,))
    kind = np.full(g.shape, FUR, np.uint8)
    fur = hexc(P["fur"])
    light = hexc(P["light"])
    dark = hexc(P["dark"])
    clump = vnoise(np.abs(g.X), g.Y, g.Z, 0.04, 1)
    fine = hash3(np.floor(np.abs(g.X) / g.cell * 0.5), np.floor(g.Y / g.cell * 0.5), np.floor(g.Z / g.cell * 0.5), 2)
    base = fur[None, None, None, :] * (1.0 + 0.18 * (clump - 0.5) + 0.07 * (fine - 0.5))[..., None]
    col[:] = base
    belly = np.clip((bot + 0.22 * Hh * 2 - g.Y) / (0.22 * Hh * 2), 0, 1) * (g.Z < zf) * (g.Z > zb) * (g.Y > bot - 0.1)
    col = col * (1 - belly[..., None] * 0.7) + light[None, None, None, :] * (belly[..., None] * 0.7)
    if P["mark"] == "grizzle":
        # Coarse bristles, dark at the root and pale at the tip: a grey over the brown, in flecks;
        # the legs darker toward the hooves, the face a shade greyer.
        gz = hash3(np.floor(np.abs(g.X) / g.cell), np.floor(g.Y / g.cell), np.floor(g.Z / g.cell), 41)
        fleck = gz > 0.66
        col[fleck] = col[fleck] * 0.55 + light[None, :] * 0.45 * (1.0 + 0.2 * gz[fleck][:, None])
        if legs is not None:
            lk = legs < 0.004
            low = np.clip((bot - g.Y[lk]) / 0.3, 0, 1)[:, None]
            col[lk] = col[lk] * (1 - low * 0.55) + dark[None, :] * (low * 0.55)
    if P["mark"] == "saddle":
        sad = np.clip((g.Y - (top - 0.35 * Hh)) / (0.3 * Hh), 0, 1) * (g.Z > zb - 0.1) * (g.Z < zf + 0.2)
        col = col * (1 - sad[..., None] * 0.6) + dark[None, None, None, :] * sad[..., None] * 0.6
    if P["mark"] == "spots":
        sp_n = vnoise(np.abs(g.X), g.Y, g.Z, 0.06, 21)
        spots = (sp_n > 0.68) & (g.Y > 0.25) & (sk >= 0.004)
        col[spots] = dark * 1.1
    # The muzzle and the face (a dog's light cheeks and a dark muzzle; a bear's pale snout).
    near_mz = (sk < 0.004) & (g.Z > hp[2] + 0.3 * hz) & (g.Y < hp[1] + 0.05 * hy)
    if kind_h == "dog":
        col[near_mz] = (dark * 0.9 if P["mark"] == "spots" else light * 0.95)
    elif kind_h == "bear":
        col[near_mz] = light
    col[nose < 0.004] = hexc(P["nose"])
    kind[nose < 0.004] = WET
    for ec in eyes:
        e = ell(g, ec, (er, er * 0.75, er * 0.8)) < 0.004
        # (the lids round it, a shade darker than the face: an eye set in, not a hole)
        lid = (ell(g, ec, (er * 1.7, er * 1.3, er * 1.4)) < 0.004) & ~e & occ
        col[lid] = col[lid] * 0.78
        col[e] = hexc(P["eye"])
        kind[e] = WET
        pupil = e & (np.abs(g.X - ec[0]) < er * 0.35) & (np.abs(g.Y - ec[1]) < er * 0.45)
        col[pupil] = (0.03, 0.02, 0.02)
        glint = e & (g.Y > ec[1] + er * 0.25) & (np.abs(g.Z - (ec[2] + er * 0.5)) < er * 0.3)
        col[glint] = (0.85, 0.85, 0.82)
    if ears is not None:
        ek = ears < 0.004
        col[ek] = fur * 0.82 if P["mark"] in ("none", "hide", "shaggy") else dark
    if ridge is not None:
        rk = (ridge < 0.004) & (d >= ridge - 0.004)
        col[rk] = dark * (0.9 + 0.2 * fine[rk])[:, None]
        if P.get("ridge") == "crest":
            # The bristles' tips pale (the crest's top), their roots dark.
            tipk = rk & (crest_spine > -0.03)
            col[tipk] = col[tipk] * 0.4 + light[None, :] * 0.75
    if kind_h == "boar":
        # The snout's disc: pinkish grey, two dark nostrils in it.
        dk = nose < 0.004
        for sx in (-1, 1):
            nst = ell(g, nose_c + np.array([sx * 0.09 * hx, 0.0, 0.02 * hz]), (0.05 * hx, 0.07 * hy, 0.06 * hz)) < 0.004
            col[nst & dk] = (0.08, 0.05, 0.05)
    if tail is not None and P["tail"] in ("bushy", "tufted"):
        tk = tail < 0.004
        tip = tk & (g.Y < np.percentile(g.Y[tk], 30) if tk.any() else tk)
        col[tip] = dark
    if tuft is not None:
        col[tuft < 0.004] = dark
    if tusks is not None:
        tk2 = tusks < 0.004
        col[tk2] = (0.92, 0.88, 0.78)
        kind[tk2] = BONE
    if horns is not None:
        hk = horns < 0.004
        hn = vnoise(np.abs(g.X), g.Y, g.Z, 0.05, 17)
        col[hk] = (np.array([0.84, 0.78, 0.64]) * (0.8 + 0.3 * hn[hk])[:, None])
        kind[hk] = BONE
    if beard is not None:
        col[beard < 0.004] = dark * 1.25
    if trunk is not None:
        tkk = trunk < 0.004
        rings = tkk & (np.sin(g.Y * 70.0) > 0.6)
        col[rings] = col[rings] * 0.8
    if P["mark"] == "shaggy":
        sh_n = vnoise(np.abs(g.X), g.Y, g.Z, 0.05, 31)
        col[occ] = col[occ] * (0.82 + 0.3 * sh_n[occ])[:, None]
    if P["mark"] == "hide":
        folds = (np.sin(g.Y * 60.0 + vnoise(np.abs(g.X), g.Y, g.Z, 0.08, 23) * 6.0) > 0.85) & (sk >= 0.004)
        col[folds & occ] = col[folds & occ] * 0.82
    if P["tail"] == "rat" and tail is not None:
        col[tail < 0.004] = hexc(P["nose"]) * 0.9
    if P["ears"] == "big" and ears is not None:
        col[(ears < 0.004)] = hexc(P["nose"])
    if claws is not None:
        ck = claws < 0.003
        col[ck] = (0.25, 0.2, 0.17) if paw == "bear" else ((0.78, 0.74, 0.66) if paw == "pillar" else (0.85, 0.8, 0.72))
        kind[ck] = BONE
    if hooves is not None:
        col[(hooves < 0.004) & (g.Y < 0.12)] = (0.16, 0.12, 0.1)
    return d, np.clip(col, 0, 1), kind


for _name, _P in QUADS.items():
    SCULPTS[_name] = (lambda sp, g, P=_P: quad(sp, g, P))


# ---------- the rest, sculpted part by part (the reptiles, the serpents, the birds, the crawlers,
# the ape and the beasts of myth) ----------
#
# Each part gets a shape by what it is: the trunk a body, a neck, a leg, a tail or a coil a limb
# tapering from where it hangs to where the next hangs (or to the far side of its box), a head by
# its kind (a reptile's long snout, a bird's beak, a dog's muzzle, a goat's, an ape's brow), a wing
# a membrane (or feathers), a horn, a fang, a sting a tapering point, a scorpion's claw a pincer;
# each joined smoothly to the part it hangs from. The colours are the beast's own, as its voxels
# are painted (gen_fine_beasts.voxel_paint: the outside's, never the flesh inside), with the
# texture of what it is over them: scales in plates, a shell in segments, fur in clumps.

KIT = {}
SCALE_KIND, CHITIN_KIND, GLOW_KIND = 10, 11, 12


def _part_info(sp):
    """name -> (R, pos, half, joint (world, or None), scale, parent name, children names)."""
    K = parts_of(sp)
    out = {}
    kids = {}
    for p in sp["parts"]:
        kids.setdefault(p.get("parent"), []).append(p["name"])
    for p in sp["parts"]:
        R, pos, half = K[p["name"]]
        s = float(p["scale"])
        j = None
        if p.get("ca") is not None and p.get("parent"):
            j = pos + R @ (np.array(p["ca"], float) * s)
        out[p["name"]] = (R, pos, half, j, s, p.get("parent"), kids.get(p["name"], []))
    return out


def _limb_ends(info, n):
    """Where a limb starts (its joint) and ends (where its one child hangs, else the far side of
    its box from the joint)."""
    R, pos, half, j, s, par, kids = info[n]
    if j is None:
        ax = int(np.argmax(half))
        e = R[:, ax] * half[ax]
        return pos - e, pos + e
    if len(kids) == 1 and info[kids[0]][3] is not None:
        return j, info[kids[0]][3]
    far = pos + (pos - j)
    return j, far


def _across(half, R, a, b):
    """The box's half size across the line a-b (the mean of the two halves most across it)."""
    u = b - a
    L = np.linalg.norm(u)
    if L < 1e-6:
        return float(np.mean(half))
    u = u / L
    w = [abs(float(R[:, i] @ u)) for i in range(3)]
    order = np.argsort(w)   # the axes least along the line first
    return float(half[order[0]] + half[order[1]]) * 0.5


def _head(g, R, pos, half, kind, P):
    """A head of `kind` in its box (R, pos, half): its forward is its +z."""
    f = R[:, 2]
    up = R[:, 1]
    hx, hy, hz = half
    if kind == "reptile":
        # A low skull and a long flat snout tapering to the nostrils, the jaw under it.
        sk = ell(g, pos - f * 0.35 * hz + up * 0.08 * hy, (0.78 * hx, 0.7 * hy, 0.5 * hz))
        sk = smin(sk, cap(g, pos - f * 0.1 * hz + up * 0.02 * hy, pos + f * 0.92 * hz - up * 0.05 * hy, 0.62 * min(hx, hy), 0.36 * min(hx, hy)), 0.08 * hz)
        for sx in (-1, 1):
            sk = smin(sk, ell(g, pos - f * 0.3 * hz + R[:, 0] * sx * 0.48 * hx + up * 0.36 * hy, (0.22 * hx, 0.2 * hy, 0.22 * hz)), 0.05 * hz)
        return sk
    if kind == "snake":
        sk = ell(g, pos - f * 0.1 * hz, (0.82 * hx, 0.62 * hy, 0.8 * hz))
        return smin(sk, cap(g, pos, pos + f * 0.9 * hz - up * 0.05 * hy, 0.5 * min(hx, hy), 0.3 * min(hx, hy)), 0.06 * hz)
    if kind == "bird":
        # A round skull and a beak, hooked when P says (a griffin's: an eagle's).
        sk = ell(g, pos - f * 0.25 * hz + up * 0.1 * hy, (0.7 * hx, 0.72 * hy, 0.58 * hz))
        if P.get("hooked"):
            sk = smin(sk, cap(g, pos + f * 0.05 * hz, pos + f * 0.82 * hz - up * 0.12 * hy, 0.42 * min(hx, hy), 0.12 * min(hx, hy)), 0.05 * hz)
            sk = smin(sk, cap(g, pos + f * 0.78 * hz - up * 0.1 * hy, pos + f * 0.9 * hz - up * 0.5 * hy, 0.12 * min(hx, hy), 0.04 * min(hx, hy)), 0.02 * hz)
        else:
            sk = smin(sk, cap(g, pos + f * 0.05 * hz, pos + f * 0.95 * hz - up * 0.08 * hy, 0.38 * min(hx, hy), 0.2 * min(hx, hy)), 0.04 * hz)
        return sk
    if kind == "dog":
        sk = ell(g, pos - f * 0.22 * hz + up * 0.14 * hy, (0.62 * hx, 0.6 * hy, 0.52 * hz))
        sk = smin(sk, cap(g, pos + f * 0.05 * hz - up * 0.05 * hy, pos + f * 0.88 * hz - up * 0.18 * hy, 0.38 * hx, 0.24 * hx), 0.06 * hz)
        for sx in (-1, 1):
            e = cap(g, pos - f * 0.3 * hz + R[:, 0] * sx * 0.4 * hx + up * 0.6 * hy, pos - f * 0.4 * hz + R[:, 0] * sx * 0.5 * hx + up * 1.05 * hy, 0.18 * hx, 0.03)
            sk = smin(sk, e, 0.03 * hz)
        return sk
    if kind == "goat":
        sk = ell(g, pos - f * 0.2 * hz + up * 0.12 * hy, (0.58 * hx, 0.6 * hy, 0.55 * hz))
        return smin(sk, cap(g, pos + f * 0.05 * hz, pos + f * 0.85 * hz - up * 0.25 * hy, 0.36 * hx, 0.26 * hx), 0.06 * hz)
    if kind == "ape":
        # A domed skull with a heavy brow, a muzzle under it, the jaw deep.
        sk = ell(g, pos + up * 0.12 * hy - f * 0.12 * hz, (0.72 * hx, 0.78 * hy, 0.7 * hz))
        sk = smin(sk, ell(g, pos + f * 0.45 * hz - up * 0.22 * hy, (0.5 * hx, 0.4 * hy, 0.4 * hz)), 0.08 * hz)
        sk = smin(sk, cap(g, pos + f * 0.55 * hz + up * 0.2 * hy - R[:, 0] * 0.42 * hx, pos + f * 0.55 * hz + up * 0.2 * hy + R[:, 0] * 0.42 * hx, 0.13 * hy), 0.04 * hz)
        return sk
    if kind == "spider":
        return ell(g, pos, (0.86 * hx, 0.8 * hy, 0.86 * hz))
    if kind == "scorpion":
        return ell(g, pos - f * 0.05 * hz, (0.9 * hx, 0.7 * hy, 0.86 * hz))
    if kind == "lion":
        sk = ell(g, pos - f * 0.15 * hz + up * 0.08 * hy, (0.68 * hx, 0.68 * hy, 0.6 * hz))
        return smin(sk, cap(g, pos + f * 0.1 * hz - up * 0.08 * hy, pos + f * 0.8 * hz - up * 0.18 * hy, 0.42 * hx, 0.3 * hx), 0.07 * hz)
    # A plain round head.
    return ell(g, pos, (0.82 * hx, 0.82 * hy, 0.86 * hz))


def _poly2(u, v, pts):
    """A convex polygon's signed distance in the plane (pts counter-clockwise, (u, v)): exact
    inside, a fair bound outside."""
    d = None
    n = len(pts)
    for i in range(n):
        a = np.array(pts[i], float)
        b = np.array(pts[(i + 1) % n], float)
        e = b - a
        L = float(np.hypot(e[0], e[1]))
        if L < 1e-9:
            continue
        nx, ny = e[1] / L, -e[0] / L   # outward for counter-clockwise
        di = (u - a[0]) * nx + (v - a[1]) * ny
        d = di if d is None else np.maximum(d, di)
    return d


def _ccw(pts):
    """The convex hull of 2-D points, counter-clockwise."""
    pts = sorted(set((float(a), float(b)) for a, b in pts))
    if len(pts) < 3:
        return pts
    def cross(o, a, b):
        return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])
    lower, upper = [], []
    for q in pts:
        while len(lower) >= 2 and cross(lower[-2], lower[-1], q) <= 0:
            lower.pop()
        lower.append(q)
    for q in reversed(pts):
        while len(upper) >= 2 and cross(upper[-2], upper[-1], q) <= 0:
            upper.pop()
        upper.append(q)
    return lower[:-1] + upper[:-1]


def _wing(g, J, s, c, Ls, Hc, thick, style):
    """A wing from its root J outward along s (its span Ls), its chord along c (front +, half
    Hc), the normal across them: a bat's (a dragon's, a manticore's) an arm bone along its front to
    the wrist and fingers fanning from it to the tips, a membrane between them scalloped behind;
    a bird's (`feathers`) as thick as its feathers, their tips in a comb behind."""
    n = np.cross(s, c)
    n = n / max(np.linalg.norm(n), 1e-9)
    rx, ry, rz = g.X - J[0], g.Y - J[1], g.Z - J[2]
    u = rx * s[0] + ry * s[1] + rz * s[2]
    v = rx * c[0] + ry * c[1] + rz * c[2]
    w = rx * n[0] + ry * n[1] + rz * n[2]
    def at(a, b):
        return J + s * a + c * b
    wrist = (0.42 * Ls, 0.62 * Hc)
    tips = [(1.0 * Ls, 0.5 * Hc), (0.94 * Ls, -0.2 * Hc), (0.74 * Ls, -0.8 * Hc), (0.42 * Ls, -1.0 * Hc)]
    root = [(0.0, 0.45 * Hc), (0.0, -0.75 * Hc)]
    hull = _ccw([root[0], wrist] + tips + [root[1]])
    plane = _poly2(u, v, hull)
    if style == "feathers":
        # The feathers' tips in a comb along the back edge.
        comb = 0.04 * Hc * (np.abs(np.sin(u / max(Ls, 1e-6) * math.pi * 9.0)))
        plane = plane + np.where(v < -0.2 * Hc, comb, 0.0)
        mem = np.maximum(plane, np.abs(w) - thick)
    else:
        # Scalloped between the fingers' tips behind.
        for a, b in zip(tips[1:], tips[2:] + [root[1]]):
            mu, mv = (a[0] + b[0]) * 0.5, (a[1] + b[1]) * 0.5
            gap = math.hypot(a[0] - b[0], a[1] - b[1])
            # (Pushed out from the wing's middle, past the line between the two tips.)
            cu, cv = mu - 0.15 * Ls, mv - 0.42 * gap
            plane = np.maximum(plane, -(np.hypot(u - cu, v - cv) - 0.55 * gap))
        mem = np.maximum(plane, np.abs(w) - thick)
    rb = max(thick * 1.6, 0.035 * Hc)
    bones = cap(g, at(*root[0]), at(*wrist), rb * 1.5, rb * 1.1)
    for t in tips:
        bones = np.minimum(bones, cap(g, at(*wrist), at(*t), rb, rb * 0.35))
    return smin(mem, bones, rb * 0.6)


def _foot(g, b, r, style):
    """A foot at the bottom b of a leg (its radius there r), forward the beast's +z: a cat's or a
    dog's `paw` (a pad and four toes), a reptile's `claw` (flat, splayed toes), a bird's `talon`
    (three toes forward, one back), an ape's `fist` (on its knuckles). (shape, its nails)."""
    fwd = np.array([0.0, 0.0, 1.0])
    up = np.array([0.0, 1.0, 0.0])
    side = np.array([1.0, 0.0, 0.0])
    nails = None
    if style == "fist":
        return ell(g, b + up * 0.1 * r + fwd * 0.25 * r, (1.3 * r, 0.95 * r, 1.2 * r)), None
    if style == "paw":
        sh = ell(g, b + fwd * 0.5 * r - up * 0.3 * r, (1.15 * r, 0.7 * r, 1.4 * r))
        for sx in (-0.62, -0.21, 0.21, 0.62):
            t = b + fwd * (1.5 - 0.35 * abs(sx)) * r + side * sx * 1.25 * r - up * 0.45 * r
            sh = np.minimum(sh, ell(g, t, (0.36 * r, 0.42 * r, 0.44 * r)))
        return sh, None
    p0 = b + fwd * 0.35 * r - up * 0.55 * r
    if style == "claw":
        sh = ell(g, p0 + up * 0.08 * r, (1.2 * r, 0.5 * r, 1.05 * r))
        dirs = [(a, 1.75) for a in (-0.75, -0.26, 0.26, 0.75)]
    else:   # talon
        sh = ell(g, p0 + up * 0.12 * r, (0.75 * r, 0.55 * r, 0.75 * r))
        dirs = [(a, 2.3) for a in (-0.42, 0.0, 0.42)] + [(math.pi, 1.3)]
    for a, L in dirs:
        dv = fwd * math.cos(a) + side * math.sin(a)
        tip = p0 + dv * L * r - up * 0.12 * r
        sh = np.minimum(sh, cap(g, p0, tip, 0.33 * r, 0.2 * r))
        nl = cap(g, tip - dv * 0.1 * r, tip + dv * 0.55 * r - up * 0.22 * r, 0.2 * r, 0.04 * r)
        nails = nl if nails is None else np.minimum(nails, nl)
    return np.minimum(sh, nails), nails


def kit(sp, g, P, vc, vk):
    info = _part_info(sp)
    names = [p["name"] for p in sp["parts"]]
    d = None
    nails = None
    rad = {}
    roles = P.get("roles", {})
    heads = P.get("heads", {})
    for n in names:
        R, pos, half, j, s, par, kids = info[n]
        role = roles.get(n)
        if role is None:
            low = n.lower()
            if n == "beastBody":
                role = "body"
            elif n in heads:
                role = "head"
            elif low.startswith("wing"):
                role = "wing"
            elif low.startswith(("horn", "goathorn", "fang", "stinger", "tongue")):
                role = "point"
            elif low.startswith("claw"):
                role = "pincer"
            elif low in ("abdomen",):
                role = "blob"
            elif low in ("spines",):
                role = "spines"
            elif low in ("tailfin", "crest", "ruff", "plume", "collar", "tuft"):
                role = "blob"
            else:
                role = "limb"
        if role == "body":
            k = P.get("body", (0.94, 0.88, 0.96))
            sh = ell(g, pos, (half[0] * k[0], half[1] * k[1], half[2] * k[2]))
            r_here = float(min(half))
        elif role == "blob":
            k = list(P.get("blob", {}).get(n, (0.92, 0.92, 0.92)))
            th = int(np.argmin(half))
            if float(half[th]) < 0.45 * float(np.sort(half)[1]):
                k[th] *= 0.6   # (a fin, a crest, a ruff: thin, not a ball)
            sh = ell(g, pos, (half[0] * k[0], half[1] * k[1], half[2] * k[2]))
            if n.lower() == "crest":
                # A crown of spikes fanning up and back from the head.
                up = R[:, 1]
                fw = R[:, 2]
                base = pos - up * 0.6 * float(half[1])
                sh = ell(g, base, (half[0] * 0.5, half[1] * 0.45, half[2] * 0.7))
                for a in np.linspace(-0.9, 0.9, 5):
                    tip = base + up * float(half[1]) * 1.5 * math.cos(a * 0.8) - fw * float(half[2]) * 1.1 * math.sin(a)
                    sh = np.minimum(sh, cap(g, base + up * 0.1 * float(half[1]), tip, half[0] * 0.55, 0.01))
            if n.lower() in ("ruff", "plume", "tuft"):
                sh = sh - 0.25 * min(half) * (vnoise(np.abs(g.X), g.Y, g.Z, 0.35 * min(half), 7) - 0.4)
            r_here = float(min(half))
        elif role == "head":
            sh = _head(g, R, pos, half, heads[n], P)
            r_here = float(min(half))
        elif role == "wing":
            style = P.get("wings", "membrane")
            th = int(np.argmin(half))
            if style == "fold" or j is None:
                # Folded on the flank (an ostrich's): a plume of feathers, drooping behind.
                k = [0.9, 0.9, 0.9]
                k[th] = 0.6
                sh = ell(g, pos, tuple(half[i] * k[i] for i in range(3)))
                sh = sh - 0.3 * float(half[th]) * (vnoise(np.abs(g.X), g.Y, g.Z, 0.5 * float(half[th]), 19) - 0.4)
            else:
                # Spread: its span from the root out along the box's longest side, its chord along
                # the box's other side (front: the beast's front).
                spn = int(np.argmax(half))
                chd = 3 - spn - th
                sv = pos - j
                sv = sv - R[:, chd] * float(sv @ R[:, chd])
                sv = sv / max(np.linalg.norm(sv), 1e-9)
                cv = R[:, chd] if float(R[:, chd][2]) >= 0 else -R[:, chd]
                Ls = float(np.linalg.norm(pos - j)) + float(half[spn])
                thick = max(g.cell * 0.55, float(half[th]) * (0.35 if style == "membrane" else 0.8))
                sh = _wing(g, j, sv, cv, Ls, float(half[chd]), thick, style)
            r_here = float(half[th])
        elif role == "point":
            a, b = _limb_ends(info, n)
            r0 = _across(half, R, a, b) * 0.85
            sh = cap(g, a, b, r0, max(0.006, r0 * 0.12))
            r_here = r0
        elif role == "pincer":
            # The palm and two fingers forward of it, the outer one the thumb.
            a, b = _limb_ends(info, n)
            u = b - a
            L = float(np.linalg.norm(u))
            u = u / max(L, 1e-6)
            r0 = _across(half, R, a, b)
            palm = ell(g, a + u * 0.38 * L, (r0 * 0.95, r0 * 0.75, 0.42 * L)) if abs(u[2]) > 0.5 else cap(g, a, a + u * 0.6 * L, r0 * 0.9, r0 * 0.8)
            side = np.cross(u, np.array([0.0, 1.0, 0.0]))
            side = side / max(np.linalg.norm(side), 1e-6)
            f1 = cap(g, a + u * 0.6 * L + side * 0.3 * r0, b + side * 0.12 * r0, r0 * 0.42, r0 * 0.08)
            f2 = cap(g, a + u * 0.6 * L - side * 0.35 * r0, b - side * 0.3 * r0 - u * 0.08 * L, r0 * 0.36, r0 * 0.08)
            sh = smin(palm, np.minimum(f1, f2), 0.03)
            r_here = r0
        elif role == "spines":
            # A row of spines along the back, each a cone standing up.
            a, b = _limb_ends(info, n)
            sh = None
            up = R[:, 1]
            hgt = float(half[1]) * 1.6
            for t in np.linspace(0.06, 0.94, int(P.get("spines", 7))):
                c0 = a + (b - a) * t - up * 0.4 * hgt
                c1 = c0 + up * hgt * (0.7 + 0.3 * math.sin(t * math.pi))
                cone = cap(g, c0, c1, float(half[0]) * 1.1, 0.008)
                sh = cone if sh is None else np.minimum(sh, cone)
            r_here = float(half[0])
        else:
            a, b = _limb_ends(info, n)
            low = n.lower()
            leg = low.startswith("leg")
            r0 = _across(half, R, a, b) * P.get("limb_k", 0.95 if leg else 0.88)
            taper = 0.72
            if low.startswith("neck"):
                taper = 0.86
            elif low in ("tailtip", "tail3") or (low.startswith("tail") and not kids):
                taper = 0.22
            elif low.startswith(("tail", "coil")):
                taper = 0.8
            elif low.endswith("lo"):
                taper = P.get("foot_taper", 0.7)
            sh = cap(g, a, b, r0, r0 * taper)
            hk = float(P.get("haunch", 1.0))
            if leg and not low.endswith("lo") and par == "beastBody" and hk > 0:
                # The thigh's (the shoulder's) muscle, from the joint up into the body over it.
                bp, bh = info["beastBody"][1], info["beastBody"][2]
                top_y = bp[1] - 0.1 * bh[1]
                if top_y > a[1] + 0.5 * r0:
                    top = np.array([a[0] * 0.8, top_y, a[2]])
                    sh = smin(sh, cap(g, a - np.array([0.0, 0.45 * r0, 0.0]), top, r0 * 1.12 * hk, r0 * 1.4 * hk), 0.45 * r0)
            if leg and low.endswith("lo") and not kids:
                fs = P.get("feet", "none")
                if isinstance(fs, dict):
                    fs = fs.get(n[3:4], "none")   # (legFLLo: its front's or its back's)
                if fs != "none":
                    ft, nl = _foot(g, b, r0 * taper, fs)
                    sh = smin(sh, ft, 0.3 * r0 * taper)
                    if nl is not None:
                        nails = nl if nails is None else np.minimum(nails, nl)
            r_here = r0
        rad[n] = r_here
        if d is None:
            d = sh
        else:
            k = 0.06 if role in ("point", "pincer", "spines") else max(0.03, 0.45 * min(r_here, rad.get(par, r_here)))
            d = smin(d, sh, k)
    if P.get("yoke") and "legFL" in info and "legFR" in info:
        # An ape's shoulders over its arms: a yoke between them and its back's hump from them down
        # to the body.
        jl, jr = info["legFL"][3], info["legFR"][3]
        r = rad["legFL"] * float(P["yoke"])
        mid = (jl + jr) * 0.5
        bp, bh = info["beastBody"][1], info["beastBody"][2]
        yk = cap(g, jl + np.array([0.0, 0.25 * r, -0.2 * r]), jr + np.array([0.0, 0.25 * r, -0.2 * r]), r * 1.05)
        yk = smin(yk, cap(g, mid + np.array([0.0, 0.15 * r, -0.5 * r]), bp + np.array([0.0, 0.35 * bh[1], -0.25 * bh[2]]), r * 1.45, r * 1.25), 0.4 * r)
        # Its chest as broad as from arm to arm.
        yk = smin(yk, ell(g, np.array([0.0, mid[1] - 1.9 * r, mid[2] - 0.8 * r]), (abs(float(jl[0])) * 0.82, r * 2.3, r * 2.0)), 0.5 * r)
        d = smin(d, yk, 0.45 * r)
    # Colours: the beast's own, with the texture of what it is.
    col = np.array(vc, copy=True)
    kind = np.array(vk, copy=True)
    if nails is not None:
        m = nails < 0.5 * g.cell
        col[m] = np.array([0.62, 0.57, 0.48], np.float32)
        kind[m] = 6
    tex = P.get("tex", "scales")
    ax = np.abs(g.X)
    if tex == "scales":
        cs = P.get("scale_size", 0.05)
        pl = hash3(np.floor(ax / cs), np.floor(g.Y / cs), np.floor(g.Z / cs), 3)
        seam = (np.abs((ax / cs) % 1.0 - 0.5) > 0.42) | (np.abs((g.Z / cs) % 1.0 - 0.5) > 0.42)
        k = (0.9 + 0.2 * pl) * np.where(seam, 0.85, 1.0)
        col = col * k[..., None]
    elif tex == "chitin":
        seg = np.abs((g.Z / P.get("seg", 0.12)) % 1.0 - 0.5) > 0.44
        col = col * np.where(seg, 0.7, 1.0)[..., None]
    else:
        clump = vnoise(ax, g.Y, g.Z, 0.04, 1)
        fine = hash3(np.floor(ax / g.cell), np.floor(g.Y / g.cell), np.floor(g.Z / g.cell), 2)
        col = col * (0.88 + 0.16 * clump + 0.06 * fine)[..., None]
    return d, np.clip(col, 0, 1), kind


def _kit(name, **P):
    KIT[name] = (lambda sp, g, vc, vk, P=P: kit(sp, g, P, vc, vk))


_kit("griffin", heads={"beastHead": "bird"}, hooked=True, tex="fur", wings="feathers", feet={"F": "talon", "B": "paw"})
_kit("spider", heads={"beastHead": "spider"}, tex="chitin", seg=0.1, limb_k=0.8, foot_taper=0.45, haunch=0)
_kit("scorpion", heads={"beastHead": "scorpion"}, tex="chitin", seg=0.12, body=(0.94, 0.8, 0.96), limb_k=0.8, foot_taper=0.5, haunch=0)


# ---------- the beasts of myth sculpted whole: the dragon and the hydra; and the great ape ----------
#
# (The user: the kit's dragon, hydra and gorilla did not look good enough, and the monsters should
# be bigger and more menacing.) Each over its own parts as the cats and the bears are: the trunk in
# its masses, the legs in their muscles down to clawed feet, a neck in a curve, a head in its bones
# and jaws with a row of teeth, heavy brows over eyes that glow, horns and spikes.

INF = 1e9


class _Sub:
    """The cells of a grid round a box (lo..hi, metres), a grid of their own (ell, cap and the rest
    take it as they take the whole): a head, a foot, a horn drawn where it is, not everywhere."""
    def __init__(self, g, lo, hi):
        n = np.array(g.shape)
        a = np.clip(np.floor((np.asarray(lo, float) - g.lo) / g.cell).astype(int), 0, n)
        b = np.clip(np.ceil((np.asarray(hi, float) - g.lo) / g.cell).astype(int) + 1, 0, n)
        self.sl = tuple(slice(int(a[i]), int(b[i])) for i in range(3))
        self.X, self.Y, self.Z = g.X[self.sl], g.Y[self.sl], g.Z[self.sl]
        self.cell = g.cell
        self.lo = g.lo + a * g.cell
        self.shape = self.X.shape


def _around(g, pts, pad):
    pts = np.array(pts, float)
    return _Sub(g, pts.min(0) - pad, pts.max(0) + pad)


def ell_o(g, c, R, r):
    """An ellipsoid turned as R is (its radii along R's columns)."""
    dx, dy, dz = g.X - c[0], g.Y - c[1], g.Z - c[2]
    x = (dx * R[0, 0] + dy * R[1, 0] + dz * R[2, 0]) / r[0]
    y = (dx * R[0, 1] + dy * R[1, 1] + dz * R[2, 1]) / r[1]
    z = (dx * R[0, 2] + dy * R[1, 2] + dz * R[2, 2]) / r[2]
    return (np.sqrt(x * x + y * y + z * z) - 1.0) * min(r)


class _Shape:
    """A beast's distance on the grid built up piece by piece, and its features (where its teeth,
    eyes, horns, claws... are: each the distance to the nearest of its kind)."""
    def __init__(self, g):
        self.g = g
        self.d = np.full(g.shape, INF)
        self.feat = {}

    def add(self, sh, k=0.0, sub=None):
        sl = sub.sl if sub is not None else (slice(None),) * 3
        self.d[sl] = smin(self.d[sl], sh, k) if k > 0 else np.minimum(self.d[sl], sh)

    def cut(self, sh, k=0.0, sub=None):
        sl = sub.sl if sub is not None else (slice(None),) * 3
        self.d[sl] = smax(self.d[sl], -sh, k) if k > 0 else np.maximum(self.d[sl], -sh)

    def mark(self, key, sh, sub=None):
        f = self.feat.get(key)
        if f is None:
            f = self.feat[key] = np.full(self.g.shape, INF, np.float32)
        sl = sub.sl if sub is not None else (slice(None),) * 3
        f[sl] = np.minimum(f[sl], sh)

    def on(self, key, thr):
        f = self.feat.get(key)
        if f is None:
            return np.zeros(self.g.shape, bool)
        return (f < thr) & (self.d < 0)


def _chain(g, pts, radii):
    """Capsules through points, the radius running from one to the next."""
    out = None
    for i in range(len(pts) - 1):
        c = cap(g, pts[i], pts[i + 1], radii[i], radii[i + 1])
        out = c if out is None else np.minimum(out, c)
    return out


def _clawed_foot(S, g, F, fwd, r, toes, claw_k=1.0, spread=0.62):
    """A clawed foot on the ground at F (its sole there), forward `fwd`: a pad, toes splayed from it
    and a hooked claw at the end of each (a dragon's, a hydra's)."""
    fwd = fwd / np.linalg.norm(fwd)
    up = np.array([0.0, 1.0, 0.0])
    side = np.cross(up, fwd)
    pts = [F + up * r * 0.6, F + fwd * r * 3.2, F - fwd * r * 1.5, F + side * r * 2.4, F - side * r * 2.4]
    sub = _around(g, pts, r * 1.6)
    pad = ell(sub, F + up * r * 0.55 + fwd * r * 0.2, (r * 1.15, r * 0.6, r * 1.25))
    S.add(pad, r * 0.3, sub)
    n = len(toes)
    for i, a in enumerate(toes):
        dv = fwd * math.cos(a) + side * math.sin(a)
        L = r * (1.7 if abs(a) < 0.5 else 1.35) if a < 2.0 else r * 0.9
        t0 = F + up * r * 0.45 + dv * r * 0.5
        t1 = F + up * r * 0.32 + dv * (r * 0.5 + L)
        S.add(cap(sub, t0, t1, r * 0.36, r * 0.26), r * 0.15, sub)
        cl = cap(sub, t1 - dv * r * 0.1 + up * r * 0.05, t1 + dv * r * 0.75 * claw_k - up * r * 0.28, r * 0.2, r * 0.03)
        S.add(cl, 0, sub)
        S.mark("claw", cl, sub)


def _wyrm_head(S, g, R, pos, half, P):
    """A dragon's (a hydra's) head in its box, forward its +z: the skull broad behind with the jaw's
    muscles under it, a long snout flat on top narrowing to the nostrils, the jaw hung open under it,
    a row of teeth along each, the fangs longest; heavy brows down over eyes set deep (they glow);
    horns swept back from the crown and spikes back from the cheeks."""
    hx, hy, hz = (float(v) for v in half)
    ax, up, f = R[:, 0], R[:, 1], R[:, 2]

    def L(x, y, z):
        return pos + ax * (x * hx) + up * (y * hy) + f * (z * hz)
    m = min(hx, hy)
    gape = P.get("gape", 0.16)
    # (all eight corners: a turned head's two opposite corners alone left the box short on one side,
    # and the hydra's outer heads were not each other's mirror)
    sub = _around(g, [L(x, y, z) for x in (-1.6, 1.6) for y in (-1.4, 1.9) for z in (-2.4, 1.5)], 0.05)
    # The skull and the cheeks.
    sk = ell_o(sub, L(0, 0.14, -0.42), R, (0.64 * hx, 0.52 * hy, 0.46 * hz))
    for s in (-1, 1):
        sk = smin(sk, ell_o(sub, L(s * 0.42, -0.06, -0.38), R, (0.36 * hx, 0.42 * hy, 0.38 * hz)), 0.06 * hz)
    # The snout, flat on top, narrowing and dropping a little to the nose.
    for zz, wx, wy in ((-0.1, 0.56, 0.36), (0.26, 0.48, 0.32), (0.58, 0.4, 0.28), (0.84, 0.31, 0.23)):
        sk = smin(sk, ell_o(sub, L(0, 0.1 - 0.12 * (zz + 0.1), zz), R, (wx * hx, wy * hy, 0.27 * hz)), 0.09 * hz)
    # The jaw, from its hinges under the cheeks to the chin, hung open; the throat between.
    chin = L(0, -0.46 - gape, 0.7)
    jaw = None
    for s in (-1, 1):
        j = cap(sub, L(s * 0.44, -0.3, -0.5), chin + ax * (s * 0.08 * hx), 0.21 * m, 0.12 * m)
        jaw = j if jaw is None else smin(jaw, j, 0.08 * m)
    jaw = smin(jaw, ell_o(sub, L(0, -0.42 - 0.4 * gape, -0.05), R, (0.3 * hx, 0.13 * hy, 0.5 * hz)), 0.06 * m)
    sk = smin(sk, jaw, 0.05 * m)
    # The mouth inside (dark, wet: a dragon's glowing with its fire), set in between the jaws.
    mouth = ell_o(sub, L(0, -0.3 - 0.5 * gape, 0.12), R, (0.26 * hx, 0.11 * hy, 0.62 * hz))
    sk = np.minimum(sk, mouth)
    S.mark("mouth", mouth, sub)
    # Teeth: down from the snout's edges, up from the jaw's; the fangs longest.
    nt = int(P.get("teeth", 7))
    for s in (-1, 1):
        for i in range(nt):
            t = i / (nt - 1)
            zz = -0.18 + 0.96 * t
            fang = i == nt - 2
            lt = (0.18 + (0.14 if fang else 0.0)) * hy
            a0 = L(s * (0.36 - 0.17 * t), -0.12 - 0.06 * t, zz)
            tooth = cap(sub, a0, a0 - up * lt + f * 0.02 * hz, max((0.07 if fang else 0.05) * m, (1.0 if fang else 0.75) * g.cell), 0.006)
            S.add(tooth, 0, sub)
            S.mark("tooth", tooth, sub)
            if i % 2 == 0 or fang:
                b0 = L(s * (0.33 - 0.22 * t), -0.36 - gape * (0.4 + 0.6 * t), zz - 0.05)
                tooth = cap(sub, b0, b0 + up * lt * 0.8 + f * 0.02 * hz, max(0.045 * m, 0.7 * g.cell), 0.006)
                S.add(tooth, 0, sub)
                S.mark("tooth", tooth, sub)
    # Brows: heavy ridges down to the front over the eyes, the eyes set in under them.
    for s in (-1, 1):
        ec = L(s * 0.5, 0.24, -0.12)
        er = 0.15 * m
        sk = smax(sk, -ell_o(sub, ec, R, (er * 1.3, er * 1.0, er * 1.35)), 0.01)
        eye = ell_o(sub, ec - ax * (s * er * 0.25), R, (er, er * 0.8, er * 1.1))
        sk = np.minimum(sk, eye)
        S.mark("eye", eye, sub)
        sk = smin(sk, cap(sub, L(s * 0.58, 0.52, -0.5), L(s * 0.36, 0.42, 0.06), 0.15 * m, 0.1 * m), 0.05 * m)
    # Nostrils at the tip of the snout.
    for s in (-1, 1):
        nst = ell_o(sub, L(s * 0.14, 0.06, 0.95), R, (0.045 * hx, 0.035 * hy, 0.05 * hz))
        sk = smax(sk, -nst, 0.01)
        S.mark("nostril", nst, sub)
    S.add(sk, P.get("join", 0.0), sub)
    # Horns swept back from the crown, curving up at their tips; spikes back from the cheeks.
    hk = P.get("horn_k", 1.0)
    if hk > 0:
        for s in (-1, 1):
            h0 = L(s * 0.28, 0.42, -0.6)
            h1 = L(s * 0.44, 0.7, -1.1)
            h2 = L(s * 0.52, 1.05, -1.55)
            hn = smin(cap(sub, h0, h1, 0.16 * m * hk, 0.1 * m * hk), cap(sub, h1, h2, 0.1 * m * hk, 0.012), 0.02 * m)
            S.add(hn, 0.03 * m, sub)
            S.mark("horn", hn, sub)
    for s in (-1, 1):
        for y0, z1, y1, k in ((-0.18, -1.05, -0.32, 1.0), (0.06, -1.2, 0.0, 0.85), (0.3, -1.1, 0.4, 0.7)):
            spk = cap(sub, L(s * 0.5, y0, -0.6), L(s * (0.86 + 0.1 * k), y1, z1), 0.13 * m * k, 0.01)
            S.add(spk, 0.02 * m, sub)
            S.mark("spike", spk, sub)
    return [L(s * 0.5, 0.24, -0.12) for s in (-1, 1)]


def _wing_full(S, g, J, s, c, Ls, Hc, thick):
    """A dragon's wing (_wing's), its bones and its membrane marked; a hooked claw at its wrist and
    at each finger's tip."""
    n = np.cross(s, c)
    n = n / max(np.linalg.norm(n), 1e-9)
    tip_pts = [J, J + s * Ls + c * 0.6 * Hc, J + s * 0.42 * Ls - c * 1.1 * Hc, J - c * Hc]
    sub = _around(g, tip_pts, Hc * 0.4)
    w = _wing(sub, J, s, c, Ls, Hc, thick, "membrane")
    S.add(w, 0.06, sub)
    # (the membrane: where the wing is thin)
    rx, ry, rz = sub.X - J[0], sub.Y - J[1], sub.Z - J[2]
    across = np.abs(rx * n[0] + ry * n[1] + rz * n[2])
    S.mark("membrane", np.where(across < thick * 1.4, w, INF), sub)
    wrist = J + s * 0.42 * Ls + c * 0.62 * Hc
    cl = cap(sub, wrist, wrist + c * 0.32 * Hc + n * 0.04 * Hc + s * 0.05 * Ls, 0.045 * Hc, 0.006)
    S.add(cl, 0.02, sub)
    S.mark("claw", cl, sub)
    tip = J + s * Ls + c * 0.5 * Hc
    cl = cap(sub, tip, tip + s * 0.08 * Ls + c * 0.08 * Hc, 0.03 * Hc, 0.004)
    S.add(cl, 0.02, sub)
    S.mark("claw", cl, sub)


def _scales(g, col, size, seed=3):
    """Scales over the colours: each a shade of its own, their edges darker."""
    ax = np.abs(g.X)
    cs = size
    pl = hash3(np.floor(ax / cs), np.floor(g.Y / cs + 0.5 * np.floor(g.Z / cs)), np.floor(g.Z / cs), seed)
    seam = (np.abs((ax / cs) % 1.0 - 0.5) > 0.4) | (np.abs((g.Z / cs) % 1.0 - 0.5) > 0.4)
    k = (0.88 + 0.22 * pl) * np.where(seam, 0.8, 1.0)
    return col * k[..., None]


def _spine_row(S, g, pts, ups, backs, hs, thick, key="spine"):
    """A row of blade-like spines standing up from points (each raked back), as thin as `thick`."""
    for p, u, b, h in zip(pts, ups, backs, hs):
        tip = p + u * h + b * h * 0.55
        sub = _around(g, [p - b * h * 0.6, tip, p + b * h * 0.4], h * 0.2 + thick)
        bl = cap(sub, p - u * h * 0.15, tip, h * 0.32, 0.008)
        side = np.cross(u, b)
        side = side / max(np.linalg.norm(side), 1e-9)
        slab = np.abs((sub.X - p[0]) * side[0] + (sub.Y - p[1]) * side[1] + (sub.Z - p[2]) * side[2]) - thick
        bl = smax(bl, slab, thick * 0.5)
        S.add(bl, thick * 0.6, sub)
        S.mark(key, bl, sub)


def _top_line(S, g, z, x=0.0, below=1e9):
    """The height of the beast's back over (x, z): its highest cell there (under `below`)."""
    ix = int(np.clip(round((x - g.lo[0]) / g.cell - 0.5), 0, g.shape[0] - 1))
    iz = int(np.clip(round((z - g.lo[2]) / g.cell - 0.5), 0, g.shape[2] - 1))
    ys = g.lo[1] + (np.arange(g.shape[1]) + 0.5) * g.cell
    col = np.where((S.d[ix, :, iz] < 0) & (ys < below))[0]
    if col.size == 0:
        return None
    return float(g.lo[1] + (col.max() + 0.5) * g.cell)


def dragon(sp, g):
    info = _part_info(sp)
    K = parts_of(sp)
    _, body, bh = K["beastBody"]
    W, H, Lz = (float(v) for v in bh)
    cy, zc = float(body[1]), float(body[2])
    ground = min(float(K[n][1][1] - K[n][2][1]) for n in K if n.startswith("leg") and n.endswith("Lo"))
    S = _Shape(g)
    # The trunk: a deep chest between the shoulders, the belly under it, the waist drawn in, broad
    # haunches; the withers high where the wings and the neck come out.
    S.add(ell(g, (0, cy - 0.1 * H, zc + 0.5 * Lz), (0.82 * W, 0.95 * H, 0.56 * Lz)))
    S.add(ell(g, (0, cy - 0.2 * H, zc - 0.05 * Lz), (0.68 * W, 0.78 * H, 0.62 * Lz)), 0.3)
    S.add(ell(g, (0, cy + 0.04 * H, zc - 0.56 * Lz), (0.7 * W, 0.7 * H, 0.42 * Lz)), 0.3)
    trunk = np.array(S.d, copy=True)
    S.add(ell(g, (0, cy + 0.42 * H, zc + 0.36 * Lz), (0.55 * W, 0.42 * H, 0.45 * Lz)), 0.25)
    for sx in (-1, 1):
        S.add(ell(g, (sx * 0.5 * W, cy + 0.38 * H, zc + 0.52 * Lz), (0.32 * W, 0.42 * H, 0.3 * Lz)), 0.18)
        S.add(ell(g, (sx * 0.56 * W, cy - 0.02 * H, zc - 0.6 * Lz), (0.38 * W, 0.62 * H, 0.36 * Lz)), 0.2)
    # The legs: a lion's in their muscles, the hind ones bent back at the hock, down to clawed feet.
    for fb in ("F", "B"):
        for side in ("L", "R"):
            up_n, lo_n = "leg%s%s" % (fb, side), "leg%s%sLo" % (fb, side)
            if up_n not in info or lo_n not in info:
                continue
            ja = info[up_n][3]
            x, zj = float(ja[0]), float(ja[2])
            sx = 1.0 if x > 0 else -1.0
            r = float(min(K[up_n][2][0], K[up_n][2][2]))   # (the upper leg's half width)
            if fb == "F":
                sh_ = np.array([x * 0.98, cy - 0.1 * H, zj - 0.06])
                el = np.array([x * 1.08, 0.95 + ground, zj - 0.1])
                wr = np.array([x * 1.0, ground + 0.34, zj + 0.12])
                ft = np.array([x * 1.0, ground, zj + 0.3])
                S.add(cap(g, sh_, el, r * 1.0, r * 0.7), 0.22)
                S.add(ell(g, (x * 1.06, el[1] + 0.62 * (sh_[1] - el[1]) - 0.1, zj + 0.02), (r * 0.82, r * 1.4, r * 0.92)), 0.2)
                S.add(cap(g, el, wr, r * 0.7, r * 0.48), 0.15)
                S.add(ell(g, (x * 1.05, el[1] - 0.2, zj - 0.04), (r * 0.66, r * 0.9, r * 0.72)), 0.12)
            else:
                hp_ = np.array([x * 0.96, cy - 0.05 * H, zj + 0.04])
                kn = np.array([x * 1.06, ground + 1.0, zj + 0.32])
                hk = np.array([x * 1.02, ground + 0.45, zj - 0.25])
                ft = np.array([x * 1.0, ground, zj + 0.14])
                S.add(ell(g, (x * 1.0, cy - 0.45 * H, zj + 0.06), (r * 1.08, r * 1.75, r * 1.4)), 0.25)
                S.add(cap(g, hp_, kn, r * 1.0, r * 0.72), 0.2)
                S.add(cap(g, kn, hk, r * 0.72, r * 0.46), 0.12)
                S.add(ell(g, (x * 1.03, kn[1] - 0.16, zj + 0.05), (r * 0.6, r * 0.85, r * 0.7)), 0.1)
                S.add(cap(g, hk, ft + np.array([0, 0.25, 0]), r * 0.46, r * 0.4), 0.1)
                wr = hk
            _clawed_foot(S, g, ft, np.array([sx * 0.12, 0.0, 1.0]), r * 0.55, tuple(sx * a for a in (-0.62, -0.2, 0.22, 0.64)) + (math.pi - sx * 0.5,), 1.2)
    # The neck: out of the chest, rising in a curve to the back of the head.
    a, b = _limb_ends(info, "neck")
    Rn = K["neck"][0]
    u = (b - a) / np.linalg.norm(b - a)
    thr = Rn[:, 2]
    ln = float(np.linalg.norm(b - a))
    rn = float(K["neck"][2][0])
    # (arched: its crest bowed up between the withers and the head)
    npts = [a - u * 0.35, a + u * 0.33 * ln - thr * 0.12, a + u * 0.68 * ln - thr * 0.14, b + u * 0.02]
    nrad = [rn * 1.45, rn * 1.15, rn * 0.95, rn * 0.8]
    neck = _chain(g, npts, nrad)
    S.add(neck, 0.3)
    # The head.
    Rh, hp, hh = K["beastHead"]
    S.feat["_eyes"] = _wyrm_head(S, g, Rh, hp, hh, {"gape": 0.42, "teeth": 9, "horn_k": 0.0, "join": 0.18})
    # Its horns, along their own parts: thick at the crown, swept back, curving up at their tips.
    for n in ("hornL", "hornR"):
        if n not in info:
            continue
        h0, h1 = _limb_ends(info, n)
        mid = h0 + (h1 - h0) * 0.55 + np.array([0, -0.1, 0])
        tip = h1 + np.array([0, 0.3, -0.12])
        rh = float(min(K[n][2][0], K[n][2][2]))
        sub = _around(g, [h0, tip], rh * 1.5)
        hn = smin(cap(sub, h0 - (h1 - h0) * 0.15, mid, rh * 0.8, rh * 0.5), cap(sub, mid, tip, rh * 0.5, 0.012), 0.03)
        S.add(hn, 0.06, sub)
        S.mark("horn", hn, sub)
    # The tail: thick from the hips, tapering to a spade.
    ta, tb = _limb_ends(info, "tail")
    fa, fb_ = _limb_ends(info, "tailFin") if "tailFin" in info else (tb, tb)
    tu = (tb - ta) / np.linalg.norm(tb - ta)
    rt = float(K["tail"][2][0])
    tpts = [ta - tu * 0.6, ta + (tb - ta) * 0.3 + np.array([0, 0.06, 0]), ta + (tb - ta) * 0.7 - np.array([0, 0.04, 0]), tb, fb_]
    trad = [rt * 1.3, rt * 0.9, rt * 0.58, rt * 0.3, rt * 0.14]
    S.add(_chain(g, tpts, trad), 0.3)
    if "tailFin" in K:
        Rf, fp, fh = K["tailFin"]
        sub = _around(g, [fp - np.array([fh[0], 0.1, fh[2] * 1.2]), fp + np.array([fh[0], 0.1, fh[2] * 1.2])], 0.05)
        dz = (sub.Z - fp[2]) * 0.95
        spade = (np.abs(sub.X) / (fh[0] * 1.0) + np.abs(dz) / (fh[2] * 1.05) - 1.0) * min(fh[0], fh[2]) * 0.7
        spade = smax(spade, np.abs(sub.Y - fp[1]) - 0.05, 0.02)
        S.add(spade, 0.04, sub)
        S.mark("spine", spade, sub)
    # The wings.
    for n in ("wingL", "wingR"):
        if n not in info:
            continue
        R, pos, half, j, s_, par, kids = info[n]
        th = int(np.argmin(half))
        spn = int(np.argmax(half))
        chd = 3 - spn - th
        sv = pos - j
        sv = sv - R[:, chd] * float(sv @ R[:, chd])
        sv = sv / max(np.linalg.norm(sv), 1e-9)
        cv = R[:, chd] if float(R[:, chd][2]) >= 0 else -R[:, chd]
        Ls = float(np.linalg.norm(pos - j)) + float(half[spn])
        _wing_full(S, g, j, sv, cv, Ls * 1.04, float(half[chd]) * 1.05, max(g.cell * 0.6, float(half[th]) * 0.4))
    # The spines: blades down the back from the withers, smaller down the tail, and up the neck.
    zs = np.linspace(zc + 0.62 * Lz, zc - 0.9 * Lz, 9)
    pts, ups, backs, hs = [], [], [], []
    for i, z in enumerate(zs):
        y = _top_line(S, g, z, below=cy + H + 0.25)
        if y is None:
            continue
        pts.append(np.array([0.0, y - 0.06, z]))
        ups.append(np.array([0.0, 1.0, 0.0]))
        backs.append(np.array([0.0, 0.0, -1.0]))
        hs.append(0.42 * (1.0 - 0.3 * abs(i - 3) / 6.0))
    for t in np.linspace(0.08, 0.85, 7):
        p = ta + (tb - ta) * t
        y = _top_line(S, g, float(p[2]))
        if y is None:
            continue
        pts.append(np.array([0.0, y - 0.04, p[2]]))
        ups.append(np.array([0.0, 1.0, 0.0]))
        backs.append(np.array([0.0, 0.0, -1.0]))
        hs.append(0.3 * (1.0 - 0.75 * t))
    back_n = -thr
    for t in np.linspace(0.1, 0.86, 6):
        q = a + u * t * ln - thr * (0.14 * math.sin(t * math.pi))
        r_here = rn * (1.25 - 0.5 * t)
        pts.append(q + back_n * r_here * 0.8)
        ups.append(back_n)
        backs.append(-u)
        hs.append(0.26 * (1.0 - 0.35 * t))
    _spine_row(S, g, pts, ups, backs, hs, 0.045)
    d = S.d
    occ = d < 0
    thr_c = 0.4 * g.cell
    # Colours: a deep red in scales, darker over the back; the belly in pale gold plates across;
    # the membranes dark; horns, claws, spines and teeth.
    red = np.array([0.6, 0.07, 0.05])
    dark = np.array([0.3, 0.03, 0.03])
    gold = np.array([0.86, 0.64, 0.34])
    col = np.zeros(g.shape + (3,))
    col[:] = red
    hi = np.clip((g.Y - (cy + 0.2 * H)) / (0.9 * H), 0, 1)
    col = col * (1 - hi[..., None] * 0.55) + dark * (hi[..., None] * 0.55)
    kind = np.full(g.shape, SCALE_KIND, np.uint8)
    # (the belly: under the trunk and the tail, the throat's side of the neck, in plates)
    belly = (trunk < 0.6 * g.cell) & (g.Y < cy - 0.3 * H) & (np.abs(g.X) < 0.5 * W)
    rx, ry, rz = g.X - a[0], g.Y - a[1], g.Z - a[2]
    tt = np.clip((rx * u[0] + ry * u[1] + rz * u[2]) / ln, -0.3, 1.05)
    wx, wy, wz = rx - u[0] * tt * ln, ry - u[1] * tt * ln, rz - u[2] * tt * ln
    wn = np.sqrt(wx * wx + wy * wy + wz * wz) + 1e-6
    throat = ((wx * thr[0] + wy * thr[1] + wz * thr[2]) / wn > 0.62) & (tt > -0.1) & (tt < 0.9) & (neck < 0.6 * g.cell)
    under_tail = (g.Z < zc - 0.9 * Lz) & (g.Y < np.interp(-g.Z, [-float(ta[2]), -float(tb[2])], [float(ta[1]), float(tb[1])]) - 0.12)
    bel = (belly | throat | under_tail) & occ
    col = _scales(g, col, 0.085)
    plates = np.abs(((g.Z + 0.6 * g.Y) / 0.13) % 1.0 - 0.5) > 0.42
    col[bel] = gold * np.where(plates[bel], 0.72, 1.0)[:, None]
    if "membrane" in S.feat:
        mm = S.on("membrane", thr_c)
        vein = vnoise(np.abs(g.X), g.Y, g.Z, 0.12, 5)
        col[mm] = np.array([0.32, 0.05, 0.06]) * (0.85 + 0.3 * vein[mm])[:, None]
    sp_k = S.on("spine", thr_c)
    col[sp_k] = np.array([0.22, 0.03, 0.03])
    sk_k = S.on("spike", thr_c)
    col[sk_k] = np.array([0.42, 0.36, 0.28])
    kind[sk_k] = BONE
    hk = S.on("horn", thr_c)
    if hk.any() and "hornL" in info:
        # (ivory at the crown, darkening to black at the tips)
        h0, h1 = _limb_ends(info, "hornL")
        hu = (h1 - h0) / np.linalg.norm(h1 - h0)
        t_h = np.clip(((np.abs(g.X) - abs(h0[0])) * abs(hu[0]) + (g.Y - h0[1]) * hu[1] + (g.Z - h0[2]) * hu[2]) / float(np.linalg.norm(h1 - h0)), 0, 1)
        ivory, black = np.array([0.84, 0.78, 0.64]), np.array([0.1, 0.08, 0.07])
        tk = t_h[hk][:, None] ** 1.5
        col[hk] = ivory * (1 - tk) + black * tk
        kind[hk] = BONE
    ck = S.on("claw", thr_c)
    col[ck] = np.array([0.06, 0.05, 0.05])
    kind[ck] = BONE
    th_k = S.on("tooth", thr_c)
    col[th_k] = np.array([0.93, 0.9, 0.8])
    kind[th_k] = BONE
    mo = S.on("mouth", thr_c) & ~th_k
    col[mo] = np.array([1.0, 0.42, 0.08])
    kind[mo] = GLOW_KIND
    ns = (S.feat.get("nostril", np.full(g.shape, INF)) < thr_c * 1.5) & occ & ~th_k
    col[ns] = np.array([0.16, 0.03, 0.03])
    kind[ns] = 7
    ey = S.on("eye", thr_c)
    col[ey] = np.array([1.0, 0.78, 0.12])
    kind[ey] = GLOW_KIND
    _slits(S, g, ey, Rh, hh, col)
    return d, np.clip(col, 0, 1), kind


def _slits(S, g, ey, R, half, col):
    """A slit of a pupil down the middle of each glowing eye (seen from the side)."""
    f = R[:, 2]
    up = R[:, 1]
    for c in S.feat.get("_eyes", []):
        dz = (g.X - c[0]) * f[0] + (g.Y - c[1]) * f[1] + (g.Z - c[2]) * f[2]
        slit = ey & (np.abs(dz) < 0.32 * g.cell + 0.012) & (np.abs((g.X - c[0]) * up[0] + (g.Y - c[1]) * up[1] + (g.Z - c[2]) * up[2]) < float(min(half[0], half[1])) * 0.11)
        col[slit] = np.array([0.08, 0.02, 0.0])


SCULPTS["dragon"] = dragon


def _belly_plates(g, col, mask, gold, dark_k=0.72, step=0.12):
    """Plates across the belly (and the throat): pale gold, the seams between them darker."""
    plates = np.abs(((g.Z + 0.6 * g.Y) / step) % 1.0 - 0.5) > 0.42
    col[mask] = gold * np.where(plates[mask], dark_k, 1.0)[:, None]


def _throat_mask(g, a, b, thr, neck_d, rn):
    """The throat's side of a neck from a to b (`thr` the way it faces)."""
    u = b - a
    ln = float(np.linalg.norm(u))
    u = u / ln
    rx, ry, rz = g.X - a[0], g.Y - a[1], g.Z - a[2]
    tt = np.clip((rx * u[0] + ry * u[1] + rz * u[2]) / ln, -0.3, 1.05)
    wx, wy, wz = rx - u[0] * tt * ln, ry - u[1] * tt * ln, rz - u[2] * tt * ln
    wn = np.sqrt(wx * wx + wy * wy + wz * wz) + 1e-6
    return ((wx * thr[0] + wy * thr[1] + wz * thr[2]) / wn > 0.74) & (tt > -0.1) & (tt < 0.92) & (neck_d < 0.6 * g.cell)


def hydra(sp, g):
    info = _part_info(sp)
    K = parts_of(sp)
    _, body, bh = K["beastBody"]
    W, H, Lz = (float(v) for v in bh)
    cy, zc = float(body[1]), float(body[2])
    ground = min(float(K[n][1][1] - K[n][2][1]) for n in K if n.startswith("leg") and n.endswith("Lo"))
    S = _Shape(g)
    # The trunk: low and heavy, broadest at the shoulders where the necks come out of it, the hips
    # narrower, the belly slung low.
    S.add(ell(g, (0, cy - 0.08 * H, zc - 0.05 * Lz), (0.84 * W, 0.86 * H, 0.92 * Lz)))
    S.add(ell(g, (0, cy + 0.05 * H, zc + 0.48 * Lz), (0.92 * W, 0.84 * H, 0.52 * Lz)), 0.25)
    S.add(ell(g, (0, cy + 0.02 * H, zc - 0.62 * Lz), (0.72 * W, 0.78 * H, 0.44 * Lz)), 0.25)
    trunk = np.array(S.d, copy=True)
    # The legs: a crocodile's, sprawled out from the sides to clawed feet.
    for fb in ("F", "B"):
        for side in ("L", "R"):
            up_n, lo_n = "leg%s%s" % (fb, side), "leg%s%sLo" % (fb, side)
            if up_n not in info or lo_n not in info:
                continue
            ja = info[up_n][3]
            x, zj = float(ja[0]), float(ja[2])
            sx = 1.0 if x > 0 else -1.0
            r = float(min(K[up_n][2][0], K[up_n][2][2])) * 0.9
            sh_ = np.array([x * 0.85, cy - 0.15 * H, zj])
            el = np.array([x * 1.42, ground + 0.48, zj + 0.04])
            wr = np.array([x * 1.3, ground + 0.2, zj + 0.12])
            ft = np.array([x * 1.3, ground, zj + 0.2])
            big = 1.15 if fb == "B" else 1.0
            S.add(ell(g, (x * 1.0, cy - 0.3 * H, zj), (r * 1.3 * big, r * 1.2 * big, r * 1.35 * big)), 0.16)
            S.add(cap(g, sh_, el, r * 1.0 * big, r * 0.78), 0.14)
            S.add(cap(g, el, wr, r * 0.78, r * 0.6), 0.1)
            _clawed_foot(S, g, ft, np.array([sx * 0.25, 0.0, 1.0]), r * 0.5, tuple(sx * a for a in (-0.75, -0.28, 0.2, 0.66)) + (math.pi - sx * 0.6,), 1.15)
    # The necks: thick at their roots in the shoulders, arched, up to the heads.
    necks = []
    for nk in sorted(n for n in K if n.startswith("neck")):
        a, b = _limb_ends(info, nk)
        Rn = K[nk][0]
        u = (b - a) / np.linalg.norm(b - a)
        thr = Rn[:, 2]
        ln = float(np.linalg.norm(b - a))
        rn = float(K[nk][2][0])
        npts = [a - u * 0.3, a + u * 0.33 * ln - thr * 0.08, a + u * 0.68 * ln - thr * 0.1, b + u * 0.02]
        nrad = [rn * 1.75, rn * 1.3, rn * 1.08, rn * 0.98]
        nd = _chain(g, npts, nrad)
        S.add(nd, 0.2)
        necks.append((nk, a, b, u, thr, ln, rn, nd))
    # The heads, each at the end of its neck.
    eyes = []
    for nk, a, b, u, thr, ln, rn, nd in necks:
        hd = info[nk][6][0] if info[nk][6] else None
        if hd is None:
            continue
        Rh, hp, hh = K[hd]
        for e in _wyrm_head(S, g, Rh, hp, hh, {"gape": 0.36, "teeth": 7, "horn_k": 0.75, "join": 0.08}):
            eyes.append((e, Rh, hh))
    # The tail: thick from the hips, tapering to a point.
    ta, tb = _limb_ends(info, "tail")
    tu = (tb - ta) / np.linalg.norm(tb - ta)
    rt = float(K["tail"][2][0])
    tpts = [ta - tu * 0.5, ta + (tb - ta) * 0.35 + np.array([0, 0.03, 0]), ta + (tb - ta) * 0.75 - np.array([0, 0.05, 0]), tb + tu * 0.4 - np.array([0, 0.12, 0])]
    trad = [rt * 1.35, rt * 0.95, rt * 0.55, rt * 0.08]
    S.add(_chain(g, tpts, trad), 0.25)
    # Spines: a ridge of them down the back to the tail's end, and down the back of each neck.
    pts, ups, backs, hs = [], [], [], []
    zs = np.linspace(zc + 0.55 * Lz, float(tb[2]) + 0.2, 14)
    for i, z in enumerate(zs):
        y = _top_line(S, g, z, below=cy + H + 0.2)
        if y is None:
            continue
        t = i / (len(zs) - 1)
        pts.append(np.array([0.0, y - 0.04, z]))
        ups.append(np.array([0.0, 1.0, 0.0]))
        backs.append(np.array([0.0, 0.0, -1.0]))
        hs.append(0.3 * (1.0 - 0.7 * t) * (0.7 if i == 0 else 1.0))
    for nk, a, b, u, thr, ln, rn, nd in necks:
        for t in np.linspace(0.22, 0.86, 5):
            q = a + u * t * ln - thr * (0.1 * math.sin(t * math.pi))
            r_here = rn * (1.6 - 0.65 * t)
            pts.append(q - thr * r_here * 0.85)
            ups.append(-thr)
            backs.append(-u)
            hs.append(0.15 * (1.0 - 0.3 * t))
    _spine_row(S, g, pts, ups, backs, hs, 0.035)
    d = S.d
    occ = d < 0
    thr_c = 0.4 * g.cell
    # Colours: a deep green in scales, darker over the back with dark bands across it; the belly and
    # the throats pale in plates; bone, horn, claws, teeth; the eyes glowing.
    green = np.array([0.14, 0.33, 0.17])
    dark = np.array([0.05, 0.14, 0.07])
    gold = np.array([0.82, 0.76, 0.46])
    col = np.zeros(g.shape + (3,))
    col[:] = green
    hi = np.clip((g.Y - (cy + 0.1 * H)) / (1.0 * H), 0, 1)
    col = col * (1 - hi[..., None] * 0.6) + dark * (hi[..., None] * 0.6)
    bands = (np.sin(g.Z * 7.0 + vnoise(np.abs(g.X), g.Y, g.Z, 0.25, 9) * 3.0) > 0.55) & (g.Y > cy) & (trunk < 0.3)
    col[bands] = col[bands] * 0.55
    col = _scales(g, col, 0.07, 5)
    kind = np.full(g.shape, SCALE_KIND, np.uint8)
    belly = (trunk < 0.6 * g.cell) & (g.Y < cy - 0.25 * H) & (np.abs(g.X) < 0.55 * W)
    under_tail = (g.Z < zc - 0.8 * Lz) & (g.Y < float(ta[1]) - 0.18) & occ & (np.abs(g.X) < 0.3)
    bel = belly | under_tail
    for nk, a, b, u, thr, ln, rn, nd in necks:
        bel |= _throat_mask(g, a, b, thr, nd, rn)
    bel &= occ
    _belly_plates(g, col, bel, gold, 0.75, 0.1)
    sp_k = S.on("spine", thr_c)
    col[sp_k] = np.array([0.07, 0.12, 0.06])
    sk_k = S.on("spike", thr_c)
    col[sk_k] = np.array([0.1, 0.14, 0.08])
    hk = S.on("horn", thr_c)
    col[hk] = np.array([0.5, 0.47, 0.36])
    kind[hk] = BONE
    ck = S.on("claw", thr_c)
    col[ck] = np.array([0.06, 0.05, 0.05])
    kind[ck] = BONE
    th_k = S.on("tooth", thr_c)
    col[th_k] = np.array([0.93, 0.9, 0.8])
    kind[th_k] = BONE
    mo = S.on("mouth", thr_c) & ~th_k
    col[mo] = np.array([0.42, 0.05, 0.06])
    kind[mo] = 7
    ns = (S.feat.get("nostril", np.full(g.shape, INF)) < thr_c * 1.5) & occ & ~th_k
    col[ns] = np.array([0.03, 0.06, 0.03])
    kind[ns] = 7
    ey = S.on("eye", thr_c)
    col[ey] = np.array([1.0, 0.86, 0.15])
    kind[ey] = GLOW_KIND
    for e, Rh, hh in eyes:
        S.feat["_eyes"] = [e]
        _slits(S, g, ey, Rh, hh, col)
    return d, np.clip(col, 0, 1), kind


SCULPTS["hydra"] = hydra


def gorilla(sp, g):
    """A silverback on its knuckles: the shoulders a mountain over the arms, the head low between
    them under the hump of its neck, the skull peaked by its crest, a shelf of brow over eyes set
    deep, a black face; arms longer and thicker than its legs down to the knuckles it walks on, the
    belly big, short bowed legs; black, the saddle of its back silver."""
    info = _part_info(sp)
    K = parts_of(sp)
    _, body, bh = K["beastBody"]
    W, H, Lz = (float(v) for v in bh)
    cy, zc = float(body[1]), float(body[2])
    _, hp, hh = K["beastHead"]
    h = float(min(hh))
    ground = float(K["legFLLo"][1][1] - K["legFLLo"][2][1])
    S = _Shape(g)
    jL = info["legFL"][3]
    sxw = abs(float(jL[0]))
    top = float(jL[1])
    # The trunk: long and deep, sloping from the shoulders down to the rump over the legs; the belly
    # hanging under it, the chest broad between the arms; the shoulders sloping down from the head
    # (the neck's muscle) to the round of the upper arms; the rump low.
    hipL = info["legBL"][3]
    rump = np.array([0.0, float(hipL[1]) + 0.05, float(hipL[2]) - 0.32])
    withers = np.array([0.0, top - 0.2, float(jL[2]) - 0.2])
    u = (withers - rump) / np.linalg.norm(withers - rump)
    side = np.array([1.0, 0.0, 0.0])
    third = np.cross(side, u)
    Rt = np.stack([side, u, third], 1)
    half_len = float(np.linalg.norm(withers - rump)) * 0.5
    S.add(ell_o(g, (rump + withers) * 0.5, Rt, (0.8 * sxw, half_len + 0.42, 0.62)))
    S.add(ell(g, (0, float(hipL[1]) + 0.18, zc + 0.12), (0.62, 0.56, 0.62)), 0.3)   # the belly
    S.add(ell(g, (0, top - 0.36, float(jL[2]) - 0.12), (0.76 * sxw, 0.44, 0.42)), 0.3)   # the chest
    S.add(ell(g, (0, float(hipL[1]) + 0.02, float(hipL[2]) - 0.38), (0.6, 0.5, 0.44)), 0.25)   # the rump
    for sx in (-1, 1):
        S.add(ell(g, (sx * 1.02 * sxw, top - 0.18, float(jL[2]) - 0.04), (0.42, 0.44, 0.42)), 0.22)   # the round of the shoulder
        S.add(cap(g, (0, float(hp[1]) - 0.2, float(hp[2]) - 0.5), (sx * 0.78 * sxw, top - 0.06, float(jL[2]) - 0.08), 0.34, 0.3), 0.25)   # the neck's muscle down to it
    S.add(ell(g, (0, top - 0.02, float(jL[2]) - 0.42), (0.62 * sxw, 0.34, 0.5)), 0.3)   # the hump behind the head
    trunk = np.array(S.d, copy=True)
    # The arms: from the shoulders down past the elbows to the fists, the forearms as thick as the
    # upper arms; the hands knuckled under on the ground.
    for side in ("L", "R"):
        up_n, lo_n = "legF%s" % side, "legF%sLo" % side
        sh_ = info[up_n][3]
        el = info[lo_n][3]
        x = float(sh_[0])
        sx = 1.0 if x > 0 else -1.0
        r = float(K[up_n][2][0]) * 0.86
        sh2 = np.array([x * 0.96, float(sh_[1]) - 0.06, float(sh_[2]) - 0.03])
        el2 = np.array([x * 1.05, float(el[1]), float(el[2]) + 0.05])
        wr = np.array([x * 1.02, ground + 0.3, float(el[2]) + 0.1])
        sh2 = sh2 + np.array([x * 0.1, 0.0, 0.0])
        S.add(cap(g, sh2, el2, r * 1.0, r * 0.76), 0.2)
        S.add(ell(g, (x * 1.08, (sh2[1] + el2[1]) * 0.5 + 0.05, el2[2] + 0.02), (r * 0.92, r * 1.35, r * 1.0)), 0.12)
        S.add(cap(g, el2, wr, r * 0.86, r * 0.6), 0.12)
        S.add(ell(g, (x * 1.06, el2[1] - 0.28, el2[2] - 0.01), (r * 0.95, r * 1.15, r * 0.95)), 0.1)
        fist_c = np.array([x * 1.02, ground + 0.15, wr[2] + 0.1])
        sub = _around(g, [fist_c - 0.35, fist_c + 0.35], 0.05)
        fist = ell(sub, fist_c, (r * 0.78, r * 0.48, r * 0.76))
        for i in range(4):
            kc = np.array([x * 1.02 + (i - 1.5) * r * 0.36, ground + 0.07, fist_c[2] + r * 0.52])
            fist = smin(fist, ell(sub, kc, (r * 0.2, r * 0.2, r * 0.22)), 0.03)
        th = cap(sub, fist_c + np.array([-sx * r * 0.55, 0.04, r * 0.2]), fist_c + np.array([-sx * r * 0.62, -0.06, r * 0.5]), r * 0.17, r * 0.13)
        fist = smin(fist, th, 0.03)
        S.add(fist, 0.1, sub)
        S.mark("hand", fist, sub)
    # The legs: short, bowed, folded under the rump; broad flat feet.
    for side in ("L", "R"):
        up_n, lo_n = "legB%s" % side, "legB%sLo" % side
        hip = info[up_n][3]
        kn = info[lo_n][3]
        an = _limb_ends(info, lo_n)[1]
        x = float(hip[0])
        sx = 1.0 if x > 0 else -1.0
        r = float(K[up_n][2][0]) * 0.86
        S.add(cap(g, hip + np.array([x * 0.1, 0.08, -0.05]), kn + np.array([x * 0.12, 0, 0]), r * 1.0, r * 0.74), 0.22)
        S.add(ell(g, (hip + kn) * 0.5 + np.array([x * 0.1, 0.04, 0.0]), (r * 0.95, r * 0.8, r * 1.1)), 0.15)
        S.add(cap(g, kn + np.array([x * 0.12, 0, 0]), an + np.array([x * 0.06, 0.12, 0.02]), r * 0.72, r * 0.5), 0.15)
        foot_c = np.array([float(an[0]) * 1.08, ground + 0.08, float(an[2]) + 0.24])
        sub = _around(g, [foot_c - 0.45, foot_c + 0.45], 0.05)
        ft = ell(sub, foot_c, (r * 0.55, r * 0.24, r * 0.95))
        for i in range(4):
            tc = np.array([foot_c[0] + sx * (i - 1.0) * r * 0.2, ground + 0.05, foot_c[2] + r * 0.88])
            ft = smin(ft, ell(sub, tc, (r * 0.12, r * 0.12, r * 0.16)), 0.02)
        bt = cap(sub, foot_c + np.array([-sx * r * 0.4, 0.0, r * 0.4]), foot_c + np.array([-sx * r * 0.62, -0.02, r * 0.8]), r * 0.16, r * 0.13)
        ft = smin(ft, bt, 0.03)
        S.add(ft, 0.12, sub)
        S.mark("sole", ft, sub)
    # The fur: in clumps over all of it (long on the arms and the back), not on the face.
    clump = vnoise(np.abs(g.X), g.Y, g.Z, 0.09, 17)
    S.d = S.d - 0.022 * (clump - 0.45)
    # The head: a silverback's, low between its shoulders. The crown peaked by the crest along the
    # skull; a shelf of brow straight across over small deep-set eyes; the face bare and black under
    # it, the nose broad and flat with flared nostrils, the muzzle thrust forward, the mouth shut in
    # a hard line; the cheeks and the jowls furred; small ears close to the head.
    sub = _around(g, [hp - h * 1.4, hp + h * 1.4], 0.05)

    def P(x, y, z):
        return hp + np.array([x, y, z]) * h
    hd = ell(sub, P(0, 0.04, -0.12), (0.74 * h, 0.7 * h, 0.74 * h))
    hd = smin(hd, ell(sub, P(0, 0.46, -0.22), (0.26 * h, 0.4 * h, 0.6 * h)), 0.18 * h)   # the crest
    for sx in (-1, 1):
        hd = smin(hd, cap(sub, P(sx * 0.5, 0.18, 0.52), P(0, 0.22, 0.64), 0.16 * h, 0.15 * h), 0.06 * h)   # the brow
        hd = smin(hd, ell(sub, P(sx * 0.46, -0.24, 0.28), (0.3 * h, 0.34 * h, 0.32 * h)), 0.08 * h)   # the cheeks
        hd = smin(hd, ell(sub, P(sx * 0.76, 0.0, -0.12), (0.08 * h, 0.14 * h, 0.12 * h)), 0.04 * h)   # the ears
    hd = smin(hd, ell(sub, P(0, -0.16, 0.48), (0.54 * h, 0.48 * h, 0.4 * h)), 0.1 * h)   # the face
    hd = smin(hd, ell(sub, P(0, -0.44, 0.66), (0.46 * h, 0.3 * h, 0.36 * h)), 0.1 * h)   # the muzzle
    hd = smin(hd, ell(sub, P(0, -0.68, 0.6), (0.34 * h, 0.18 * h, 0.3 * h)), 0.08 * h)   # the chin
    hd = smin(hd, cap(sub, P(0, 0.12, 0.78), P(0, -0.04, 0.9), 0.08 * h, 0.1 * h), 0.04 * h)   # the bridge of the nose
    hd = smin(hd, ell(sub, P(0, -0.12, 0.88), (0.3 * h, 0.17 * h, 0.13 * h)), 0.04 * h)   # the nose
    for sx in (-1, 1):
        hd = smax(hd, -ell(sub, P(sx * 0.12, -0.17, 0.99), (0.08 * h, 0.065 * h, 0.08 * h)), 0.01)   # the nostrils
    hd = smax(hd, -ell(sub, P(0, -0.52, 1.0), (0.3 * h, 0.028 * h + 0.3 * g.cell, 0.1 * h)), 0.005)   # the mouth, shut
    eyes = []
    for sx in (-1, 1):
        ec = P(sx * 0.25, 0.05, 0.66)
        hd = smax(hd, -ell(sub, ec, (0.13 * h, 0.1 * h, 0.12 * h)), 0.01)
        eye = ell(sub, ec - np.array([0, 0, 0.03 * h]), (0.075 * h, 0.065 * h, 0.07 * h))
        hd = np.minimum(hd, eye)
        S.mark("eye", eye, sub)
        eyes.append(ec)
    S.add(hd, 0.22 * h, sub)
    d = S.d
    occ = d < 0
    thr_c = 0.4 * g.cell
    # Colours: black-brown fur in clumps, the tips lighter; the saddle of the back silver, the crown
    # a rusty brown; the face, the hands and the soles bare black skin, glossy; the eyes dark brown.
    fur = np.array([0.085, 0.078, 0.082])
    silver = np.array([0.56, 0.56, 0.58])
    col = np.zeros(g.shape + (3,))
    fine = hash3(np.floor(np.abs(g.X) / g.cell), np.floor(g.Y / g.cell), np.floor(g.Z / g.cell), 8)
    col[:] = fur
    col = col * (0.7 + 0.6 * clump[..., None] + 0.25 * fine[..., None])
    behind = np.clip((float(jL[2]) - 0.45 - g.Z) / 0.4, 0, 1)
    mid_y = rump[1] + (g.Z - rump[2]) * (withers[1] - rump[1]) / (withers[2] - rump[2])
    saddle = np.clip((g.Y - mid_y + 0.1) / 0.45, 0, 1) * behind * (trunk < 0.16) * np.clip((0.8 * sxw - np.abs(g.X)) / 0.35, 0, 1)
    streak = 0.7 + 0.5 * vnoise(np.abs(g.X), g.Y * 0.4, g.Z, 0.05, 23)
    sv = saddle[..., None] * 0.7
    col = col * (1 - sv) + (silver * streak[..., None]) * sv
    kind = np.full(g.shape, FUR, np.uint8)
    # (grey-black, a shade above the fur: the face, the chest and the hands stand out of the coat as
    # they do on the animal, glossy)
    skin = np.array([0.2, 0.19, 0.2])
    face = (np.abs(g.X - hp[0]) < 0.42 * h) & (g.Y < hp[1] + 0.24 * h) & (g.Y > hp[1] - 0.86 * h) & (g.Z > hp[2] + 0.5 * h) & (np.abs(g.X - hp[0]) < 0.42 * h - np.clip(hp[1] - 0.5 * h - g.Y, 0, None) * 0.4)
    pecs = np.minimum(ell(g, (-0.24 * sxw, top - 0.52, float(jL[2]) + 0.18), (0.3 * sxw, 0.17, 0.3)), ell(g, (0.24 * sxw, top - 0.52, float(jL[2]) + 0.18), (0.3 * sxw, 0.17, 0.3)))
    chest = (trunk < 0.6 * g.cell) & (pecs < 0.0) & (g.Z > float(jL[2]) - 0.1)
    bare = (face | chest | S.on("hand", thr_c) & (g.Y < ground + 0.16) | S.on("sole", thr_c) & (g.Y < ground + 0.06)) & occ
    col[bare] = skin * (0.85 + 0.35 * fine[bare])[:, None]
    col[chest & occ] = col[chest & occ] * 0.7
    kind[bare] = 7
    ey = S.on("eye", thr_c)
    col[ey] = np.array([0.3, 0.16, 0.07])
    kind[ey] = 7
    for ec in eyes:
        pupil = ey & (np.abs(g.X - ec[0]) < 0.03 * h + 0.3 * g.cell) & (np.abs(g.Y - ec[1]) < 0.03 * h + 0.3 * g.cell)
        col[pupil] = np.array([0.02, 0.01, 0.01])
    return d, np.clip(col, 0, 1), kind


SCULPTS["gorilla"] = gorilla


# ---------- the crocodile, the basilisk, Cerberus, the chimera and the manticore, sculpted whole ----------
#
# (The user: the kit's manticore, Cerberus, basilisk and chimera looked twisted and not whole, the
# crocodile odd and too small.) Each over its own parts as the dragon is, whole: a body in its
# masses, its head in its bones and jaws, its own hide.

def _croc_head(S, g, R, pos, half):
    """A crocodile's head in its box, forward its +z: the skull broad and flat behind with the jaw's
    muscles, a long snout narrowing to a swollen tip where the nostrils sit on a knob; the eyes on
    knobs on top at the back; the jaws shut along a line that rises to the front, the teeth showing
    over it from both jaws; the hide of the skull ridged. Returns the eyes' middles."""
    hx, hy, hz = (float(v) for v in half)
    ax, up, f = R[:, 0], R[:, 1], R[:, 2]

    def L(x, y, z):
        return pos + ax * (x * hx) + up * (y * hy) + f * (z * hz)
    sub = _around(g, [L(x, y, z) for x in (-1.3, 1.3) for y in (-1.4, 1.5) for z in (-1.4, 1.2)], 0.05)
    m = min(hx, hy)
    # The skull: broad and flat, the jaw's muscles bulging at its back corners.
    sk = ell_o(sub, L(0, 0.02, -0.6), R, (0.9 * hx, 0.7 * hy, 0.44 * hz))
    for s in (-1, 1):
        sk = smin(sk, ell_o(sub, L(s * 0.6, -0.24, -0.64), R, (0.38 * hx, 0.56 * hy, 0.36 * hz)), 0.08 * hz)
    # The snout: flat, narrowing forward to the swollen tip.
    for zz, wx, wy, yy in ((-0.28, 0.8, 0.62, -0.04), (0.08, 0.62, 0.5, -0.1), (0.42, 0.47, 0.44, -0.14), (0.7, 0.38, 0.4, -0.16), (0.9, 0.43, 0.4, -0.15)):
        sk = smin(sk, ell_o(sub, L(0, yy, zz), R, (wx * hx, wy * hy, 0.26 * hz)), 0.1 * hz)
    # The lower jaw under it, its back hinged under the skull's corners.
    for s in (-1, 1):
        sk = smin(sk, cap(sub, L(s * 0.62, -0.5, -0.82), L(s * 0.28, -0.46, 0.86), 0.2 * hy, 0.14 * hy), 0.06 * hz)
    # The eyes on knobs on top of the skull at its back, under a bony brow; the nostrils on a knob
    # at the tip of the snout.
    eyes = []
    for s in (-1, 1):
        sk = smin(sk, ell_o(sub, L(s * 0.42, 0.56, -0.44), R, (0.2 * hx, 0.3 * hy, 0.16 * hz)), 0.05 * hz)
        ec = L(s * 0.5, 0.62, -0.36)
        er = 0.13 * m
        eye = ell_o(sub, ec, R, (er * 1.05, er * 0.8, er * 1.2))
        sk = np.minimum(sk, eye)
        S.mark("eye", eye, sub)
        eyes.append(ec)
    sk = smin(sk, ell_o(sub, L(0, 0.34, 0.84), R, (0.2 * hx, 0.16 * hy, 0.12 * hz)), 0.04 * hz)
    for s in (-1, 1):
        nst = ell_o(sub, L(s * 0.08, 0.5, 0.86), R, (0.05 * hx, 0.08 * hy, 0.04 * hz))
        sk = smax(sk, -nst, 0.01)
        S.mark("nostril", nst, sub)
    # The ridges of the skull: a rough hide in knobs.
    rough = vnoise(np.abs(sub.X), sub.Y, sub.Z, 0.05, 41)
    sk = sk - 0.012 * (rough - 0.5)
    S.add(sk, 0.0, sub)
    S.mark("head", sk, sub)
    # The line of the jaws, rising to the front, and the teeth over it: the upper ones down outside
    # the lower jaw, the lower ones up outside the snout, the fourth from the front the longest.
    lip_y = lambda zz: -0.42 + 0.14 * (zz + 0.8) / 1.7
    for s in (-1, 1):
        for i in range(13):
            zz = -0.62 + 1.5 * i / 12.0
            # (the snout's half width there: the teeth stand at its edge)
            wx = np.interp(zz, [-0.62, -0.28, 0.08, 0.42, 0.7, 0.9], [0.84, 0.78, 0.6, 0.46, 0.38, 0.42])
            big = i in (2, 9)
            lt = (0.34 if big else 0.22) * hy
            a0 = L(s * (wx - 0.02), lip_y(zz) + 0.06, zz)
            tooth = cap(sub, a0, a0 - up * lt + ax * (s * 0.02 * hx), 0.5 * g.cell, 0.004)
            S.add(tooth, 0, sub)
            S.mark("tooth", tooth, sub)
            if i % 2 == 1:
                b0 = L(s * (wx - 0.06), lip_y(zz) - 0.1, zz + 0.04)
                tooth = cap(sub, b0, b0 + up * lt * 0.9 + ax * (s * 0.03 * hx), 0.5 * g.cell, 0.004)
                S.add(tooth, 0, sub)
                S.mark("tooth", tooth, sub)
    # (the dark seam of the shut mouth, along the line)
    lx = (sub.X - pos[0]) * ax[0] + (sub.Y - pos[1]) * ax[1] + (sub.Z - pos[2]) * ax[2]
    ly = (sub.X - pos[0]) * up[0] + (sub.Y - pos[1]) * up[1] + (sub.Z - pos[2]) * up[2]
    lz = (sub.X - pos[0]) * f[0] + (sub.Y - pos[1]) * f[1] + (sub.Z - pos[2]) * f[2]
    seam = np.abs(ly / hy - lip_y(lz / hz)) * hy - 0.3 * g.cell
    seam = np.where((np.abs(lx) > 0.12 * hx) & (lz > -0.9 * hz), seam, INF)
    S.mark("mouth", seam, sub)
    return eyes


def crocodile(sp, g):
    """A great crocodile, low on its sprawled legs: the body broad and flat, rows of bony scutes
    along its back, a double crest of them down the tail; the head long and flat with the teeth
    showing along the shut jaws, the eyes and the nostrils on knobs; a long tail, deep from side to
    side, its end on the ground. Olive above, banded darker, pale yellow under."""
    info = _part_info(sp)
    K = parts_of(sp)
    _, body, bh = K["beastBody"]
    W, H, Lz = (float(v) for v in bh)
    cy, zc = float(body[1]), float(body[2])
    ground = min(float(K[n][1][1] - K[n][2][1]) for n in K if n.startswith("leg") and n.endswith("Lo"))
    S = _Shape(g)
    # The trunk: broad and flat, widest at the belly, narrowing to the shoulders and the hips, the
    # back gently rounded; the shoulders and the hips standing out of its sides a little.
    S.add(ell(g, (0, cy + 0.0 * H, zc - 0.05 * Lz), (0.92 * W, 0.84 * H, 0.72 * Lz)))
    S.add(ell(g, (0, cy + 0.02 * H, zc + 0.5 * Lz), (0.72 * W, 0.8 * H, 0.52 * Lz)), 0.16)
    S.add(ell(g, (0, cy + 0.02 * H, zc - 0.62 * Lz), (0.66 * W, 0.8 * H, 0.42 * Lz)), 0.16)
    S.add(ell(g, (0, cy - 0.3 * H, zc), (0.8 * W, 0.55 * H, 0.8 * Lz)), 0.1)
    for sx in (-1, 1):
        S.add(ell(g, (sx * 0.6 * W, cy - 0.12 * H, zc + 0.58 * Lz), (0.3 * W, 0.6 * H, 0.24 * Lz)), 0.12)
        S.add(ell(g, (sx * 0.58 * W, cy - 0.08 * H, zc - 0.6 * Lz), (0.34 * W, 0.68 * H, 0.28 * Lz)), 0.12)
    trunk = np.array(S.d, copy=True)
    # The neck, thick and short, into the back of the head.
    Rh, hp, hh = K["beastHead"]
    jh = info["beastHead"][3]
    S.add(cap(g, (0, cy + 0.06 * H, zc + 0.78 * Lz), jh + Rh[:, 2] * 0.12, 0.62 * H, 0.82 * float(hh[1])), 0.16)
    # The head.
    S.feat["_eyes"] = _croc_head(S, g, Rh, hp, hh)
    # The legs: short and thick, out from under the sides, the elbows and the knees out, the feet
    # flat with long toes splayed and a claw on each.
    for fb in ("F", "B"):
        for side in ("L", "R"):
            up_n, lo_n = "leg%s%s" % (fb, side), "leg%s%sLo" % (fb, side)
            if up_n not in info or lo_n not in info:
                continue
            j0, j1 = _limb_ends(info, up_n)
            _, j2 = _limb_ends(info, lo_n)
            sx = 1.0 if j0[0] > 0 else -1.0
            r = float(K[up_n][2][1]) * (1.12 if fb == "B" else 0.98)
            sh_ = np.array([j0[0] * 1.02, j0[1] - 0.04, j0[2]])
            el = np.array([j1[0] + sx * 0.1, j1[1] + 0.02, j1[2] + (0.04 if fb == "F" else -0.06)])
            ft = np.array([j2[0] + sx * 0.04, ground, j2[2] + 0.06])
            S.add(cap(g, sh_, el, r * 1.15, r * 0.8), 0.12)
            S.add(cap(g, el, ft + np.array([0, r * 0.5, 0]), r * 0.74, r * 0.56), 0.08)
            toes = tuple(sx * a for a in ((-0.75, -0.35, 0.05, 0.45, 0.85) if fb == "F" else (-0.6, -0.15, 0.3, 0.75)))
            _clawed_foot(S, g, ft, np.array([sx * 0.25, 0.0, 1.0]), r * 0.42, toes, 0.8, 0.7)
    # The tail: deep from side to side, thick at the hips, tapering to its end on the ground.
    ta, tb = _limb_ends(info, "tail")
    _, tc = _limb_ends(info, "tailTip")
    rt = float(K["tail"][2][0])
    # (its top running on from the back's, its underside dropping to the ground toward its end)
    t0 = np.array([0.0, cy + 0.02 * H, zc - 0.7 * Lz])
    pts = [t0, ta + (tb - ta) * 0.4 + np.array([0, cy - ta[1], 0]) * 0.8, tb + np.array([0, -0.06, 0]), tb + (tc - tb) * 0.55 + np.array([0, -0.14, 0]), tc + np.array([0, -0.2, 0.0])]
    rads = [0.9 * H, 0.74 * H, 0.54 * H, 0.32 * H, 0.1 * H]
    tail = None
    for i in range(len(pts) - 1):
        a, b = pts[i], pts[i + 1]
        sub = _around(g, [a, b], max(rads[i], rads[i + 1]) * 1.6 + 0.05)
        # (deep, not broad: a crocodile's swims)
        u = (b - a) / np.linalg.norm(b - a)
        t = np.clip(((sub.X - a[0]) * u[0] + (sub.Y - a[1]) * u[1] + (sub.Z - a[2]) * u[2]) / np.linalg.norm(b - a), 0, 1)
        cxp, cyp, czp = a[0] + (b - a)[0] * t, a[1] + (b - a)[1] * t, a[2] + (b - a)[2] * t
        rr = rads[i] + (rads[i + 1] - rads[i]) * t
        dd = np.sqrt(((sub.X - cxp) / 0.62) ** 2 + ((sub.Y - cyp) / 1.0) ** 2 + (sub.Z - czp) ** 2) - rr
        S.add(dd * 0.62, 0.06, sub)
    # The scutes: rows of bony knobs across the back from the nape to the hips (the middle pair the
    # largest), a cluster of big ones on the nape; down the tail a double crest of upright plates,
    # one row from halfway to the end.
    top_at = lambda x, z: _top_line(S, g, z, x)
    scute = None
    for i, z in enumerate(np.arange(zc + 0.86 * Lz, zc - 0.95 * Lz, -0.115)):
        for xk, k in ((0.07, 1.0), (0.2, 0.85), (0.34, 0.7), (0.48, 0.55)):
            for s in (-1, 1):
                x = s * xk * W
                y = top_at(x, float(z))
                if y is None:
                    continue
                c = np.array([x, y - 0.012, float(z)])
                rr = 0.045 * k * (1.0 if i % 2 == 0 else 0.92)
                sub = _around(g, [c], rr * 2.5)
                kn = ell(sub, c, (rr * 1.1, rr * 0.8, rr * 1.2))
                S.add(kn, 0.012, sub)
                S.mark("scute", kn, sub)
    for s in (-1, 1):
        for x, z, rr in ((0.1, 0.0, 0.07), (0.24, 0.02, 0.06), (0.12, -0.16, 0.06)):
            zz = float(jh[2]) - 0.12 + z
            y = top_at(s * x, zz)
            if y is None:
                continue
            c = np.array([s * x, y - 0.01, zz])
            sub = _around(g, [c], rr * 2.5)
            kn = ell(sub, c, (rr, rr * 0.85, rr * 1.1))
            S.add(kn, 0.01, sub)
            S.mark("scute", kn, sub)
    tpts, tups, tbacks, ths = [], [], [], []
    for t in np.linspace(0.04, 0.96, 16):
        # (along the tail's line)
        seg = min(int(t * (len(pts) - 1)), len(pts) - 2)
        lt = t * (len(pts) - 1) - seg
        q = pts[seg] + (pts[seg + 1] - pts[seg]) * lt
        rr = rads[seg] + (rads[seg + 1] - rads[seg]) * lt
        double = t < 0.5
        for s in ((-1, 1) if double else (0,)):
            x = s * rr * 0.36
            y = top_at(x, float(q[2]))
            if y is None:
                continue
            tpts.append(np.array([x, y - 0.02, float(q[2])]))
            tups.append(np.array([s * 0.15, 1.0, 0.0]) / np.linalg.norm([s * 0.15, 1.0, 0.0]))
            tbacks.append(np.array([0.0, 0.0, -1.0]))
            ths.append(max(0.05, 0.13 * (1.0 - 0.6 * t)))
    _spine_row(S, g, tpts, tups, tbacks, ths, max(0.6 * g.cell, 0.02), key="scute")
    d = S.d
    occ = d < 0
    thr_c = 0.4 * g.cell
    # Colours: olive above with darker bands across the back and the tail, the scutes darker still
    # on their tops, the flanks paler, the belly pale yellow in square plates.
    olive = np.array([0.24, 0.27, 0.13])
    dark = np.array([0.1, 0.11, 0.06])
    pale = np.array([0.8, 0.74, 0.5])
    col = np.zeros(g.shape + (3,))
    col[:] = olive
    wv = vnoise(np.abs(g.X), g.Y, g.Z, 0.2, 7)
    band = (np.sin((g.Z * 3.4 + wv * 1.6) * math.pi) > 0.45) & (g.Z < zc + 0.2 * Lz)
    col[band] = col[band] * 0.55 + dark * 0.45
    side = np.clip((cy + 0.1 * H - g.Y) / (0.9 * H), 0, 1)
    col = col * (1 - 0.45 * side[..., None]) + pale * (0.45 * side[..., None]) * 0.9
    col = _scales(g, col, 0.06)
    belly = (g.Y < cy - 0.55 * H) & occ & (np.abs(g.X) < 0.7 * W) & (trunk < 0.5 * g.cell)
    plates = (np.abs((g.Z / 0.07) % 1.0 - 0.5) > 0.42) | (np.abs((np.abs(g.X) / 0.07) % 1.0 - 0.5) > 0.42)
    col[belly] = pale * np.where(plates[belly], 0.82, 1.0)[:, None]
    sc = S.on("scute", thr_c)
    col[sc] = col[sc] * 0.7 + dark * 0.3
    kind = np.full(g.shape, SCALE_KIND, np.uint8)
    ck = S.on("claw", thr_c)
    col[ck] = np.array([0.16, 0.13, 0.1])
    kind[ck] = BONE
    th_k = S.on("tooth", thr_c)
    col[th_k] = np.array([0.9, 0.86, 0.72])
    kind[th_k] = BONE
    mo = S.on("mouth", thr_c) & ~th_k
    col[mo] = np.array([0.08, 0.06, 0.04])
    ns = (S.feat.get("nostril", np.full(g.shape, INF)) < thr_c * 1.5) & occ
    col[ns] = np.array([0.05, 0.04, 0.03])
    ey = S.on("eye", thr_c)
    col[ey] = np.array([0.72, 0.62, 0.16])
    kind[ey] = WET
    f = Rh[:, 2]
    upv = Rh[:, 1]
    for c in S.feat.get("_eyes", []):
        dz = (g.X - c[0]) * f[0] + (g.Y - c[1]) * f[1] + (g.Z - c[2]) * f[2]
        slit = ey & (np.abs(dz) < 0.3 * g.cell + 0.008)
        col[slit] = np.array([0.04, 0.03, 0.02])
    return d, np.clip(col, 0, 1), kind


SCULPTS["crocodile"] = crocodile


def _catmull(pts, step):
    """Points along a Catmull-Rom curve through `pts`, about `step` apart."""
    P = [np.asarray(p, float) for p in pts]
    P = [P[0] * 2 - P[1]] + P + [P[-1] * 2 - P[-2]]
    out = []
    for i in range(1, len(P) - 2):
        p0, p1, p2, p3 = P[i - 1], P[i], P[i + 1], P[i + 2]
        n = max(2, int(np.linalg.norm(p2 - p1) / step))
        for k in range(n):
            t = k / n
            t2, t3 = t * t, t * t * t
            out.append(0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 + (-p0 + 3 * p1 - 3 * p2 + p3) * t3))
    out.append(P[-2])
    return out


def _tube(S, g, pts, rads, flat=1.0, k=0.0, key=None):
    """A tube along points, its radius running along `rads` (one a point), as wide as `flat` times
    its height (a serpent's, lying on its belly): one piece (its segments not blended into one
    another, which swelled it past its own marks), blended by `k` into what is there."""
    tube = np.full(g.shape, INF)
    for i in range(len(pts) - 1):
        a, b = pts[i], pts[i + 1]
        ra, rb = rads[i], rads[i + 1]
        sub = _around(g, [a, b], max(ra, rb) * max(flat, 1.0) + 0.05)
        ab = b - a
        L2 = float(ab @ ab)
        t = np.clip(((sub.X - a[0]) * ab[0] + (sub.Y - a[1]) * ab[1] + (sub.Z - a[2]) * ab[2]) / max(L2, 1e-9), 0, 1)
        cx, cy_, cz = a[0] + ab[0] * t, a[1] + ab[1] * t, a[2] + ab[2] * t
        rr = ra + (rb - ra) * t
        dd = (np.sqrt(((sub.X - cx) / flat) ** 2 + (sub.Y - cy_) ** 2 + ((sub.Z - cz) / flat) ** 2) - rr) * min(flat, 1.0)
        tube[sub.sl] = np.minimum(tube[sub.sl], dd)
    S.add(tube, k)
    if key:
        S.mark(key, tube)


def basilisk(sp, g):
    """The king of serpents: a great snake lying in an S of thick coils, its belly flat on the
    ground in plates; the front of it reared up, a hood spread at the top of the neck; a viper's
    head, broad behind, the brows standing up over glowing eyes, the jaws a little open on two long
    fangs and a forked tongue; on its crown a fan of spines with a red web between them. Dark green
    in scales with black bands, the belly and the throat pale gold."""
    info = _part_info(sp)
    K = parts_of(sp)
    _, body, bh = K["beastBody"]
    W, H, Lz = (float(v) for v in bh)
    cy, zc = float(body[1]), float(body[2])
    S = _Shape(g)
    # The coils: one smooth S through the body and the coils' joints to the tip of the tail, thick
    # in the middle, tapering to the tail; flat underneath.
    path = [np.array([0.0, cy, zc + 0.75 * Lz]), np.array([0.0, cy, zc])]
    for n in ("coil1", "coil2", "tailTip"):
        if n in info:
            a, b = _limb_ends(info, n)
            path.append(np.array([a[0], cy, a[2]]))
            if n == "tailTip":
                path.append(np.array([b[0], cy, b[2]]))
    # (where coil1 starts is the body's back end: one point there)
    clean = [path[0]]
    for p in path[1:]:
        if np.linalg.norm(p - clean[-1]) > 0.2:
            clean.append(p)
    curve = _catmull(clean, 0.12)
    n = len(curve)
    r0 = 0.92 * H
    rads = []
    for i in range(n):
        t = i / (n - 1)
        rads.append(r0 * (1.0 if t < 0.35 else max(0.08, 1.0 - (t - 0.35) / 0.65 * 0.95)))
    # (the belly resting on the ground: each point lowered as it thins)
    curve = [np.array([p[0], (cy - H) + r * 0.95, p[2]]) for p, r in zip(curve, rads)]
    _tube(S, g, curve, rads, flat=1.18, k=0.06)
    coils = np.array(S.d, copy=True)
    # The neck: up out of the front of the coils in a curve, back and then forward under the head.
    jn = info["neck"][3]
    Rh, hp, hh = K["beastHead"]
    jh = info["beastHead"][3]
    npts = [np.array([0.0, cy + 0.1 * H, zc + 0.7 * Lz]), np.array([0.0, jn[1] + 0.25, jn[2] + 0.02]), np.array([0.0, (jn[1] + jh[1]) * 0.5 + 0.1, (jn[2] + jh[2]) * 0.5 - 0.08]), jh + np.array([0.0, 0.05, 0.12])]
    ncurve = _catmull(npts, 0.1)
    rn = float(K["neck"][2][0])
    nrads = [rn * (0.78 - 0.2 * i / (len(ncurve) - 1)) for i in range(len(ncurve))]
    _tube(S, g, ncurve, nrads, flat=1.1, k=0.12, key="neck")
    # The hood: spread to either side over the upper neck, flat, its front the throat's.
    hood_c = ncurve[int(len(ncurve) * 0.62)]
    hood_u = ncurve[-1] - ncurve[int(len(ncurve) * 0.35)]
    hood_u = hood_u / np.linalg.norm(hood_u)
    hood_f = np.array([0.0, -hood_u[2], hood_u[1]])   # (its front, the throat's way)
    if hood_f[2] < 0:
        hood_f = -hood_f
    Rhood = np.stack([np.array([1.0, 0.0, 0.0]), hood_u, hood_f], axis=1)
    sub = _around(g, [hood_c + np.array([s * 0.75, 0.0, 0.0]) + hood_u * u for s in (-1, 1) for u in (-0.7, 0.6)], 0.15)
    hood = ell_o(sub, hood_c - hood_f * rn * 0.1, Rhood, (rn * 1.45, rn * 1.7, rn * 0.32))
    hood = smax(hood, -(ell_o(sub, hood_c - hood_f * rn * 0.7, Rhood, (rn * 0.95, rn * 1.3, rn * 0.45))), 0.05)
    S.add(hood, 0.08, sub)
    S.mark("hood", hood, sub)
    # The head: a viper's, broad behind where the poison is, the snout rounded; heavy brows over
    # the eyes; the jaw dropped a little on two long fangs.
    hx, hy, hz = (float(v) for v in hh)
    ax_, up, f = Rh[:, 0], Rh[:, 1], Rh[:, 2]

    def L(x, y, z):
        return hp + ax_ * (x * hx) + up * (y * hy) + f * (z * hz)
    sub = _around(g, [L(x, y, z) for x in (-1.3, 1.3) for y in (-1.5, 1.6) for z in (-1.3, 1.3)], 0.05)
    m = min(hx, hy)
    sk = ell_o(sub, L(0, 0.12, -0.42), Rh, (0.9 * hx, 0.62 * hy, 0.5 * hz))
    for s in (-1, 1):
        sk = smin(sk, ell_o(sub, L(s * 0.56, -0.06, -0.52), Rh, (0.46 * hx, 0.54 * hy, 0.44 * hz)), 0.08 * hz)
    for zz, wx, wy, yy in ((0.05, 0.68, 0.46, 0.14), (0.42, 0.54, 0.4, 0.1), (0.75, 0.4, 0.33, 0.06), (0.92, 0.3, 0.27, 0.04)):
        sk = smin(sk, ell_o(sub, L(0, yy, zz), Rh, (wx * hx, wy * hy, 0.24 * hz)), 0.1 * hz)
    # (the lower jaw, hung a little open)
    gape = 0.16
    chin = L(0, -0.5 - gape, 0.78)
    jaw = None
    for s in (-1, 1):
        j = cap(sub, L(s * 0.6, -0.36, -0.6), chin + ax_ * (s * 0.1 * hx), 0.2 * m, 0.13 * m)
        jaw = j if jaw is None else smin(jaw, j, 0.08 * m)
    jaw = smin(jaw, ell_o(sub, L(0, -0.48 - 0.5 * gape, 0.1), Rh, (0.4 * hx, 0.14 * hy, 0.56 * hz)), 0.06 * m)
    sk = smin(sk, jaw, 0.05 * m)
    mouth = ell_o(sub, L(0, -0.3 - 0.45 * gape, 0.22), Rh, (0.42 * hx, 0.1 * hy, 0.6 * hz))
    sk = smax(sk, -mouth, 0.02)
    S.mark("mouth", ell_o(sub, L(0, -0.3 - 0.45 * gape, 0.22), Rh, (0.46 * hx, 0.16 * hy, 0.64 * hz)), sub)
    # Brows standing up over the eyes, like horns laid back; the eyes under them; nostrils.
    eyes = []
    for s in (-1, 1):
        ec = L(s * 0.56, 0.3, 0.12)
        er = 0.15 * m
        sk = smax(sk, -ell_o(sub, ec, Rh, (er * 1.25, er * 1.0, er * 1.3)), 0.01)
        eye = ell_o(sub, ec - ax_ * (s * er * 0.2), Rh, (er, er * 0.85, er * 1.1))
        sk = np.minimum(sk, eye)
        S.mark("eye", eye, sub)
        eyes.append(ec)
        brow = smin(cap(sub, L(s * 0.5, 0.5, 0.36), L(s * 0.62, 0.66, -0.12), 0.12 * m, 0.1 * m), cap(sub, L(s * 0.62, 0.66, -0.12), L(s * 0.7, 0.98, -0.5), 0.1 * m, 0.02), 0.04)
        S.add(brow, 0.03, sub)
        S.mark("brow", brow, sub)
        nst = ell_o(sub, L(s * 0.16, 0.14, 0.98), Rh, (0.05 * hx, 0.05 * hy, 0.05 * hz))
        sk = smax(sk, -nst, 0.01)
    S.add(sk, 0.0, sub)
    S.mark("head", sk, sub)
    S.feat["_eyes"] = eyes
    # The fangs: two long ones down from the front of the upper jaw, curved back a little; small
    # teeth along it.
    for s in (-1, 1):
        a0 = L(s * 0.3, -0.22, 0.6)
        fang = smin(cap(sub, a0, a0 - up * 0.32 * hy + f * 0.02 * hz, 0.06 * m, 0.035 * m), cap(sub, a0 - up * 0.32 * hy + f * 0.02 * hz, a0 - up * 0.5 * hy - f * 0.06 * hz, 0.035 * m, 0.004), 0.01)
        S.add(fang, 0, sub)
        S.mark("tooth", fang, sub)
        for i in range(4):
            zz = 0.36 - 0.22 * i
            t0 = L(s * (0.42 + 0.06 * i), -0.25, zz)
            tooth = cap(sub, t0, t0 - up * 0.13 * hy, max(0.5 * g.cell, 0.03 * m), 0.004)
            S.add(tooth, 0, sub)
            S.mark("tooth", tooth, sub)
    # The crown: a fan of spines up from the top of the head, raked back, the tallest behind the
    # eyes; a web between them, its edge scalloped.
    Rc, cp, chh = K["crest"]
    top_y = float(L(0, 0.62, 0)[1])
    zs = np.linspace(float(L(0, 0, 0.55)[2]), float(L(0, 0, -0.85)[2]), 6)
    hs = [0.45, 0.75, 1.0, 1.0, 0.8, 0.55]
    tips = []
    spines = None
    for z, hk in zip(zs, hs):
        base = np.array([0.0, top_y - 0.04, float(z)])
        tip = base + np.array([0.0, chh[1] * 1.6 * hk, -0.22 * hk])
        tips.append(tip)
        sub2 = _around(g, [base, tip], 0.12)
        spn = cap(sub2, base, tip, 0.75 * g.cell, 0.5 * g.cell)
        S.add(spn, 0.02, sub2)
        S.mark("spine", spn, sub2)
    # (the web: between the spines, as high as each and dipping between them)
    sub2 = _around(g, [np.array([0.0, top_y, zs[0] + 0.1]), np.array([0.0, top_y, zs[-1] - 0.1])] + tips, 0.08)
    zz_ = sub2.Z
    tip_z = np.array([t[2] for t in tips])[::-1]
    tip_y = np.array([t[1] for t in tips])[::-1]
    edge = np.interp(zz_, tip_z, tip_y)
    # scallops: lower between the tips
    span = (tip_z[-1] - tip_z[0]) / (len(tip_z) - 1)
    ph = ((zz_ - tip_z[0]) / span) % 1.0
    edge = edge - 0.22 * np.sin(ph * math.pi) * (edge - top_y) * 0.6
    web = np.maximum(np.maximum(np.abs(sub2.X) - max(0.035, 0.45 * g.cell), sub2.Y - edge), top_y - 0.05 - sub2.Y)
    web = np.maximum(web, np.maximum(zz_ - (zs[0] + 0.06), (zs[-1] - 0.06) - zz_))
    S.add(web, 0.02, sub2)
    S.mark("web", web, sub2)
    d = S.d
    occ = d < 0
    thr_c = 0.4 * g.cell
    # Colours: dark green scales, black bands across the coils (wider on top), a paler stripe low
    # on each flank; the belly in pale gold plates; the throat and the hood's front pale with dark
    # bars; the web red; spines, brows and fangs bone; the eyes glowing.
    green = np.array([0.1, 0.26, 0.12])
    black = np.array([0.03, 0.05, 0.03])
    gold = np.array([0.82, 0.7, 0.36])
    col = np.zeros(g.shape + (3,))
    col[:] = green
    # (bands along the coils: by the distance along the curve)
    cz = np.array([p[2] for p in curve])
    cx = np.array([p[0] for p in curve])
    seg = np.concatenate([[0.0], np.cumsum(np.linalg.norm(np.diff(np.array(curve), axis=0), axis=1))])
    s_al = np.interp(g.Z, cz[::-1], seg[::-1]) if np.all(np.diff(cz) <= 0) else None
    if s_al is None:
        # (the curve doubles back in z: the nearest of its points)
        flat_idx = np.argmin((g.Z[..., None] - cz) ** 2 + (g.X[..., None] - cx) ** 2, axis=-1)
        s_al = seg[flat_idx]
    wv = vnoise(np.abs(g.X), g.Y, g.Z, 0.25, 3)
    band = ((s_al / 0.55 + wv * 0.6) % 1.0) < 0.28
    col[band & (coils < 0.5 * g.cell)] = black * 1.4
    col = _scales(g, col, 0.07)
    low = (g.Y < cy - 0.35 * H) & (coils < 0.5 * g.cell)
    col[low] = gold * 0.62
    belly = (g.Y < cy - 0.72 * H) & (coils < 0.5 * g.cell)
    plates = np.abs((s_al / 0.09) % 1.0 - 0.5) > 0.4
    col[belly] = gold * np.where(plates[belly], 0.78, 1.0)[:, None]
    # (the throat: the front of the neck and the hood)
    nk = S.on("neck", thr_c)
    rx = g.Z - np.interp(g.Y, [p[1] for p in ncurve], [p[2] for p in ncurve])
    throat = nk & (rx > 0.4 * rn)
    hd = S.on("hood", thr_c)
    hood_front = hd & (((g.X - hood_c[0]) * hood_f[0] + (g.Y - hood_c[1]) * hood_f[1] + (g.Z - hood_c[2]) * hood_f[2]) > -rn * 0.1)
    tf = throat | hood_front
    bars = np.abs(((g.Y - hood_c[1]) / 0.16) % 1.0 - 0.5) > 0.36
    col[tf] = gold * np.where(bars[tf], 0.4, 0.95)[:, None]
    # (the back of the hood: a pale ring on the dark, the king's mark)
    hb_ = hd & ~hood_front
    ring = np.abs(np.sqrt((g.X / (rn * 1.0)) ** 2 + ((g.Y - hood_c[1]) / (rn * 1.2)) ** 2) - 1.0) < 0.18
    col[hb_ & ring] = gold * 0.9
    kind = np.full(g.shape, SCALE_KIND, np.uint8)
    wb = S.on("web", thr_c)
    vein = vnoise(np.abs(g.X), g.Y, g.Z, 0.08, 6)
    col[wb] = np.array([0.62, 0.06, 0.05]) * (0.8 + 0.4 * vein[wb])[:, None]
    for key, c_ in (("spine", (0.86, 0.72, 0.36)), ("brow", (0.5, 0.44, 0.3))):
        km = S.on(key, thr_c)
        col[km] = np.array(c_)
        kind[km] = BONE
    th_k = S.on("tooth", thr_c)
    col[th_k] = np.array([0.93, 0.9, 0.8])
    kind[th_k] = BONE
    mo = S.on("mouth", thr_c) & ~th_k
    col[mo] = np.array([0.55, 0.12, 0.14])
    kind[mo] = WET
    # (the head: a dark band back from each eye, the lips and the jaw under them pale)
    hd_ = S.on("head", thr_c)
    lx = (g.X - hp[0]) * ax_[0] + (g.Y - hp[1]) * ax_[1] + (g.Z - hp[2]) * ax_[2]
    ly = (g.X - hp[0]) * up[0] + (g.Y - hp[1]) * up[1] + (g.Z - hp[2]) * up[2]
    lz = (g.X - hp[0]) * f[0] + (g.Y - hp[1]) * f[1] + (g.Z - hp[2]) * f[2]
    col[hd_ & (ly < -0.2 * hy)] = gold * 0.85
    stripe = hd_ & (np.abs(ly - (0.3 * hy + (0.12 - lz / hz) * 0.25 * hy)) < 0.09 * hy) & (lz < 0.12 * hz) & (np.abs(lx) > 0.4 * hx)
    col[stripe] = black * 1.2
    ey = S.on("eye", thr_c)
    col[ey] = np.array([0.95, 0.85, 0.15])
    kind[ey] = GLOW_KIND
    _slits(S, g, ey, Rh, hh, col)
    return d, np.clip(col, 0, 1), kind


SCULPTS["basilisk"] = basilisk


def _cat_k(sp, g, P, k, drop=()):
    """A big cat (cat()'s, the lion's own sculpt) over parts `k` times a lion's size: sculpted at
    the lion's size and scaled up, so its skull, its muzzle, its paws and its mane are as the
    lion's are. Returns (distance, colour, kind) and where its head is (hc, mz, hs: the skull's
    middle, the muzzle's, the head's size, in the beast's own metres)."""
    sp2 = {"parts": []}
    for p in sp["parts"]:
        if p["name"] in drop:
            continue
        q = dict(p)
        q["pos"] = [float(v) / k for v in p["pos"]]
        q["scale"] = float(p["scale"]) / k
        sp2["parts"].append(q)
    g2 = Grid(g.lo / k, g.shape, g.cell / k)
    d, col, kind = cat(sp2, g2, P)
    K = parts_of(sp2)
    head = K["beastHead"][1]
    hs = P["head"]
    hc = np.array([0.0, head[1] + 0.07, head[2] + 0.06])
    mz = hc + np.array([0.0, -0.15, 0.25]) * hs
    return d * k, col, kind, hc * k, mz * k, hs * k


def _goat_head(S, g, R, pos, half):
    """A goat's head in its box, forward its +z: a long face to a narrow muzzle, the jaw under it
    and a beard from the chin; ears out flat to the sides; eyes on the sides of the skull (their
    pupils bars across). Returns the eyes' middles."""
    hx, hy, hz = (float(v) for v in half)
    ax, up, f = R[:, 0], R[:, 1], R[:, 2]

    def L(x, y, z):
        return pos + ax * (x * hx) + up * (y * hy) + f * (z * hz)
    sub = _around(g, [L(x, y, z) for x in (-1.3, 1.3) for y in (-1.6, 1.2) for z in (-1.2, 1.2)], 0.05)
    m = min(hx, hy)
    sk = ell_o(sub, L(0, 0.3, -0.35), R, (0.62 * hx, 0.52 * hy, 0.44 * hz))
    sk = smin(sk, cap(sub, L(0, 0.2, -0.12), L(0, -0.22, 0.78), 0.44 * hx, 0.28 * hx), 0.08 * hz)
    sk = smin(sk, ell_o(sub, L(0, -0.3, 0.74), R, (0.3 * hx, 0.28 * hy, 0.24 * hz)), 0.05 * hz)
    sk = smin(sk, cap(sub, L(0, -0.46, -0.12), L(0, -0.5, 0.64), 0.22 * hx, 0.15 * hx), 0.05 * hz)
    eyes = []
    for s in (-1, 1):
        ec = L(s * 0.56, 0.34, 0.02)
        er = 0.13 * m
        sk = smax(sk, -ell_o(sub, ec, R, (er * 1.2, er * 1.0, er * 1.2)), 0.01)
        eye = ell_o(sub, ec - ax * (s * er * 0.2), R, (er, er * 0.85, er))
        sk = np.minimum(sk, eye)
        S.mark("goat_eye", eye, sub)
        eyes.append(ec)
        ear = cap(sub, L(s * 0.5, 0.28, -0.38), L(s * 1.08, 0.06, -0.5), 0.15 * hx, 0.07 * hx)
        ear = smax(ear, np.abs((sub.X - ec[0]) * up[0] + (sub.Y - ec[1]) * up[1] + (sub.Z - ec[2]) * up[2] + 0.06 * hy) - 0.07 * hy, 0.02)
        sk = smin(sk, ear, 0.03)
    S.add(sk, 0.0, sub)
    S.mark("goat", sk, sub)
    # (the beard: in a point down from the chin, in locks)
    lock = vnoise(np.abs(sub.X), sub.Y, sub.Z, 0.03, 17)
    beard = cap(sub, L(0, -0.62, 0.42), L(0, -1.4, 0.2), 0.2 * hx, 0.03) - 0.03 * (lock - 0.5)
    S.add(beard, 0.02, sub)
    S.mark("beard", beard, sub)
    for s in (-1, 1):
        nst = ell_o(sub, L(s * 0.1, -0.2, 0.98), R, (0.05 * hx, 0.05 * hy, 0.04 * hz))
        S.mark("goat_nose", nst, sub)
    return eyes


def _snake_head(S, g, R, pos, half, gape=0.3, key="snake"):
    """A viper's head in its box, forward its +z, the jaws open on two fangs."""
    hx, hy, hz = (float(v) for v in half)
    ax, up, f = R[:, 0], R[:, 1], R[:, 2]

    def L(x, y, z):
        return pos + ax * (x * hx) + up * (y * hy) + f * (z * hz)
    sub = _around(g, [L(x, y, z) for x in (-1.3, 1.3) for y in (-1.6, 1.4) for z in (-1.3, 1.3)], 0.05)
    m = min(hx, hy)
    sk = ell_o(sub, L(0, 0.1, -0.35), R, (0.92 * hx, 0.6 * hy, 0.52 * hz))
    for zz, wx, wy in ((0.1, 0.7, 0.46), (0.5, 0.52, 0.38), (0.85, 0.36, 0.3)):
        sk = smin(sk, ell_o(sub, L(0, 0.12, zz), R, (wx * hx, wy * hy, 0.26 * hz)), 0.1 * hz)
    chin = L(0, -0.5 - gape, 0.75)
    jaw = None
    for s in (-1, 1):
        j = cap(sub, L(s * 0.6, -0.3, -0.55), chin + ax * (s * 0.1 * hx), 0.22 * m, 0.13 * m)
        jaw = j if jaw is None else smin(jaw, j, 0.08 * m)
    sk = smin(sk, jaw, 0.05 * m)
    mouth = ell_o(sub, L(0, -0.25 - 0.5 * gape, 0.2), R, (0.45 * hx, 0.14 * hy + 0.3 * gape * hy, 0.62 * hz))
    sk = smax(sk, -mouth, 0.02)
    S.mark(key + "_mouth", ell_o(sub, L(0, -0.25 - 0.5 * gape, 0.2), R, (0.5 * hx, 0.2 * hy + 0.3 * gape * hy, 0.66 * hz)), sub)
    eyes = []
    for s in (-1, 1):
        ec = L(s * 0.6, 0.32, 0.05)
        er = 0.16 * m
        eye = ell_o(sub, ec - ax * (s * er * 0.2), R, (er, er * 0.85, er * 1.1))
        sk = np.minimum(sk, eye)
        S.mark(key + "_eye", eye, sub)
        eyes.append(ec)
    S.add(sk, 0.0, sub)
    S.mark(key, sk, sub)
    for s in (-1, 1):
        a0 = L(s * 0.32, -0.18, 0.62)
        fang = cap(sub, a0, a0 - up * (0.45 + gape) * hy - f * 0.08 * hz, max(0.55 * g.cell, 0.07 * m), 0.004)
        S.add(fang, 0, sub)
        S.mark("tooth", fang, sub)
    return eyes


def chimera(sp, g):
    """The chimera: a lion (the lion's own sculpt, its mane, larger) with a goat's neck and head
    rising from the middle of its back, black-haired with great ridged horns swept back, and for a
    tail a serpent, scaled, its head poised over the lion's back with its jaws open."""
    info = _part_info(sp)
    K = parts_of(sp)
    k = float(K["beastBody"][2][1]) / 0.499   # (the lion's trunk is 0.499 high: a lion that much larger)
    P = dict(CATS["lion"], mane=0x6a3214, mane2=0x3a1a0a, head=1.24)
    d, col, kind, hc, mz, hs = _cat_k(sp, g, P, k, drop=("tail", "tail2"))
    S = _Shape(g)
    S.d = d
    # The goat's neck out of the middle of the back, and its head.
    a, b = _limb_ends(info, "goatNeck")
    Rg, gp, gh = K["goatHead"]
    _, body, bh = K["beastBody"]
    base = np.array([0.0, float(body[1] + bh[1]) - 0.12, float(a[2]) + 0.05])
    npts = _catmull([base, a + (b - a) * 0.5 + np.array([0, 0, 0.04]), b + np.array([0.0, 0.02, 0.02])], 0.08)
    rn = float(K["goatNeck"][2][0])
    _tube(S, g, npts, [rn * (1.25 - 0.35 * i / (len(npts) - 1)) for i in range(len(npts))], 1.0, 0.1, key="goat_neck")
    geyes = _goat_head(S, g, Rg, gp, gh)
    # Its horns: from the crown back over the neck, thick and ridged, curling down at their tips.
    for n in ("goatHornL", "goatHornR"):
        h0, h1 = _limb_ends(info, n)
        sx = 1.0 if h0[0] > 0 else -1.0
        mid = h1 + np.array([sx * 0.05, 0.02, -0.18])
        tip = mid + np.array([sx * 0.1, -0.24, -0.2])
        rh = float(K[n][2][0])
        sub = _around(g, [h0, h1, mid, tip], rh * 1.8 + 0.05)
        hn = smin(cap(sub, h0 - (h1 - h0) * 0.2, h1, rh * 1.25, rh * 0.95), cap(sub, h1, mid, rh * 0.95, rh * 0.62), 0.03)
        hn = smin(hn, cap(sub, mid, tip, rh * 0.62, 0.01), 0.02)
        S.add(hn, 0.04, sub)
        S.mark("horn", hn, sub)
    # The serpent: from the root of the tail, scaled, up and back, its head bent down to strike.
    t0, t1 = _limb_ends(info, "tail")
    _, t2 = _limb_ends(info, "tail2")
    Rs, spos, sh_ = K["snakeHead"]
    js = info["snakeHead"][3]
    rt = float(K["tail"][2][0])
    tpts = _catmull([t0 + np.array([0, -0.05, 0.12]), t0 + (t1 - t0) * 0.55 + np.array([0, 0.05, 0]), t1 + np.array([0, 0.06, -0.05]), t2 + np.array([0, 0.0, 0.08]), js], 0.08)
    trad = [rt * (0.9 + 0.35 * min(1.0, 3.0 * i / (len(tpts) - 1)) - 0.2 * i / (len(tpts) - 1)) for i in range(len(tpts))]
    _tube(S, g, tpts, trad, 1.0, 0.05, key="serpent")
    seyes = _snake_head(S, g, Rs, spos + Rs[:, 2] * float(sh_[2]) * 0.15, sh_ * np.array([1.25, 1.2, 1.1]), 0.35, "snake")
    d = S.d
    occ = d < 0
    thr_c = 0.4 * g.cell
    col = np.array(col, copy=True)
    kind = np.array(kind, copy=True)
    # Colours: the goat black-haired, its muzzle and beard grey; the horns ridged horn; the serpent
    # dark green in scales with a pale belly; eyes.
    fine = hash3(np.floor(np.abs(g.X) / g.cell), np.floor(g.Y / g.cell), np.floor(g.Z / g.cell), 31)
    goat = (S.on("goat", thr_c) | S.on("goat_neck", 0.03) | S.on("beard", thr_c)) & occ
    col[goat] = np.array([0.13, 0.11, 0.1]) * (0.85 + 0.35 * fine[goat])[:, None]
    kind[goat] = FUR
    lx = g.Z - gp[2]
    muz = S.on("goat", thr_c) & (((g.X - gp[0]) * Rg[0, 2] + (g.Y - gp[1]) * Rg[1, 2] + (g.Z - gp[2]) * Rg[2, 2]) > 0.55 * float(gh[2]))
    col[muz] = np.array([0.36, 0.33, 0.3])
    bd = S.on("beard", thr_c)
    col[bd] = np.array([0.42, 0.4, 0.38]) * (0.85 + 0.3 * fine[bd])[:, None]
    gn = (S.feat.get("goat_nose", np.full(g.shape, INF)) < thr_c * 1.5) & occ
    col[gn] = np.array([0.04, 0.03, 0.03])
    hk = S.on("horn", thr_c)
    if hk.any():
        rings = np.abs(((g.Y + 0.6 * np.abs(g.X) - 0.4 * g.Z) / 0.06) % 1.0 - 0.5) > 0.36
        col[hk] = np.array([0.5, 0.44, 0.34]) * np.where(rings[hk], 0.62, 1.0)[:, None]
        kind[hk] = BONE
    ge = S.on("goat_eye", thr_c)
    col[ge] = np.array([0.9, 0.62, 0.1])
    kind[ge] = WET
    for c in geyes:
        bar = ge & (np.abs(g.Y - c[1]) < 0.4 * g.cell + 0.01) & (np.abs(g.Z - c[2]) < 0.05)
        col[bar] = np.array([0.03, 0.02, 0.02])
    sn = (S.on("serpent", 0.03) | S.on("snake", thr_c)) & occ & ~hk
    green = np.array([0.12, 0.3, 0.14])
    scol = np.zeros(g.shape + (3,))
    scol[:] = green
    scol = _scales(g, scol, 0.05)
    col[sn] = scol[sn]
    kind[sn] = SCALE_KIND
    under = sn & ~S.on("snake", thr_c) & (g.Y < np.interp(g.Z, [p[2] for p in tpts][::-1], [p[1] for p in tpts][::-1]) - 0.06)
    col[under] = np.array([0.78, 0.7, 0.4])
    smo = S.on("snake_mouth", thr_c) & occ
    col[smo] = np.array([0.55, 0.12, 0.14])
    kind[smo] = WET
    th = S.on("tooth", thr_c)
    col[th] = np.array([0.93, 0.9, 0.8])
    kind[th] = BONE
    se = S.on("snake_eye", thr_c)
    col[se] = np.array([0.95, 0.8, 0.12])
    kind[se] = GLOW_KIND
    return d, np.clip(col, 0, 1), kind


SCULPTS["chimera"] = chimera


def _man_face(S, g, hc, hs):
    """The manticore's face, as the old books give it: a man's, framed in the lion's mane. The
    lion's face taken away; a man's head in its place, forward its +z: a high brow, the ridges
    over deep eyes (whites, and pale irises that glow), a heavy nose, cheekbones, a wide mouth
    drawn back in a grin on rows of sharp teeth, a jaw and a beard into the mane; a man's ears
    under the mane. Marks: face, lips, face_mouth, eye_white, iris, beard, tooth."""
    u = hs
    c = np.array(hc, float)

    def P(x, y, z):
        return c + np.array([x, y, z]) * u
    sub = _around(g, [P(-0.45, -0.62, -0.35), P(0.45, 0.45, 0.6)], 0.05)
    # (the lion's face taken away: its muzzle, its cheeks, its chin)
    S.cut(ell(sub, P(0, -0.06, 0.2), np.array([0.3, 0.32, 0.28]) * u), 0.02, sub)
    # the cranium, behind the face; the forehead; the cheekbones; the jaw; the mouth's mound; the chin
    sk = ell(sub, P(0, 0.08, -0.05), np.array([0.21, 0.23, 0.24]) * u)
    sk = smin(sk, ell(sub, P(0, 0.11, 0.07), np.array([0.17, 0.11, 0.11]) * u), 0.03 * u)
    for s in (-1, 1):
        sk = smin(sk, ell(sub, P(s * 0.115, -0.04, 0.115), np.array([0.07, 0.06, 0.075]) * u), 0.035 * u)
        sk = smin(sk, cap(sub, P(s * 0.16, -0.05, -0.03), P(s * 0.07, -0.235, 0.13), 0.06 * u, 0.05 * u), 0.04 * u)
    sk = smin(sk, ell(sub, P(0, -0.15, 0.135), np.array([0.115, 0.08, 0.09]) * u), 0.03 * u)
    sk = smin(sk, ell(sub, P(0, -0.25, 0.14), np.array([0.085, 0.065, 0.075]) * u), 0.03 * u)
    # the ridges of the brow, the sockets under them
    for s in (-1, 1):
        sk = smin(sk, cap(sub, P(s * 0.03, 0.065, 0.19), P(s * 0.145, 0.06, 0.155), 0.03 * u, 0.026 * u), 0.02 * u)
    eyes = []
    for s in (-1, 1):
        ec = P(s * 0.078, 0.012, 0.165)
        sk = smax(sk, -ell(sub, ec + np.array([0, 0, 0.012]) * u, np.array([0.05, 0.034, 0.04]) * u), 0.008 * u)
        eyes.append(ec)
    # the nose: the bridge from between the brows to a heavy tip, the wings of the nostrils
    nose = smin(cap(sub, P(0, 0.035, 0.2), P(0, -0.065, 0.245), 0.024 * u, 0.034 * u), ell(sub, P(0, -0.082, 0.24), np.array([0.046, 0.034, 0.04]) * u), 0.02 * u)
    for s in (-1, 1):
        nose = smin(nose, ell(sub, P(s * 0.034, -0.09, 0.218), np.array([0.024, 0.022, 0.024]) * u), 0.01 * u)
    sk = smin(sk, nose, 0.012 * u)
    # the mouth: wide, its lips drawn back in a grin, open a little on the teeth
    lips = cap(sub, P(-0.1, -0.152, 0.2), P(0.1, -0.152, 0.2), 0.024 * u, 0.024 * u)
    sk = smin(sk, lips, 0.012 * u)
    mouth = ell(sub, P(0, -0.153, 0.215), np.array([0.095, 0.016, 0.05]) * u)
    sk = smax(sk, -mouth, 0.004 * u)
    # a man's ears at the sides of the head (in the mane)
    for s in (-1, 1):
        sk = smin(sk, ell(sub, P(s * 0.212, 0.0, -0.02), np.array([0.035, 0.068, 0.05]) * u), 0.015 * u)
    S.add(sk, 0.02 * u, sub)
    S.mark("face", sk, sub)
    S.mark("lips", lips, sub)
    S.mark("face_mouth", ell(sub, P(0, -0.153, 0.215), np.array([0.1, 0.024, 0.055]) * u), sub)
    for ec in eyes:
        eb = ell(sub, ec, np.array([0.04, 0.027, 0.03]) * u)
        S.add(eb, 0, sub)
        S.mark("eye_white", eb, sub)
        S.mark("iris", ell(sub, ec + np.array([0, -0.002, 0.022]) * u, np.array([0.026, 0.026, 0.014]) * u), sub)
        sx_ = 1.0 if ec[0] > c[0] else -1.0
        S.mark("brow_hair", cap(sub, ec + np.array([-sx_ * 0.045, 0.052, 0.03]) * u, ec + np.array([sx_ * 0.06, 0.042, 0.012]) * u, 0.016 * u, 0.012 * u), sub)
        S.mark("socket", ell(sub, ec + np.array([0, 0, 0.01]) * u, np.array([0.062, 0.046, 0.05]) * u), sub)
    # the teeth: rows of them, sharp, along both lips and a third behind the upper row
    for row, (yy, zz, dy) in enumerate(((-0.144, 0.205, -1.0), (-0.162, 0.203, 1.0), (-0.146, 0.185, -1.0))):
        n = 9 if row < 2 else 7
        for i in range(n):
            x = -0.084 + 0.168 * i / (n - 1)
            if row == 2:
                x *= 0.8
            a0 = P(x, yy, zz - 1.6 * x * x)
            tooth = cap(sub, a0, a0 + np.array([0, dy * 0.028, 0.002]) * u, max(0.45 * g.cell, 0.008 * u), 0.003)
            S.add(tooth, 0, sub)
            S.mark("tooth", tooth, sub)
    # the beard: from the jaw and the chin down, in locks, into the mane
    lock = vnoise(np.abs(sub.X), sub.Y, sub.Z, 0.035, 47)
    beard = ell(sub, P(0, -0.31, 0.1), np.array([0.19, 0.15, 0.12]) * u)
    beard = smin(beard, cap(sub, P(0, -0.3, 0.13), P(0, -0.5, 0.05), 0.09 * u, 0.02 * u), 0.04 * u)
    beard = smax(beard, -ell(sub, P(0, -0.1, 0.26), np.array([0.13, 0.12, 0.12]) * u), 0.02 * u)
    beard = beard - 0.025 * u * (lock - 0.5)
    S.add(beard, 0.02 * u, sub)
    S.mark("beard", beard, sub)
    S.feat["_face_c"] = c
    S.feat["_face_u"] = u
    return eyes


def manticore(sp, g):
    """The manticore: a great red lion (the lion's own sculpt), its mane black, two sabre fangs down
    over its lip and short horns back from its brow; a bat's wings from its shoulders; for a tail
    a scorpion's, in plates of black chitin arching up over its back, the sting at its end."""
    info = _part_info(sp)
    K = parts_of(sp)
    k = float(K["beastBody"][2][1]) / 0.499
    P = dict(CATS["lion"], fur=0xa3361f, light=0xd9935c, dark=0x5e180e, mane=0x2a0c08, mane2=0x120404, nose=0x2a0e0c, eye=0xf2c41a, ear=0x4a160c, head=1.24)
    d, col, kind, hc, mz, hs = _cat_k(sp, g, P, k, drop=("tail", "tail2", "tail3", "stinger"))
    S = _Shape(g)
    S.d = d
    # A man's face, as the old books have it (user: more human, as in the legends), in the mane.
    face_eyes = _man_face(S, g, hc, hs)
    # Short horns back from the brow, curving up at their tips.
    for n in ("hornL", "hornR"):
        if n not in info:
            continue
        h0, h1 = _limb_ends(info, n)
        tip = h1 + (h1 - h0) * 0.3 + np.array([0.0, 0.12, -0.12])
        rh = float(min(K[n][2][0], K[n][2][2]))
        sub = _around(g, [h0, h1, tip], rh * 2.0 + 0.05)
        hn = smin(cap(sub, h0 - (h1 - h0) * 0.25, h1, rh * 1.3, rh * 0.9), cap(sub, h1, tip, rh * 0.9, 0.01), 0.03)
        S.add(hn, 0.03, sub)
        S.mark("horn", hn, sub)
    # The wings: a bat's (the dragon's), from the shoulders.
    for n in ("wingL", "wingR"):
        if n not in info:
            continue
        R, pos, half, j, s_, par, kids = info[n]
        th = int(np.argmin(half))
        spn = int(np.argmax(half))
        chd = 3 - spn - th
        sv = pos - j
        sv = sv - R[:, chd] * float(sv @ R[:, chd])
        sv = sv / max(np.linalg.norm(sv), 1e-9)
        cv = R[:, chd] if float(R[:, chd][2]) >= 0 else -R[:, chd]
        Ls = float(np.linalg.norm(pos - j)) + float(half[spn])
        _wing_full(S, g, j, sv, cv, Ls * 1.04, float(half[chd]) * 1.05, max(g.cell * 0.6, float(half[th]) * 0.4))
    # The scorpion's tail: out of the rump, arching up and over in plates, the sting at its end.
    pts = []
    for n in ("tail", "tail2", "tail3", "stinger"):
        a, b = _limb_ends(info, n)
        if not pts:
            pts.append(a + np.array([0.0, -0.06, 0.14]))
        pts.append(b)
    path = _catmull(pts, 0.05)
    L_tot = float(sum(np.linalg.norm(path[i + 1] - path[i]) for i in range(len(path) - 1)))
    r0 = float(K["tail"][2][0]) * 0.95
    nseg = 9
    acc = [0.0]
    for i in range(len(path) - 1):
        acc.append(acc[-1] + float(np.linalg.norm(path[i + 1] - path[i])))
    acc = np.array(acc)
    seg_end = 0.86   # (the sting's bulb from here on)
    for si in range(nseg):
        t0 = seg_end * si / nseg
        t1 = seg_end * (si + 1) / nseg
        idx = [i for i in range(len(path)) if t0 * L_tot <= acc[i] <= t1 * L_tot]
        if len(idx) < 2:
            continue
        a, b = path[idx[0]], path[idx[-1]]
        rr = r0 * (1.0 - 0.38 * (si / nseg))
        sub = _around(g, [a, b], rr * 1.4 + 0.05)
        # (each plate swelling between its ends, narrower where it meets the next)
        u = b - a
        Lu = float(np.linalg.norm(u))
        u = u / max(Lu, 1e-9)
        tt = np.clip(((sub.X - a[0]) * u[0] + (sub.Y - a[1]) * u[1] + (sub.Z - a[2]) * u[2]) / max(Lu, 1e-9), 0, 1)
        cx, cy_, cz = a[0] + u[0] * tt * Lu, a[1] + u[1] * tt * Lu, a[2] + u[2] * tt * Lu
        bulge = rr * (0.8 + 0.3 * np.sin(tt * math.pi))
        dd = np.sqrt((sub.X - cx) ** 2 + (sub.Y - cy_) ** 2 + (sub.Z - cz) ** 2) - bulge
        S.add(dd, 0.0, sub)
        S.mark("chitin", dd, sub)
    # the sting: a bulb, then the barb curving forward and down
    i_b = int(np.searchsorted(acc, seg_end * L_tot))
    bulb_c = path[min(i_b + 2, len(path) - 1)]
    end = path[-1]
    du = end - bulb_c
    du = du / max(np.linalg.norm(du), 1e-9)
    rb = r0 * 0.95
    sub = _around(g, [bulb_c - du * rb * 1.5, end + np.array([0, -0.1, 0.45])], rb * 1.6 + 0.08)
    bulb = ell(sub, bulb_c + du * rb * 0.5, (rb * 0.95, rb * 1.1, rb * 0.95))
    S.add(bulb, 0.03, sub)
    S.mark("chitin", bulb, sub)
    b0 = bulb_c + du * rb * 1.4
    b1 = b0 + du * rb * 1.2 + np.array([0.0, 0.0, rb * 0.9])
    b2 = b1 + np.array([0.0, rb * 0.3, rb * 1.3])
    barb = smin(cap(sub, b0, b1, rb * 0.42, rb * 0.22), cap(sub, b1, b2, rb * 0.22, 0.008), 0.02)
    S.add(barb, 0.02, sub)
    S.mark("sting", barb, sub)
    d = S.d
    occ = d < 0
    thr_c = 0.4 * g.cell
    col = np.array(col, copy=True)
    kind = np.array(kind, copy=True)
    # Colours: the chitin black with a red sheen, each plate's edges lighter; the sting black, its
    # barb red-tipped; the wings' membranes dark red, their bones darker; fangs and horns.
    ch = S.on("chitin", 0.03) & occ
    sheen = vnoise(np.abs(g.X), g.Y, g.Z, 0.08, 19)
    col[ch] = np.array([0.16, 0.05, 0.04]) * (0.8 + 0.5 * sheen[ch])[:, None]
    kind[ch] = CHITIN_KIND
    st = S.on("sting", thr_c)
    col[st] = np.array([0.08, 0.03, 0.03])
    kind[st] = CHITIN_KIND
    tipm = st & (np.linalg.norm(np.stack([g.X - b2[0], g.Y - b2[1], g.Z - b2[2]]), axis=0) < rb * 0.6)
    col[tipm] = np.array([0.9, 0.25, 0.05])
    kind[tipm] = GLOW_KIND
    if "membrane" in S.feat:
        wg = S.on("membrane", thr_c)
        vein = vnoise(np.abs(g.X), g.Y, g.Z, 0.12, 5)
        col[wg] = np.array([0.3, 0.06, 0.05]) * (0.8 + 0.4 * vein[wg])[:, None]
        kind[wg] = 2   # (leather, matte: glossy, it shone the sky's blue)
    wb = (S.feat.get("membrane", np.full(g.shape, INF)) >= thr_c) & occ & (np.abs(g.X) > float(K["beastBody"][2][0]) * 1.15) & (g.Y > float(K["beastBody"][1][1]))
    col[wb] = np.array([0.14, 0.04, 0.03])
    kind[wb] = 2
    hk = S.on("horn", thr_c)
    col[hk] = np.array([0.18, 0.14, 0.12])
    kind[hk] = BONE
    ck = S.on("claw", thr_c)
    col[ck] = np.array([0.1, 0.08, 0.07])
    kind[ck] = BONE
    # The face: a man's skin, weathered, ruddy; the lips darker; the beard as black as the mane;
    # the whites of the eyes, the irises pale gold and glowing; the mouth dark inside.
    fc0 = S.on("face", 0.02) & occ
    fcc, fu = S.feat["_face_c"], S.feat["_face_u"]
    hair = fc0 & ((g.Y > fcc[1] + 0.16 * fu) | (g.Z < fcc[2] + 0.04 * fu) | ((g.Y > fcc[1] + 0.1 * fu) & (np.abs(g.X - fcc[0]) > 0.15 * fu)))
    fc = fc0 & ~hair
    shade = vnoise(np.abs(g.X), g.Y, g.Z, 0.06, 53)
    skin = np.array([0.66, 0.4, 0.3])
    col[fc] = skin * (0.86 + 0.24 * shade[fc])[:, None]
    kind[fc] = 0
    sock = S.on("socket", thr_c) & fc
    col[sock] = col[sock] * 0.62
    bh_ = S.on("brow_hair", thr_c) & fc
    col[bh_] = np.array([0.1, 0.035, 0.025])
    lp = S.on("lips", thr_c) & fc
    col[lp] = np.array([0.42, 0.16, 0.13])
    bd = (S.on("beard", 0.02) & occ & ~fc) | hair
    mn = vnoise(np.abs(g.X), g.Y, g.Z, 0.035, 7)
    col[bd] = np.array([0.1, 0.035, 0.025]) * (0.8 + 0.5 * mn[bd])[:, None]
    kind[bd] = FUR
    fm = S.on("face_mouth", thr_c) & occ
    col[fm] = np.array([0.22, 0.04, 0.04])
    kind[fm] = WET
    ew = S.on("eye_white", thr_c)
    col[ew] = np.array([0.88, 0.84, 0.74])
    kind[ew] = WET
    ir = ew & (S.feat["iris"] < thr_c)
    col[ir] = np.array([1.0, 0.78, 0.2])
    kind[ir] = GLOW_KIND
    for ec in face_eyes:
        pupil = ir & (np.abs(g.X - ec[0]) < 0.5 * g.cell) & (np.abs(g.Y - ec[1]) < 0.5 * g.cell)
        col[pupil] = np.array([0.05, 0.02, 0.01])
        kind[pupil] = WET
    th_k = S.on("tooth", thr_c)
    col[th_k] = np.array([0.94, 0.9, 0.8])
    kind[th_k] = BONE
    return d, np.clip(col, 0, 1), kind


SCULPTS["manticore"] = manticore


def _hound_head(S, g, R, pos, half, gape=0.3, key="hound"):
    """A hellhound's head in its box, forward its +z: a broad skull with the brow heavy over deep
    eyes (they glow), the muzzle long and deep, wrinkled back in a snarl, the jaws open on a row of
    teeth with long fangs; the ears pricked and laid back. Returns the eyes' middles."""
    hx, hy, hz = (float(v) for v in half)
    ax, up, f = R[:, 0], R[:, 1], R[:, 2]

    def L(x, y, z):
        return pos + ax * (x * hx) + up * (y * hy) + f * (z * hz)
    sub = _around(g, [L(x, y, z) for x in (-1.3, 1.3) for y in (-1.6, 1.8) for z in (-1.3, 1.25)], 0.05)
    m = min(hx, hy)
    sk = ell_o(sub, L(0, 0.2, -0.32), R, (0.64 * hx, 0.56 * hy, 0.5 * hz))
    for s in (-1, 1):
        sk = smin(sk, ell_o(sub, L(s * 0.42, -0.08, -0.22), R, (0.34 * hx, 0.42 * hy, 0.42 * hz)), 0.06 * hz)
    # the muzzle: long and deep, a little down to the nose; its top wrinkled back
    sk = smin(sk, cap(sub, L(0, 0.05, -0.05), L(0, -0.06, 0.82), 0.42 * hx, 0.28 * hx), 0.08 * hz)
    for s in (-1, 1):
        sk = smin(sk, ell_o(sub, L(s * 0.2, -0.16, 0.5), R, (0.2 * hx, 0.26 * hy, 0.32 * hz)), 0.04 * hz)
    lz = (sub.X - pos[0]) * f[0] + (sub.Y - pos[1]) * f[1] + (sub.Z - pos[2]) * f[2]
    ly = (sub.X - pos[0]) * up[0] + (sub.Y - pos[1]) * up[1] + (sub.Z - pos[2]) * up[2]
    wr = np.where((ly > 0.1 * hy) & (lz > 0.1 * hz) & (lz < 0.6 * hz), np.abs(np.sin(lz / hz * math.pi * 6.0)) * 0.012, 0.0)
    sk = sk + wr
    nose = ell_o(sub, L(0, 0.02, 0.9), R, (0.18 * hx, 0.13 * hy, 0.1 * hz))
    sk = smin(sk, nose, 0.02)
    S.mark(key + "_nose", nose, sub)
    # the lower jaw hung open, the mouth between
    chin = L(0, -0.52 - gape, 0.66)
    jaw = None
    for s in (-1, 1):
        j = cap(sub, L(s * 0.36, -0.3, -0.3), chin + ax * (s * 0.12 * hx), 0.2 * m, 0.13 * m)
        jaw = j if jaw is None else smin(jaw, j, 0.08 * m)
    jaw = smin(jaw, ell_o(sub, L(0, -0.48 - 0.5 * gape, 0.22), R, (0.28 * hx, 0.12 * hy, 0.46 * hz)), 0.05 * m)
    sk = smin(sk, jaw, 0.05 * m)
    mouth = ell_o(sub, L(0, -0.3 - 0.5 * gape, 0.3), R, (0.3 * hx, 0.1 * hy + 0.3 * gape * hy, 0.56 * hz))
    sk = smax(sk, -mouth, 0.02)
    S.mark(key + "_mouth", ell_o(sub, L(0, -0.3 - 0.5 * gape, 0.3), R, (0.34 * hx, 0.14 * hy + 0.3 * gape * hy, 0.6 * hz)), sub)
    # brows heavy over the eyes, the eyes deep in under them
    eyes = []
    for s in (-1, 1):
        ec = L(s * 0.34, 0.22, 0.2)
        er = 0.13 * m
        sk = smax(sk, -ell_o(sub, ec, R, (er * 1.3, er * 0.95, er * 1.25)), 0.01)
        eye = ell_o(sub, ec - f * er * 0.25, R, (er, er * 0.7, er))
        sk = np.minimum(sk, eye)
        S.mark(key + "_eye", eye, sub)
        eyes.append(ec)
        sk = smin(sk, cap(sub, L(s * 0.5, 0.42, 0.04), L(s * 0.18, 0.36, 0.32), 0.12 * m, 0.08 * m), 0.04 * m)
        # the ears: pricked, laid back
        ear = cap(sub, L(s * 0.4, 0.55, -0.45), L(s * 0.55, 1.2, -0.85), 0.22 * hx, 0.02)
        ear = smax(ear, np.abs((sub.X - pos[0]) * f[0] + (sub.Y - pos[1]) * f[1] + (sub.Z - pos[2]) * f[2] + 0.62 * hz) - 0.09 * hz, 0.03)
        sk = smin(sk, ear, 0.04)
    S.add(sk, 0.0, sub)
    S.mark(key, sk, sub)
    # teeth: the fangs long, up and down; a row between
    for s in (-1, 1):
        a0 = L(s * 0.26, -0.24, 0.66)
        fang = cap(sub, a0, a0 - up * (0.32 + 0.4 * gape) * hy + f * 0.03 * hz, max(0.6 * g.cell, 0.06 * m), 0.004)
        S.add(fang, 0, sub)
        S.mark("tooth", fang, sub)
        b0 = L(s * 0.22, -0.46 - gape * 0.9, 0.56)
        fang = cap(sub, b0, b0 + up * (0.22 + 0.3 * gape) * hy + f * 0.02 * hz, max(0.55 * g.cell, 0.05 * m), 0.004)
        S.add(fang, 0, sub)
        S.mark("tooth", fang, sub)
        for i in range(4):
            zz = 0.42 - 0.2 * i
            t0 = L(s * (0.3 + 0.03 * i), -0.25, zz)
            tooth = cap(sub, t0, t0 - up * 0.14 * hy, 0.5 * g.cell, 0.004)
            S.add(tooth, 0, sub)
            S.mark("tooth", tooth, sub)
    return eyes


def cerberus(sp, g):
    """The hound of the underworld: a great hound, deep in the chest, its haunches heavy; three
    heads on three thick necks out of its shoulders, each snarling, its jaws open on long fangs,
    its eyes glowing red; a collar of iron spikes round the three; a ridge of black bristles down
    its back; for a tail a serpent. Black, its chest and legs rust-dark."""
    info = _part_info(sp)
    K = parts_of(sp)
    _, body, bh = K["beastBody"]
    W, H, Lz = (float(v) for v in bh)
    cy, zc = float(body[1]), float(body[2])
    ground = min(float(K[n][1][1] - K[n][2][1]) for n in K if n.startswith("leg") and n.endswith("Lo"))
    S = _Shape(g)
    # The trunk: the chest deep and broad, the waist tucked up, the haunches heavy.
    S.add(ell(g, (0, cy - 0.04 * H, zc + 0.45 * Lz), (0.84 * W, 0.92 * H, 0.56 * Lz)))
    S.add(ell(g, (0, cy + 0.14 * H, zc - 0.12 * Lz), (0.7 * W, 0.7 * H, 0.6 * Lz)), 0.28)
    S.add(ell(g, (0, cy + 0.08 * H, zc - 0.62 * Lz), (0.76 * W, 0.78 * H, 0.4 * Lz)), 0.28)
    for sx in (-1, 1):
        S.add(ell(g, (sx * 0.5 * W, cy + 0.3 * H, zc + 0.55 * Lz), (0.34 * W, 0.5 * H, 0.32 * Lz)), 0.18)
        S.add(ell(g, (sx * 0.5 * W, cy - 0.02 * H, zc - 0.62 * Lz), (0.4 * W, 0.66 * H, 0.36 * Lz)), 0.2)
    trunk = np.array(S.d, copy=True)
    # The legs: a hound's, long and muscled, the hind bent at the hock, broad paws with claws.
    for fb in ("F", "B"):
        for side in ("L", "R"):
            up_n, lo_n = "leg%s%s" % (fb, side), "leg%s%sLo" % (fb, side)
            if up_n not in info or lo_n not in info:
                continue
            ja = info[up_n][3]
            _, foot_end = _limb_ends(info, lo_n)
            x, zj = float(ja[0]), float(ja[2])
            sx = 1.0 if x > 0 else -1.0
            r = float(min(K[up_n][2][0], K[up_n][2][2])) * 0.8
            if fb == "F":
                sh_ = np.array([x * 0.98, cy + 0.05 * H, zj - 0.05])
                el = np.array([x * 1.04, ground + 0.62 * (cy - ground), zj - 0.12])
                wr = np.array([x * 1.0, ground + 0.24, zj + 0.06])
                S.add(cap(g, sh_, el, r * 1.15, r * 0.8), 0.2)
                S.add(ell(g, (x * 1.04, (sh_[1] + el[1]) * 0.5, zj - 0.02), (r * 0.9, r * 1.5, r * 1.0)), 0.18)
                S.add(cap(g, el, wr, r * 0.72, r * 0.5), 0.12)
            else:
                hp_ = np.array([x * 0.96, cy, zj + 0.04])
                kn = np.array([x * 1.04, ground + 0.62 * (cy - ground), zj + 0.3])
                hk = np.array([x * 1.0, ground + 0.36, zj - 0.22])
                wr = np.array([x * 1.0, ground + 0.24, zj - 0.12])
                S.add(ell(g, (x * 1.0, cy - 0.35 * H, zj + 0.08), (r * 1.25, r * 2.0, r * 1.6)), 0.25)
                S.add(cap(g, hp_, kn, r * 1.1, r * 0.75), 0.2)
                S.add(cap(g, kn, hk, r * 0.72, r * 0.48), 0.12)
                S.add(cap(g, hk, wr, r * 0.5, r * 0.5), 0.08)
            # the paw: a pad and four toes, a claw on each
            pc = np.array([x, ground + r * 0.42, wr[2] + 0.12])
            sub = _around(g, [pc - np.array([r * 1.5, r, r * 1.5]), pc + np.array([r * 1.5, r * 1.2, r * 2.6])], 0.05)
            paw = ell(sub, pc, (r * 0.95, r * 0.5, r * 1.15))
            S.add(cap(g, wr, pc + np.array([0, r * 0.2, 0]), r * 0.5, r * 0.6), 0.08)
            for tx in (-0.6, -0.2, 0.2, 0.6):
                tc = pc + np.array([tx * r * 1.05, -r * 0.08, r * (1.0 - 0.25 * abs(tx))])
                paw = smin(paw, ell(sub, tc, (r * 0.3, r * 0.34, r * 0.38)), 0.03)
                cl = cap(sub, tc + np.array([0, 0.0, r * 0.25]), tc + np.array([0, -r * 0.3, r * 0.62]), r * 0.13, 0.006)
                S.add(cl, 0, sub)
                S.mark("claw", cl, sub)
            S.add(paw, 0.05, sub)
    # The necks: the middle one out of the chest, the outer two out of the shoulders, thick.
    heads = []
    for nk, hd in (("neckL", "headL"), ("neckR", "headR"), (None, "beastHead")):
        Rh, hp, hh = K[hd]
        jh = info[hd][3]
        if nk is not None:
            jn = info[nk][3]
            base = np.array([jn[0] * 0.8, jn[1] - 0.15, jn[2] - 0.1])
        else:
            base = np.array([0.0, cy + 0.2 * H, zc + 0.72 * Lz])
        mid = (base + jh) * 0.5 + np.array([0.0, 0.08, -0.04])
        pts = _catmull([base, mid, jh + Rh[:, 2] * 0.1], 0.08)
        rn = float(hh[0]) * 0.62
        _tube(S, g, pts, [rn * (1.25 - 0.3 * i / (len(pts) - 1)) for i in range(len(pts))], 1.0, 0.16, key="neck")
        heads.append((Rh, hp, hh))
    eyes = []
    for Rh, hp, hh in heads:
        eyes += _hound_head(S, g, Rh, hp, hh, 0.32)
    # The collar: a band of iron round the roots of the three necks, spiked.
    Rc, cpos, chalf = K["collar"]
    sub = _around(g, [cpos - chalf * 1.6, cpos + chalf * 1.6 + np.array([0, 0.2, 0.2])], 0.1)
    band = smax(np.abs(ell(sub, cpos + np.array([0, 0.04, -0.12]), (chalf[0] * 1.05, chalf[1] * 1.6, chalf[2] * 4.2))) - 0.04, np.abs(sub.Y - cpos[1] - 0.04) - chalf[1] * 0.55, 0.02)
    S.add(band, 0.0, sub)
    S.mark("collar", band, sub)
    for i in range(9):
        a = -1.25 + 2.5 * i / 8
        dirv = np.array([math.sin(a), 0.0, math.cos(a)])
        p0 = cpos + np.array([0, 0.04, -0.12]) + np.array([chalf[0] * 1.05 * math.sin(a), 0.0, chalf[2] * 4.2 * math.cos(a)])
        sub2 = _around(g, [p0, p0 + dirv * 0.22], 0.08)
        spk = cap(sub2, p0 - dirv * 0.02, p0 + dirv * 0.22, 0.055, 0.008)
        S.add(spk, 0.0, sub2)
        S.mark("spike", spk, sub2)
    # The ridge of bristles down the back from the withers, in tufts.
    tuft = vnoise(np.abs(g.X), g.Y, g.Z, 0.05, 29)
    rg = cap(g, (0, cy + 0.82 * H, zc + 0.55 * Lz), (0, cy + 0.72 * H, zc - 0.55 * Lz), 0.16 * W, 0.08 * W) - 0.08 * (tuft - 0.3)
    rg = np.maximum(rg, np.abs(g.X) - 0.12 * W)
    S.add(rg, 0.04)
    S.mark("ridge", rg)
    # The tail: a serpent out of the rump, its head raised.
    ta, tb = _limb_ends(info, "tail")
    u = (tb - ta) / np.linalg.norm(tb - ta)
    rt = float(K["tail"][2][0]) * 0.75
    tpts = _catmull([ta + np.array([0, -0.06, 0.12]), ta + (tb - ta) * 0.5 + np.array([0, -0.12, 0]), tb + np.array([0.0, 0.05, -0.25]), tb + np.array([0.0, 0.42, -0.42])], 0.06)
    _tube(S, g, tpts, [rt * (1.1 - 0.5 * i / (len(tpts) - 1)) for i in range(len(tpts))], 1.0, 0.06, key="serpent")
    hdir = tpts[-1] - tpts[-3]
    hdir = hdir / np.linalg.norm(hdir)
    fwd = np.array([0.0, 0.25, 1.0])
    fwd = fwd / np.linalg.norm(fwd)   # (it looks forward, over the back)
    side = np.array([1.0, 0.0, 0.0])
    upv = np.cross(fwd, side)
    if upv[1] < 0:
        upv = -upv
    Rs = np.stack([side, upv, fwd], axis=1)
    sh_ = np.array([rt * 1.6, rt * 1.2, rt * 2.2])
    _snake_head(S, g, Rs, tpts[-1] + fwd * sh_[2] * 0.6, sh_, 0.35, "snake")
    d = S.d
    occ = d < 0
    thr_c = 0.4 * g.cell
    # Colours: black fur, rust-dark on the chest, the belly and the legs inside; the bristles
    # tipped red; the eyes glowing red; the mouths dark red; the teeth; the iron collar, its spikes
    # bright; the serpent dark green.
    black = np.array([0.075, 0.068, 0.068])
    rust = np.array([0.24, 0.1, 0.06])
    col = np.zeros(g.shape + (3,))
    clump = vnoise(np.abs(g.X), g.Y, g.Z, 0.05, 41)
    fine = hash3(np.floor(np.abs(g.X) / g.cell), np.floor(g.Y / g.cell), np.floor(g.Z / g.cell), 43)
    col[:] = black
    col = col * (0.8 + 0.45 * clump[..., None] + 0.25 * fine[..., None])
    under = np.clip((cy - 0.3 * H - g.Y) / (0.6 * H), 0, 1) * (trunk < 0.4)
    inner = np.clip(1.0 - np.abs(g.X) / (0.75 * W), 0, 1) * (g.Y < cy - 0.2 * H)
    chest = np.clip(((g.Z - (zc + 0.5 * Lz)) / (0.5 * Lz)), 0, 1) * np.clip((cy + 0.2 * H - g.Y) / H, 0, 1)
    rk = np.clip(np.maximum(np.maximum(under, inner * 0.6), chest * 0.8), 0, 1)[..., None] * 0.75
    col = col * (1 - rk) + rust * (0.8 + 0.4 * clump[..., None]) * rk
    kind = np.full(g.shape, FUR, np.uint8)
    rgm = S.on("ridge", 0.02) & occ
    col[rgm] = black * 0.8
    tips = rgm & (tuft > 0.62)
    col[tips] = np.array([0.4, 0.08, 0.04])
    sn = (S.on("serpent", 0.03) | S.on("snake", thr_c)) & occ
    scol = np.zeros(g.shape + (3,))
    scol[:] = np.array([0.1, 0.18, 0.1])
    scol = _scales(g, scol, 0.05)
    col[sn] = scol[sn]
    kind[sn] = SCALE_KIND
    cm = S.on("collar", thr_c)
    col[cm] = np.array([0.2, 0.19, 0.18])
    kind[cm] = 3
    stud = cm & (np.abs(((np.arctan2(g.X - cpos[0], g.Z - cpos[2] + 0.12) / 0.35) % 1.0) - 0.5) > 0.38)
    col[stud] = np.array([0.62, 0.45, 0.22])
    kind[stud] = 4
    sk_ = S.on("spike", thr_c)
    col[sk_] = np.array([0.55, 0.55, 0.56])
    kind[sk_] = 3
    for key in ("hound_mouth", "snake_mouth"):
        mo = S.on(key, thr_c) & occ
        col[mo] = np.array([0.42, 0.06, 0.06])
        kind[mo] = WET
    ns = (S.feat.get("hound_nose", np.full(g.shape, INF)) < thr_c) & occ
    col[ns] = np.array([0.03, 0.025, 0.025])
    kind[ns] = WET
    th = S.on("tooth", thr_c)
    col[th] = np.array([0.92, 0.88, 0.76])
    kind[th] = BONE
    ck = S.on("claw", thr_c)
    col[ck] = np.array([0.12, 0.1, 0.09])
    kind[ck] = BONE
    for key in ("hound_eye", "snake_eye"):
        ey = S.on(key, thr_c)
        col[ey] = np.array([1.0, 0.22, 0.05]) if key == "hound_eye" else np.array([0.95, 0.8, 0.12])
        kind[ey] = GLOW_KIND
    return d, np.clip(col, 0, 1), kind


SCULPTS["cerberus"] = cerberus


def python(sp, g):
    """A giant python: one long body of muscle lying in an S of coils, round and heavy, flat on its
    belly; its neck a little raised under a wedge of a head, broad behind, the snout rounded, the
    mouth shut on its long line, pits along the lip, eyes at the sides; its forked tongue out. Tan
    with dark blotches edged in black down its length, an arrow on its crown, the belly cream."""
    info = _part_info(sp)
    K = parts_of(sp)
    _, body, bh = K["beastBody"]
    W, H, Lz = (float(v) for v in bh)
    cy, zc = float(body[1]), float(body[2])
    S = _Shape(g)
    # The coils: one smooth S through the body and the coils' joints to the tip of the tail.
    path = [np.array([0.0, cy, zc + 0.85 * Lz]), np.array([0.0, cy, zc])]
    for n in ("coil1", "coil2", "tailTip"):
        if n in info:
            a, b = _limb_ends(info, n)
            path.append(np.array([a[0], cy, a[2]]))
            if n == "tailTip":
                path.append(np.array([b[0], cy, b[2]]))
    clean = [path[0]]
    for p in path[1:]:
        if np.linalg.norm(p - clean[-1]) > 0.15:
            clean.append(p)
    curve = _catmull(clean, 0.08)
    n = len(curve)
    r0 = 0.9 * H
    rads = [r0 * (1.0 if i / (n - 1) < 0.45 else max(0.1, 1.0 - (i / (n - 1) - 0.45) / 0.55 * 0.92)) for i in range(n)]
    curve = [np.array([p[0], (cy - H) + r * 0.95, p[2]]) for p, r in zip(curve, rads)]
    _tube(S, g, curve, rads, flat=1.15, k=0.05, key="coils")
    coils = np.array(S.d, copy=True)
    # The neck, a little raised, into the back of the head.
    Rh, hp, hh = K["beastHead"]
    jh = info["beastHead"][3]
    npts = _catmull([np.array([0.0, cy, zc + 0.75 * Lz]), np.array([0.0, (cy + jh[1]) * 0.5 + 0.03, (zc + 0.75 * Lz + jh[2]) * 0.5]), jh + Rh[:, 2] * 0.06], 0.06)
    _tube(S, g, npts, [r0 * (1.0 - 0.22 * i / (len(npts) - 1)) for i in range(len(npts))], 1.1, 0.08, key="neck")
    # The head: a wedge, broad behind where the jaws hinge, the snout rounded; the mouth shut.
    hx, hy, hz = (float(v) for v in hh)
    ax_, up, f = Rh[:, 0], Rh[:, 1], Rh[:, 2]

    def L(x, y, z):
        return hp + ax_ * (x * hx) + up * (y * hy) + f * (z * hz)
    sub = _around(g, [L(x, y, z) for x in (-1.3, 1.3) for y in (-1.4, 1.4) for z in (-1.3, 1.3)], 0.05)
    m = min(hx, hy)
    sk = ell_o(sub, L(0, 0.04, -0.4), Rh, (0.82 * hx, 0.7 * hy, 0.52 * hz))
    for zz, wx, wy in ((0.05, 0.66, 0.6), (0.45, 0.52, 0.5), (0.78, 0.4, 0.42), (0.92, 0.34, 0.36)):
        sk = smin(sk, ell_o(sub, L(0, 0.0, zz), Rh, (wx * hx, wy * hy, 0.26 * hz)), 0.1 * hz)
    for s in (-1, 1):
        sk = smin(sk, ell_o(sub, L(s * 0.5, -0.2, -0.55), Rh, (0.36 * hx, 0.44 * hy, 0.36 * hz)), 0.06 * hz)
    eyes = []
    for s in (-1, 1):
        ec = L(s * 0.6, 0.24, 0.12)
        er = 0.14 * m
        eye = ell_o(sub, ec - ax_ * (s * er * 0.25), Rh, (er, er * 0.85, er * 1.05))
        sk = np.minimum(sk, eye)
        S.mark("eye", eye, sub)
        eyes.append(ec)
        # (the pits along the upper lip)
        for i in range(4):
            pit = ell_o(sub, L(s * (0.5 - 0.06 * i), -0.18, 0.72 - 0.16 * i), Rh, (0.06 * hx, 0.05 * hy, 0.05 * hz))
            sk = smax(sk, -pit, 0.005)
            S.mark("pit", pit, sub)
    S.add(sk, 0.04, sub)
    S.mark("head", sk, sub)
    S.feat["_eyes"] = eyes
    lx = (sub.X - hp[0]) * ax_[0] + (sub.Y - hp[1]) * ax_[1] + (sub.Z - hp[2]) * ax_[2]
    ly = (sub.X - hp[0]) * up[0] + (sub.Y - hp[1]) * up[1] + (sub.Z - hp[2]) * up[2]
    lz = (sub.X - hp[0]) * f[0] + (sub.Y - hp[1]) * f[1] + (sub.Z - hp[2]) * f[2]
    seam = np.abs(ly / hy + 0.28 - 0.06 * lz / hz) * hy - 0.35 * g.cell
    seam = np.where((lz > -0.75 * hz) & ((np.abs(lx) > 0.2 * hx) | (lz > 0.75 * hz)), seam, INF)
    S.mark("mouth", seam, sub)
    # The tongue: out along its own part, forked at the end, dark.
    if "tongue" in info:
        t0, t1 = _limb_ends(info, "tongue")
        tr = max(0.55 * g.cell, 0.03 * m)
        sub2 = _around(g, [t0, t1], 0.12)
        u = (t1 - t0) / max(np.linalg.norm(t1 - t0), 1e-6)
        side = np.cross(up, u)
        side = side / max(np.linalg.norm(side), 1e-6)
        tg = cap(sub2, t0 - u * 0.05, t1 - u * 0.03, tr, tr)
        for s in (-1, 1):
            tg = np.minimum(tg, cap(sub2, t1 - u * 0.04, t1 + u * 0.05 + side * (s * 0.05), tr, tr * 0.8))
        S.add(tg, 0.0, sub2)
        S.mark("tongue", tg, sub2)
    d = S.d
    occ = d < 0
    thr_c = 0.4 * g.cell
    # Colours: tan, the blotches dark brown edged in black (by the noise of its length), the belly
    # cream; the head's arrow; eyes amber with a slit; the tongue dark.
    tan = np.array([0.62, 0.5, 0.3])
    brown = np.array([0.28, 0.18, 0.09])
    black = np.array([0.06, 0.045, 0.03])
    cream = np.array([0.86, 0.8, 0.62])
    col = np.zeros(g.shape + (3,))
    col[:] = tan
    bl = vnoise(np.abs(g.X) * 0.6, g.Y, g.Z, 0.16, 61)
    blot = bl > 0.56
    edge = (bl > 0.5) & ~blot
    col[blot] = brown
    col[edge] = black
    col = _scales(g, col, 0.045)
    belly = (g.Y < cy - 0.55 * H) & (coils < 0.5 * g.cell)
    col[belly] = cream * (0.9 + 0.1 * vnoise(g.X, g.Y, g.Z, 0.05, 3)[belly])[:, None]
    hd = S.on("head", 0.02) & occ
    hcol = np.where(((np.abs((g.X - hp[0])) < 0.18 * hx + 0.3 * np.clip((hp[2] - g.Z) / hz, 0, 1) * hx) & (g.Y > hp[1] + 0.2 * hy))[..., None], brown, tan)
    col[hd] = hcol[hd] * (0.92 + 0.12 * vnoise(g.X, g.Y, g.Z, 0.04, 9)[hd])[:, None]
    under = hd & (g.Y < hp[1] - 0.3 * hy)
    col[under] = cream
    kind = np.full(g.shape, SCALE_KIND, np.uint8)
    pt = S.on("pit", thr_c) & occ
    col[pt] = black
    mo = S.on("mouth", thr_c) & occ
    col[mo] = np.array([0.12, 0.07, 0.05])
    tg_ = S.on("tongue", thr_c)
    col[tg_] = np.array([0.18, 0.06, 0.07])
    kind[tg_] = WET
    ey = S.on("eye", thr_c)
    col[ey] = np.array([0.78, 0.5, 0.12])
    kind[ey] = WET
    _slits(S, g, ey, Rh, hh, col)
    return d, np.clip(col, 0, 1), kind


SCULPTS["python"] = python


def ostrich(sp, g):
    """An ostrich: the body a deep egg of black plumage, the wings' white plumes drooped over its
    sides and a white plume for a tail; a long bare neck in a curve to a small head, great dark
    eyes under lashes, a broad flat beak; the drumsticks bare and thick, the shins long and scaled,
    two toes to a foot, the inner one great with a hoof of a claw."""
    info = _part_info(sp)
    K = parts_of(sp)
    _, body, bh = K["beastBody"]
    W, H, Lz = (float(v) for v in bh)
    cy, zc = float(body[1]), float(body[2])
    ground = min(float(K[n][1][1] - K[n][2][1]) for n in K if n.startswith("leg") and n.endswith("Lo"))
    S = _Shape(g)
    fluff = vnoise(np.abs(g.X), g.Y, g.Z, 0.035, 71)
    fluff2 = vnoise(np.abs(g.X), g.Y, g.Z, 0.016, 73)
    # The body: an egg, its breast forward and high, its rump round; the plumage in loose tufts.
    bd = ell(g, (0, cy + 0.02, zc + 0.04), (1.1 * W, 1.0 * H, 1.08 * Lz))
    bd = smin(bd, ell(g, (0, cy + 0.06, zc + 0.5 * Lz), (0.85 * W, 0.85 * H, 0.6 * Lz)), 0.06)
    bd = smin(bd, ell(g, (0, cy - 0.02, zc - 0.55 * Lz), (0.95 * W, 0.9 * H, 0.55 * Lz)), 0.06)
    bd = bd - 0.035 * (fluff - 0.5) - 0.018 * (fluff2 - 0.5)
    S.add(bd)
    S.mark("plumage", bd)
    # The wings' plumes, drooped over the sides; the tail's plume behind.
    for n in ("wingL", "wingR"):
        if n not in info:
            continue
        a, b = _limb_ends(info, n)
        sx = 1.0 if a[0] > 0 else -1.0
        c = (a + b) * 0.5 + np.array([sx * 0.0, -0.04, -0.08])
        sub = _around(g, [c], 0.42)
        # (plumes hanging in strands: the noise long up and down)
        strands = vnoise(np.abs(sub.X) * 1.0, sub.Y * 0.35, sub.Z, 0.022, 75)
        wp = ell(sub, c, (0.075, 0.17, 0.34)) - 0.04 * (strands - 0.5)
        wp = smax(wp, -ell(sub, c + np.array([-sx * 0.12, 0.0, 0.0]), (0.12, 0.3, 0.45)), 0.02)
        S.add(wp, 0.04, sub)
        S.mark("plume", wp, sub)
    if "plume" in info:
        a, b = _limb_ends(info, "plume")
        c = (a + b) * 0.5 + np.array([0.0, -0.04, -0.06])
        sub = _around(g, [c], 0.42)
        strands = vnoise(np.abs(sub.X), sub.Y * 0.4, sub.Z, 0.022, 77)
        tp = ell(sub, c, (0.17, 0.15, 0.13)) - 0.04 * (strands - 0.5)
        S.add(tp, 0.05, sub)
        S.mark("plume", tp, sub)
    # The neck: bare, long, in a curve forward and up to the head; a ruff of white at its root.
    jn0, jn1 = _limb_ends(info, "neck")
    Rh, hp, hh = K["beastHead"]
    jh = info["beastHead"][3]
    npts = _catmull([np.array([0.0, cy + 0.12, zc + 0.62 * Lz]), jn0 + np.array([0.0, 0.18, 0.06]), (jn0 + jh) * 0.5 + np.array([0.0, 0.05, 0.06]), jh - np.array([0.0, 0.03, 0.0])], 0.04)
    rr = float(K["neck"][2][0])
    _tube(S, g, npts, [rr * (1.15 - 0.45 * i / (len(npts) - 1)) for i in range(len(npts))], 1.0, 0.04, key="neck")
    sub = _around(g, [npts[0]], 0.3)
    ruff = ell(sub, npts[0] + np.array([0.0, 0.06, 0.02]), (0.13, 0.11, 0.12)) - 0.03 * (vnoise(np.abs(sub.X), sub.Y, sub.Z, 0.02, 79) - 0.5)
    S.add(ruff, 0.03, sub)
    S.mark("plume", ruff, sub)
    # The head: small and round, great eyes, the beak broad and flat.
    hx, hy, hz = (float(v) for v in hh)
    ax_, up, f = Rh[:, 0], Rh[:, 1], Rh[:, 2]

    def L(x, y, z):
        return hp + ax_ * (x * hx) + up * (y * hy) + f * (z * hz)
    sub = _around(g, [L(x, y, z) for x in (-1.3, 1.3) for y in (-1.3, 1.3) for z in (-1.3, 1.8)], 0.04)
    sk = ell_o(sub, L(0, 0.1, -0.25), Rh, (0.72 * hx, 0.72 * hy, 0.6 * hz))
    beak = ell_o(sub, L(0, -0.12, 0.62), Rh, (0.5 * hx, 0.2 * hy, 0.62 * hz))
    beak = smax(beak, -ell_o(sub, L(0, -0.12, 1.32), Rh, (0.8 * hx, 0.5 * hy, 0.12 * hz)), 0.01)
    sk = smin(sk, beak, 0.03)
    S.mark("beak", beak, sub)
    eyes = []
    for s in (-1, 1):
        ec = L(s * 0.55, 0.22, -0.02)
        er = 0.24 * min(hx, hy)
        eye = ell_o(sub, ec, Rh, (er * 0.8, er, er))
        sk = np.minimum(sk, eye)
        S.mark("eye", eye, sub)
        eyes.append(ec)
    S.add(sk, 0.02, sub)
    S.mark("head", sk, sub)
    # The legs: the drumstick bare and thick out of the plumage, bending back at the ankle; the
    # shin long and scaled; two toes, the inner great with its claw, the outer small.
    for side in ("L", "R"):
        up_n, lo_n = "legF%s" % side, "legF%sLo" % side
        if up_n not in info or lo_n not in info:
            continue
        j0, j1 = _limb_ends(info, up_n)
        _, j2 = _limb_ends(info, lo_n)
        sx = 1.0 if j0[0] > 0 else -1.0
        r = float(K[up_n][2][0])
        hip = np.array([j0[0] * 1.05, cy - 0.12, zc - 0.02])
        ank = np.array([j1[0], j1[1], j1[2] - 0.05])
        foot = np.array([j2[0], ground + 0.05, j2[2] + 0.02])
        S.add(ell(g, (j0[0] * 1.05, (hip[1] + ank[1]) * 0.5 + 0.12, zc - 0.03), (r * 1.25, r * 2.6, r * 1.45)), 0.08)
        S.add(cap(g, hip, ank, r * 1.0, r * 0.5), 0.06)
        S.mark("thigh", cap(g, hip, ank, r * 1.25, r * 0.55))
        S.add(ell(g, ank, (r * 0.55, r * 0.6, r * 0.6)), 0.03)
        shin = cap(g, ank, foot, r * 0.42, r * 0.36)
        S.add(shin, 0.03)
        S.mark("shin", shin)
        sub = _around(g, [foot + np.array([0, 0, 0.1])], 0.25)
        big = cap(sub, foot, foot + np.array([sx * -0.015, -0.03, 0.17]), r * 0.42, r * 0.3)
        small = cap(sub, foot + np.array([sx * 0.03, 0.0, 0.0]), foot + np.array([sx * 0.07, -0.03, 0.11]), r * 0.3, r * 0.2)
        S.add(np.minimum(big, small), 0.02, sub)
        S.mark("shin", np.minimum(big, small), sub)
        cl = cap(sub, foot + np.array([sx * -0.015, -0.03, 0.16]), foot + np.array([sx * -0.015, -0.05, 0.22]), r * 0.3, r * 0.08)
        S.add(cl, 0.0, sub)
        S.mark("claw", cl, sub)
    d = S.d
    occ = d < 0
    thr_c = 0.4 * g.cell
    # Colours: the plumage black with a brown sheen in its tufts; the plumes white; the neck and
    # head grey with pink under the down; the thighs and shins pink, the shins scaled; the beak
    # horn; the eyes dark brown with lashes over them.
    col = np.zeros(g.shape + (3,))
    col[:] = np.array([0.075, 0.065, 0.06]) * (0.75 + 0.5 * fluff2[..., None])
    kind = np.full(g.shape, FUR, np.uint8)
    pl = S.on("plume", 0.025) & occ
    col[pl] = np.array([0.93, 0.92, 0.88]) * (0.85 + 0.2 * fluff2[pl])[:, None]
    tips = pl & (fluff2 > 0.78)
    col[tips] = np.array([0.55, 0.52, 0.5])
    bare = (S.on("neck", 0.02) | S.on("head", 0.02)) & occ & ~pl
    col[bare] = np.array([0.66, 0.56, 0.54]) * (0.9 + 0.15 * fluff[bare])[:, None]
    kind[bare] = 0
    th = S.on("thigh", 0.02) & occ & ~pl
    col[th] = np.array([0.82, 0.56, 0.5])
    kind[th] = 0
    sh = S.on("shin", thr_c) & occ & ~th
    scl = np.abs(((g.Y) / 0.035) % 1.0 - 0.5) > 0.38
    col[sh] = np.array([0.74, 0.58, 0.52]) * np.where(scl[sh], 0.8, 1.0)[:, None]
    kind[sh] = SCALE_KIND
    bk = S.on("beak", thr_c) & occ
    col[bk] = np.array([0.8, 0.68, 0.56])
    kind[bk] = BONE
    ck = S.on("claw", thr_c)
    col[ck] = np.array([0.22, 0.2, 0.18])
    kind[ck] = BONE
    ey = S.on("eye", thr_c)
    col[ey] = np.array([0.14, 0.08, 0.05])
    kind[ey] = WET
    for ec in eyes:
        lash = ey & (g.Y > ec[1] + 0.012) & (np.abs(g.Z - ec[2]) < 0.025)
        col[lash] = np.array([0.03, 0.02, 0.02])
    return d, np.clip(col, 0, 1), kind


SCULPTS["ostrich"] = ostrich
