#!/usr/bin/env python3
"""The beasts in the new look (drawing only): each beast sculpted over its own parts
(tools/beast_sculpts.py) laid on its voxels. For every part the fine cells of the sculpt's skin
(half the size of the part's voxels) that lie nearer its voxels than any other part's, each over
the voxel of the part nearest it (it goes with it when that voxel is cut away), its colour and its
kind the sculpt's own; its shade (a crease darker, a ridge lighter) and its corners' shading; and
for every voxel which of its eight half-size cells are inside the beast and how deep (what a wound
opens on: the hide, the fat under it, the flesh). The game draws them with FineBody. The voxels,
their places, every collider and what a blow does are the beast's own, untouched.

    python3 tools/gen_fine_beasts.py data/fine_beasts [species...]

One file a sculpted beast (data/fine_beasts/<species>.json), read the first time one is drawn.
numpy."""
import base64, json, os, sys, math
import numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import beast_sculpts as BS

RES = 2
MARGIN = 16          # fine cells round a part's grid its sculpt may reach to (a mane, a paw)
PAD = 10             # cells round the beast on the sculpt's grid
CELL = 9             # a cell's numbers: ix, iy, iz (fine, from the part's corner), cx, cy, cz (its voxel), shade, ao, paint
OWN = 1 << 30        # paint: a colour (0xRRGGBB) and a kind (bits 24..29) of its own (FineBody.OWN_COLOUR)
AO_FACES = [((1, 0, 0), 1, 2), ((-1, 0, 0), 1, 2), ((0, 1, 0), 0, 2), ((0, -1, 0), 0, 2), ((0, 0, 1), 0, 1), ((0, 0, -1), 0, 1)]
KERNEL = np.array([1.0, 4.0, 6.0, 4.0, 1.0]) / 16.0
N26 = [(dx, dy, dz) for dx in (-1, 0, 1) for dy in (-1, 0, 1) for dz in (-1, 0, 1) if (dx, dy, dz) != (0, 0, 0)]


def _shift(a, d, fill=0):
    out = np.full_like(a, fill)
    src = [slice(None)] * 3
    dst = [slice(None)] * 3
    for ax in range(3):
        k = d[ax]
        if k > 0:
            src[ax] = slice(0, -k)
            dst[ax] = slice(k, None)
        elif k < 0:
            src[ax] = slice(-k, None)
            dst[ax] = slice(0, k)
    out[tuple(dst)] = a[tuple(src)]
    return out


def _blur(f, passes=1):
    for _ in range(passes):
        for ax in range(3):
            g = np.zeros_like(f)
            for i, w in enumerate(KERNEL):
                g += w * np.roll(f, i - 2, axis=ax)
            f = g
    return f


def world_grid(sp):
    """A grid round the whole beast at rest, half its voxels' size."""
    v = min(0.0275 * float(p["scale"]) for p in sp["parts"])
    h = v / RES
    corners = []
    for p in sp["parts"]:
        R = BS.quat_m(p["rot"])
        pos = np.array(p["pos"], float)
        half = np.array(p["grid"]) * 0.0275 * float(p["scale"]) * 0.5
        for sx in (-1, 1):
            for sy in (-1, 1):
                for sz in (-1, 1):
                    corners.append(pos + R @ (half * np.array([sx, sy, sz])))
    corners = np.array(corners)
    lo = corners.min(0) - PAD * h
    n = np.ceil((corners.max(0) + PAD * h - lo) / h).astype(int)
    # Even across and centred on the beast's middle (x 0): its left and right sampled alike, so an
    # eye, a nostril, a stripe is the mirror of the other (user: the lion's eyes were not alike).
    half_x = max(abs(corners[:, 0].min()), abs(corners[:, 0].max())) + PAD * h
    nx = int(np.ceil(half_x / h)) * 2
    lo[0] = -nx * h * 0.5
    n[0] = nx
    return BS.Grid(lo, n, h)


def labels(sp, g):
    """Every cell of the grid: the part and the voxel of the beast's nearest voxel (its own where
    it lies in one; spread out from them a ring at a time)."""
    N = g.shape
    own = np.full(N, -1, np.int32)
    vid = np.full(N, -1, np.int64)
    best = np.full(N, np.inf, np.float32)
    for pi, p in enumerate(sp["parts"]):
        gp = np.array(p["grid"], int)
        v = 0.0275 * float(p["scale"])
        R = BS.quat_m(p["rot"])
        pos = np.array(p["pos"], float)
        occ = np.zeros(tuple(gp), bool)
        for q in p["voxels"]:
            occ[q[0], q[1], q[2]] = True
        half = gp * v * 0.5
        cs = []
        for sx in (-1, 1):
            for sy in (-1, 1):
                for sz in (-1, 1):
                    cs.append(pos + R @ (half * np.array([sx, sy, sz])))
        cs = np.array(cs)
        a = np.maximum(np.floor((cs.min(0) - g.lo) / g.cell).astype(int) - 1, 0)
        b = np.minimum(np.ceil((cs.max(0) - g.lo) / g.cell).astype(int) + 1, N)
        ii = np.stack(np.meshgrid(np.arange(a[0], b[0]), np.arange(a[1], b[1]), np.arange(a[2], b[2]), indexing="ij"), -1).reshape(-1, 3)
        w = g.lo + (ii + 0.5) * g.cell
        f = ((w - pos) @ R) / v + gp * 0.5
        vi = np.floor(f).astype(int)
        ok = np.all((vi >= 0) & (vi < gp), 1)
        ii, vi, f = ii[ok], vi[ok], f[ok]
        ok = occ[vi[:, 0], vi[:, 1], vi[:, 2]]
        ii, vi, f = ii[ok], vi[ok], f[ok]
        dc = ((f - vi - 0.5) ** 2).sum(1).astype(np.float32)
        better = dc < best[ii[:, 0], ii[:, 1], ii[:, 2]]
        ii, vi, dc = ii[better], vi[better], dc[better]
        best[ii[:, 0], ii[:, 1], ii[:, 2]] = dc
        own[ii[:, 0], ii[:, 1], ii[:, 2]] = pi
        vid[ii[:, 0], ii[:, 1], ii[:, 2]] = (vi[:, 0] * gp[1] + vi[:, 1]) * gp[2] + vi[:, 2]
    order = sorted(N26, key=lambda o: abs(o[0]) + abs(o[1]) + abs(o[2]))
    for _ in range(60):
        miss = own < 0
        if not miss.any():
            break
        for o in order:
            so = _shift(own, o, -1)
            sv = _shift(vid, o, -1)
            take = (own < 0) & (so >= 0)
            own[take] = so[take]
            vid[take] = sv[take]
    return _mirrored(sp, own, vid)


def _mirrored(sp, own, vid):
    """The left half laid as the mirror of the right: the same part (its pair on the other side)
    and the mirror of its voxel, wherever the beast has that voxel (a beast is the same both sides,
    and so is its look: user)."""
    parts = sp["parts"]
    mate = []
    for i, p in enumerate(parts):
        m = i
        for j, q in enumerate(parts):
            if abs(q["pos"][0] + p["pos"][0]) < 1e-3 and abs(q["pos"][1] - p["pos"][1]) < 1e-3 and abs(q["pos"][2] - p["pos"][2]) < 1e-3 and q["grid"] == p["grid"]:
                m = j
                break
        mate.append(m)
    occs = []
    for p in parts:
        gp = np.array(p["grid"], int)
        o = np.zeros(tuple(gp), bool)
        for q in p["voxels"]:
            o[q[0], q[1], q[2]] = True
        occs.append(o)
    nx = own.shape[0]
    h2 = nx // 2
    ro = own[h2:][::-1]
    rv = vid[h2:][::-1]
    lo_own = own[:h2].copy()
    lo_vid = vid[:h2].copy()
    ok = ro >= 0
    for i, p in enumerate(parts):
        sel = ok & (ro == i)
        if not sel.any():
            continue
        gp = np.array(p["grid"], int)
        v = rv[sel]
        x = v // (gp[1] * gp[2])
        y = (v // gp[2]) % gp[1]
        z = v % gp[2]
        m = mate[i]
        gm = np.array(parts[m]["grid"], int)
        mx = gm[0] - 1 - x
        have = occs[m][np.clip(mx, 0, gm[0] - 1), np.clip(y, 0, gm[1] - 1), np.clip(z, 0, gm[2] - 1)] & (mx >= 0) & (mx < gm[0])
        idx = np.argwhere(sel)[have]
        lo_own[idx[:, 0], idx[:, 1], idx[:, 2]] = m
        lo_vid[idx[:, 0], idx[:, 1], idx[:, 2]] = (mx[have] * gm[1] + y[have]) * gm[2] + z[have]
    own = own.copy()
    vid = vid.copy()
    own[:h2] = lo_own
    vid[:h2] = lo_vid
    return own, vid


def sample(F, g, w):
    """F (on g) at world points w [n, 3], trilinear."""
    p = (w - g.lo) / g.cell - 0.5
    n = np.array(F.shape)
    p = np.clip(p, 0, n - 1.001)
    i0 = np.floor(p).astype(int)
    t = p - i0
    i1 = np.minimum(i0 + 1, n - 1)
    out = np.zeros(len(w), np.float32)
    for cx in (0, 1):
        for cy in (0, 1):
            for cz in (0, 1):
                ix = i1[:, 0] if cx else i0[:, 0]
                iy = i1[:, 1] if cy else i0[:, 1]
                iz = i1[:, 2] if cz else i0[:, 2]
                wt = (t[:, 0] if cx else 1 - t[:, 0]) * (t[:, 1] if cy else 1 - t[:, 1]) * (t[:, 2] if cz else 1 - t[:, 2])
                out += wt * F[ix, iy, iz]
    return out


def nearest(g, w):
    i = np.floor((w - g.lo) / g.cell).astype(int)
    return np.clip(i, 0, np.array(g.shape) - 1)


# --- the smooth skin -------------------------------------------------------------------------
# (FineSmooth: the game works a man's out as he is drawn, each part with what is jointed onto it.
# A beast's is worked out here, each part's on the whole beast at rest, so that its skin runs on
# across its joints; the game reads it with the sculpt, FineBody. User: the gladiators' smooth skin
# on every monster and beast.)
REACH, REACH_TRUNK, REACH_HEAD = 3, 4, 2        # how far the shape is blurred for the light (FineSmooth)
GEO_REACH, GEO_REACH_HEAD = 2, 1                # and for where the skin is drawn
EVEN_R, HELD_OUT, HELD_IN = 4, 0.7, 0.45
STEP = 160.0                                    # a corner's move, of a fine cell, as whole numbers
VK = 1024                                       # a corner's place as one number: ((x + 64) * VK + y + 64) * VK + z + 64
FACES = [[(1, 0, 0), (1, 1, 0), (1, 1, 1), (1, 0, 1)], [(0, 0, 0), (0, 0, 1), (0, 1, 1), (0, 1, 0)],
         [(0, 1, 0), (0, 1, 1), (1, 1, 1), (1, 1, 0)], [(0, 0, 0), (1, 0, 0), (1, 0, 1), (0, 0, 1)],
         [(0, 0, 1), (1, 0, 1), (1, 1, 1), (0, 1, 1)], [(0, 0, 0), (0, 1, 0), (1, 1, 0), (1, 0, 0)]]
STEPS = [(1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0), (0, 0, 1), (0, 0, -1)]


def _box_mean(f, r, rim="edge"):
    """`f` blurred: the mean of the 2r + 1 round each cell along each axis, twice over."""
    f = f.astype(np.float64)
    for ax in range(3):
        for _ in range(2):
            pad = [(r, r) if a == ax else (0, 0) for a in range(3)]
            p = np.pad(f, pad, mode=rim) if rim == "edge" else np.pad(f, pad, mode="constant")
            c = np.cumsum(p, axis=ax)
            c = np.concatenate([np.zeros_like(np.take(c, [0], axis=ax)), c], axis=ax)
            n = f.shape[ax]
            f = (np.take(c, np.arange(2 * r + 1, 2 * r + 1 + n), axis=ax) - np.take(c, np.arange(0, n), axis=ax)) / (2 * r + 1)
    return f.astype(np.float32)


def _at_corners(f):
    """A field at its cells' corners (corner (i, j, k): the low corner of cell (i, j, k)): its slope
    there, a fine cell, and how full it is."""
    n = f.shape
    A = np.pad(f, 1, mode="edge")
    s = lambda a, b, c: A[a:a + n[0] + 1, b:b + n[1] + 1, c:c + n[2] + 1]
    a000, a001, a010, a011, a100, a101, a110, a111 = s(0, 0, 0), s(0, 0, 1), s(0, 1, 0), s(0, 1, 1), s(1, 0, 0), s(1, 0, 1), s(1, 1, 0), s(1, 1, 1)
    gx = ((a100 + a101 + a110 + a111) - (a000 + a001 + a010 + a011)) * 0.25
    gy = ((a010 + a011 + a110 + a111) - (a000 + a001 + a100 + a101)) * 0.25
    gz = ((a001 + a011 + a101 + a111) - (a000 + a010 + a100 + a110)) * 0.25
    return gx, gy, gz, (a000 + a001 + a010 + a011 + a100 + a101 + a110 + a111) * 0.125


def _encode(nx, ny, nz):
    """A way as FineSmooth.encode has it, less the 2 (an octahedron's 32 by 32); -1: none."""
    s = np.abs(nx) + np.abs(ny) + np.abs(nz)
    ok = s > 1e-6
    s = np.where(ok, s, 1.0)
    ox, oy = nx / s, ny / s
    neg = nz < 0.0
    fx = (1.0 - np.abs(oy)) * np.where(ox >= 0.0, 1.0, -1.0)
    fy = (1.0 - np.abs(ox)) * np.where(oy >= 0.0, 1.0, -1.0)
    ox, oy = np.where(neg, fx, ox), np.where(neg, fy, oy)
    u = np.clip(np.floor((ox * 0.5 + 0.5) * 31.0 + 0.5), 0, 31).astype(np.int64)
    v = np.clip(np.floor((oy * 0.5 + 0.5) * 31.0 + 0.5), 0, 31).astype(np.int64)
    return np.where(ok, u * 32 + v, -1)


def smooth_skin(inside, idx, margin, kind="", dd=None, h=1.0):
    """The smooth skin of a part's fine cells `idx` ([n, 3], on the lattice of `inside`: the whole
    beast there), three strings of bytes in base 64: the way each cell faces (two bytes, the low
    first; 0xFFFF none); of its cells' corners, each once in the order of their places (VK), which
    are on the skin (a bit each, the low bit first); and for each of those its move and its way,
    five bytes (the move's three in steps of 1 / STEP about 128, the way's low eight bits, its
    high two with 128 for none). `dd`: the sculpt's own distance on that lattice (its cells `h`),
    for what is too thin for the blur to shape."""
    sol = inside.astype(np.float32)
    light = _box_mean(sol, REACH_TRUNK if kind == "trunk" else (REACH_HEAD if kind == "head" else REACH))
    shape = _box_mean(sol, GEO_REACH_HEAD if kind == "head" else GEO_REACH)
    n = np.array(inside.shape)
    # Each cell's way: down the slope of the light's field.
    L = np.pad(light, 1, mode="edge")
    wx = L[2:, 1:-1, 1:-1] - L[:-2, 1:-1, 1:-1]
    wy = L[1:-1, 2:, 1:-1] - L[1:-1, :-2, 1:-1]
    wz = L[1:-1, 1:-1, 2:] - L[1:-1, 1:-1, :-2]
    i, j, k = idx[:, 0], idx[:, 1], idx[:, 2]
    ways = _encode(-wx[i, j, k], -wy[i, j, k], -wz[i, j, k])
    # The corners on the beast's skin (any part's): of a face with nothing of it beyond.
    on = np.zeros(tuple(n + 1), bool)
    for d, st in enumerate(STEPS):
        bare = inside & ~_shift(inside, (-st[0], -st[1], -st[2]), False)
        for o in FACES[d]:
            on[o[0]:o[0] + n[0], o[1]:o[1] + n[1], o[2]:o[2] + n[2]] |= bare
    gx, gy, gz, w = _at_corners(shape)
    gl = np.sqrt(gx * gx + gy * gy + gz * gz)
    ok = on & (gl > 0.02)
    glz = np.where(ok, gl, 1.0)
    out_by = np.where(ok, np.clip((w - 0.5) / glz, -2.5, 2.5), 0.0).astype(np.float32)
    even = _box_mean(out_by, EVEN_R, "zero")
    cover = _box_mean(ok.astype(np.float32), EVEN_R, "zero")
    mv = np.where(ok & (cover > 1e-6), np.clip(out_by - even / np.maximum(cover, 1e-6), -HELD_IN, HELD_OUT), 0.0)
    mx, my, mz = -gx / glz * mv, -gy / glz * mv, -gz / glz * mv
    if dd is not None:
        # What is thin (a horn's point, a tusk, a claw, a thin tail: nowhere two cells deep): the
        # blur has nothing of it left to shape and the evening leaves its stairs as they are, so it
        # was drawn in bare cubes, a horn's point a block, a tusk a flight of steps. There each
        # corner goes to the sculpt's own skin instead, straight down its slope.
        deep = (-dd / h).astype(np.float32)
        for ax in range(3):
            pd_ = np.pad(deep, [(2, 2) if a == ax else (0, 0) for a in range(3)], mode="edge")
            deep = np.max(np.stack([np.take(pd_, np.arange(o, o + deep.shape[ax]), axis=ax) for o in range(5)], 0), 0)
        thin = np.clip((1.7 - deep) / 0.6, 0.0, 1.0)
        sgx, sgy, sgz, sc_ = _at_corners((dd / h).astype(np.float32))
        tc = np.where(on, _at_corners(thin)[3], 0.0)
        g2 = np.maximum(sgx * sgx + sgy * sgy + sgz * sgz, 0.05)
        sx_, sy_, sz_ = -sc_ * sgx / g2, -sc_ * sgy / g2, -sc_ * sgz / g2
        far = np.minimum(1.0, 0.75 / np.maximum(np.sqrt(sx_ * sx_ + sy_ * sy_ + sz_ * sz_), 1e-6))
        mx = mx * (1.0 - tc) + sx_ * far * tc
        my = my * (1.0 - tc) + sy_ * far * tc
        mz = mz * (1.0 - tc) + sz_ * far * tc
    lx, ly, lz, _ = _at_corners(light)
    cw = _encode(-lx, -ly, -lz)
    # The corners of this part's cells, each once, in the order of their places (as the game lists
    # them again from the cells: FineBody); which of them are on the skin, and those ones' moves
    # and ways. The rest (under the skin, where a wound opens) are drawn where they are.
    vi = np.concatenate([idx + np.array([c & 1, (c >> 1) & 1, (c >> 2) & 1]) for c in range(8)], 0)
    key = ((vi[:, 0] - margin + 64) * VK + (vi[:, 1] - margin + 64)) * VK + (vi[:, 2] - margin + 64)
    key, first = np.unique(key, return_index=True)
    vx, vy, vz = vi[first, 0], vi[first, 1], vi[first, 2]
    lit = on[vx, vy, vz]
    bits = np.packbits(lit.astype(np.uint8), bitorder="little")
    vx, vy, vz = vx[lit], vy[lit], vz[lit]
    q = lambda m: (np.clip(np.floor(m[vx, vy, vz] * STEP + 0.5), -127, 127).astype(np.int64) + 128).astype(np.uint8)
    wc = cw[vx, vy, vz]
    none = wc < 0
    wc = np.where(none, 0, wc)
    rec = np.stack([q(mx), q(my), q(mz), (wc & 255).astype(np.uint8), ((wc >> 8) | np.where(none, 128, 0)).astype(np.uint8)], 1)
    w16 = np.where(ways < 0, 0xFFFF, ways).astype("<u2")
    b64 = lambda b: base64.b64encode(b.tobytes()).decode("ascii")
    return b64(w16), b64(bits), b64(rec)


# --- its shape drawn on its hide ---------------------------------------------------------------
# (gen_fine_body._form_tones, a fighter's: user, what was done for the gladiators on every monster
# and beast.) Under the smooth skin a beast's own shape is drawn on its hide in flat tones: where it
# folds in (behind a shoulder, under the jaw, between its haunches and its belly), the shade a fold
# lies in, as far as the hide within a hand of it shuts the sky off; where it stands out round (a
# shoulder, a haunch, the ridge of its back, a knee), a light. Each fine cell a tile of one tone.
TONE_SOFT, TONE_SHADE, TONE_LIGHT = 140, 168, 218
FORM_SHARE = (0.13, 0.04, 0.16)   # how much of a part's hide lies in shade, in the deeper shade, in the light
HIDE = (8, 10, 11)                # fur, scales, shell (never an eye, a tooth, a claw, a horn)


def form_tones(dd, h, idx, ow, group, hide):
    """For each of a part's skin cells `idx` (on the lattice of `dd`, the beast's shape there, cells
    of `h`): the tone it is drawn in, 0 its hide as it is. By the part and the parts it is jointed
    to alone (`group`, of `ow`, whose each cell is): a leg by its flank does not shade the flank,
    it moves. Only its hide (`hide`, of each cell)."""
    gx, gy, gz = np.gradient(dd.astype(np.float64), h)
    gl = np.sqrt(gx * gx + gy * gy + gz * gz) + 1e-9
    i, j, l = idx[:, 0], idx[:, 1], idx[:, 2]
    n = dd.shape
    nx, ny, nz = gx[i, j, l] / gl[i, j, l], gy[i, j, l] / gl[i, j, l], gz[i, j, l] / gl[i, j, l]
    kin = np.isin(ow, list(group))
    occ = np.zeros(len(idx))
    for hh in (1.5, 3.0, 4.5, 6.0):
        pi = np.clip(np.rint(i + nx * hh).astype(int), 0, n[0] - 1)
        pj = np.clip(np.rint(j + ny * hh).astype(int), 0, n[1] - 1)
        pl = np.clip(np.rint(l + nz * hh).astype(int), 0, n[2] - 1)
        occ += np.where(kin[pi, pj, pl], np.clip(dd[i, j, l] + hh * h - dd[pi, pj, pl], 0.0, None) / (hh * h), 0.0)
    # How round it is there (over 0 a swell), two fine cells across.
    k = 2
    pad = np.pad(dd.astype(np.float64), k, mode="edge")
    lap = (pad[2 * k:, k:-k, k:-k] + pad[:-2 * k, k:-k, k:-k] + pad[k:-k, 2 * k:, k:-k] + pad[k:-k, :-2 * k, k:-k]
           + pad[k:-k, k:-k, 2 * k:] + pad[k:-k, k:-k, :-2 * k] - 6.0 * dd) / (k * h) ** 2
    c = _box_mean(lap, 1)[i, j, l]
    out = np.zeros(len(idx), np.int32)
    if hide.sum() > 50:
        qo = np.quantile(occ[hide], [1.0 - FORM_SHARE[0], 1.0 - FORM_SHARE[1]])
        qc = np.quantile(c[hide], 1.0 - FORM_SHARE[2])
        out[c > qc] = TONE_LIGHT
        out[(occ > qo[0]) & (occ > 0.02)] = TONE_SHADE
        out[(occ > qo[1]) & (occ > 0.05)] = TONE_SOFT
        out[~hide] = 0
    # Specks: a tile whose tone fewer than two of the tiles round it share is its hide's own.
    grid = np.full(n, -1, np.int32)
    grid[i, j, l] = out
    padg = np.pad(grid, 1, constant_values=-1)
    same = np.zeros(len(idx), np.int32)
    for a in (-1, 0, 1):
        for b in (-1, 0, 1):
            for e in (-1, 0, 1):
                if a or b or e:
                    same += padg[i + 1 + a, j + 1 + b, l + 1 + e] == out
    out[(out != 0) & (same < 2)] = 0
    return out.astype(np.uint8)


JOINT_OVERLAP = 3    # fine cells a part's skin reaches on past where its neighbour's begins, at their joint
# A beast whose necks rise side by side out of one chest (the hydra's five): the skin between two
# of them was laid by whichever neck was the nearer, so a neck that bowed or turned on its own left
# a hole in its side where its neighbour's skin had lain, and one bowed far to strike opened at its
# root (user: make sure the hydra looks whole). Its necks reach into each other's skin as into a
# joint's; every joint of it reaches further than most, and its necks' roots (and the necks beside
# each other) further still: (every joint, the necks').
NECKS_SIDE_BY_SIDE = {"hydra": (6, 10)}


def part_cells(pi, p, g, d, col, kind, own, vid, kin):
    """`kin`: the parts it is jointed to, each with how many fine cells its skin reaches on into
    theirs."""
    gp = np.array(p["grid"], int)
    v = 0.0275 * float(p["scale"])
    h = v / RES
    R = BS.quat_m(p["rot"])
    pos = np.array(p["pos"], float)
    n = gp * RES + 2 * MARGIN
    ii = np.stack(np.meshgrid(np.arange(n[0]), np.arange(n[1]), np.arange(n[2]), indexing="ij"), -1).reshape(-1, 3)
    local = -gp * v * 0.5 + (ii - MARGIN + 0.5) * h
    w = pos + local @ R.T
    dd = sample(d, g, w).reshape(tuple(n))
    inside = dd < 0
    ni = nearest(g, w)
    ow = own[ni[:, 0], ni[:, 1], ni[:, 2]].reshape(tuple(n))
    mine = inside & (ow == pi)
    if not mine.any():
        return None
    # At a joint each of the two parts' skin reaches a little on into the other's (drawn twice
    # where they lie still, alike): turned at the joint, a knee or a neck shows no crack.
    over = np.zeros_like(mine)
    if kin:
        grow = mine.copy()
        for step in range(1, max(kin.values()) + 1):
            g2 = grow.copy()
            for ax in range(3):
                for dl in (-1, 1):
                    dv = [0, 0, 0]
                    dv[ax] = dl
                    g2 |= _shift(grow, dv, False)
            grow = g2 & inside
            for k, reach in kin.items():
                if reach == step:
                    over |= grow & (ow == k)
        over &= ~mine
    out_n = np.zeros_like(inside)
    for ax in range(3):
        for dl in (-1, 1):
            dv = [0, 0, 0]
            dv[ax] = dl
            out_n |= ~_shift(inside, (-dv[0], -dv[1], -dv[2]), False)
    skin = (mine | over) & out_n
    wide = _blur(inside.astype(float), 2)
    shade = np.clip(200 - (wide - 0.5) * 70, 165, 215).astype(np.int64)
    ao = np.zeros(inside.shape, np.int64)
    at = lambda dv: _shift(inside, (-dv[0], -dv[1], -dv[2]), False)
    for fi, (fn, ua, va) in enumerate(AO_FACES):
        open_face = ~at(fn)
        for c in range(4):
            du = [0, 0, 0]
            du[ua] = 1 if c & 1 else -1
            dv2 = [0, 0, 0]
            dv2[va] = 1 if c & 2 else -1
            a1 = at((fn[0] + du[0], fn[1] + du[1], fn[2] + du[2]))
            b1 = at((fn[0] + dv2[0], fn[1] + dv2[1], fn[2] + dv2[2]))
            c1 = at((fn[0] + du[0] + dv2[0], fn[1] + du[1] + dv2[1], fn[2] + du[2] + dv2[2]))
            ao |= np.where(skin & open_face & (a1 | b1 | c1), 1 << (fi * 4 + c), 0)
    idx = np.argwhere(skin)
    flat = np.ravel_multi_index(idx.T, tuple(n))
    nw = ni[flat]
    # Its colour and its kind: the sculpt's a little in under the skin there (on a thin tusk or a
    # claw the nearest of the grid's cells may lie just outside it, and took the fur's).
    wc = w[flat]
    grad = np.zeros_like(wc)
    for ax in range(3):
        e = np.zeros(3)
        e[ax] = h * 0.5
        grad[:, ax] = sample(d, g, wc + e) - sample(d, g, wc - e)
    nrm = grad / np.maximum(np.linalg.norm(grad, axis=1, keepdims=True), 1e-9)
    nc = nearest(g, wc - nrm * h * 0.6)
    # (but where the grid's own cell there is inside, that one: a thin horn's tip, stepped in on,
    # was stepped right through and out of its far side)
    keep = d[nw[:, 0], nw[:, 1], nw[:, 2]] < 0
    nc[keep] = nw[keep]
    vv = vid[nw[:, 0], nw[:, 1], nw[:, 2]]
    cx = vv // (gp[1] * gp[2])
    cy = (vv // gp[2]) % gp[1]
    cz = vv % gp[2]
    occ = np.zeros(tuple(gp), bool)
    for q in p["voxels"]:
        occ[q[0], q[1], q[2]] = True
    # (A cell reaching into the neighbour lies over the nearest of this part's own voxels.)
    theirs = ~mine.reshape(-1)[flat]
    if theirs.any():
        vox = np.argwhere(occ)
        q = (idx[theirs] - MARGIN + 0.5) / RES
        best = np.zeros(q.shape[0], int)
        bd = np.full(q.shape[0], np.inf)
        for chunk in range(0, vox.shape[0], 4096):
            vc = vox[chunk:chunk + 4096] + 0.5
            d2 = ((q[:, None, :] - vc[None, :, :]) ** 2).sum(-1)
            j = d2.argmin(1)
            m = d2[np.arange(q.shape[0]), j] < bd
            bd[m] = d2[np.arange(q.shape[0]), j][m]
            best[m] = chunk + j[m]
        cx[theirs], cy[theirs], cz[theirs] = vox[best, 0], vox[best, 1], vox[best, 2]
    rgb = np.clip(np.round(col[nc[:, 0], nc[:, 1], nc[:, 2]] * 255.0), 0, 255).astype(np.int64)
    kd = kind[nc[:, 0], nc[:, 1], nc[:, 2]].astype(np.int64)
    paint = OWN | (kd << 24) | (rgb[:, 0] << 16) | (rgb[:, 1] << 8) | rgb[:, 2]
    cells = np.stack([idx[:, 0] - MARGIN, idx[:, 1] - MARGIN, idx[:, 2] - MARGIN, cx, cy, cz, shade[skin], ao[skin], paint], 1)
    # Each voxel's eight cells, how deep in the beast: 1 its hide, 2 the fat under it, 3 its flesh.
    core = dd[MARGIN:MARGIN + gp[0] * RES, MARGIN:MARGIN + gp[1] * RES, MARGIN:MARGIN + gp[2] * RES]
    depth = np.where(core >= 0, 0, np.where(-core < 1.2 * h, 1, np.where(-core < 2.6 * h, 2, 3))).astype(np.int64)
    sub = np.zeros(tuple(gp), np.int64)
    for a in range(RES):
        for b in range(RES):
            for c in range(RES):
                s = a + RES * b + RES * RES * c
                sub |= depth[a::RES, b::RES, c::RES] << (2 * s)
    sub[~occ] = 0
    low = p["name"].lower()
    sw, sn, sv = smooth_skin(inside, idx, MARGIN, "trunk" if low == "beastbody" else ("head" if "head" in low else ""), dd, h)
    st = form_tones(dd, h, idx, ow, {pi} | set(kin.keys()), np.isin(kd, HIDE))
    return {"cells": [int(x) for x in cells.reshape(-1)], "sub": [int(x) for x in sub.reshape(-1)], "sw": sw, "sn": sn, "sv": sv,
            "st": base64.b64encode(st.tobytes()).decode("ascii")}


# The beasts' own paint (BeastStyle's rules, as the classic look reads its voxels).
FLESH = (0x9e1b1b, 0x6e0f0f)
BONE_C = 0xe8e0c8
SCALED = ("crocodile", "python", "basilisk", "dragon", "hydra")
CHITIN = ("scorpion", "spider")
GLOWING = ("dragon", "basilisk", "cerberus", "hydra", "manticore", "chimera", "griffin")


def voxel_paint(sp, g, name):
    """The beast's voxels' own colours and kinds on the grid, from its outside voxels (never the
    flesh inside), spread to every cell round them nearest first, the left the mirror of the right:
    (colours [..., 3], kinds)."""
    N = g.shape
    vc = np.zeros(N + (3,), np.float32)
    vk = np.full(N, 8, np.uint8)
    have = np.zeros(N, bool)
    base = 10 if name in SCALED else (11 if name in CHITIN else 8)
    for p in sp["parts"]:
        gp = np.array(p["grid"], int)
        v = 0.0275 * float(p["scale"])
        R = BS.quat_m(p["rot"])
        pos = np.array(p["pos"], float)
        occ = np.zeros(tuple(gp + 2), bool)
        for q in p["voxels"]:
            occ[q[0] + 1, q[1] + 1, q[2] + 1] = True
        low = p["name"].lower()
        gy = max(1, gp[1] - 1)
        for q in p["voxels"]:
            x, y, z, c = q[0] + 1, q[1] + 1, q[2] + 1, int(q[3])
            if occ[x - 1, y, z] and occ[x + 1, y, z] and occ[x, y - 1, z] and occ[x, y + 1, z] and occ[x, y, z - 1] and occ[x, y, z + 1]:
                continue   # (inside: the flesh)
            if c in FLESH:
                continue
            rgb = np.array([(c >> 16 & 255) / 255.0, (c >> 8 & 255) / 255.0, (c & 255) / 255.0], np.float32)
            lum = 0.2126 * rgb[0] + 0.7152 * rgb[1] + 0.0722 * rgb[2]
            k = base
            if (len(q) > 4 and q[4]) or c == BONE_C or (("horn" in low or "tusk" in low or "fang" in low) and lum > 0.6):
                k = 6
            elif lum < 0.06 and "head" in low:
                k = 12 if name in GLOWING and q[1] / gy > 0.45 else 7
                if k == 12:
                    rgb = np.array([1.0, 0.55, 0.1] if name != "basilisk" else [0.75, 1.0, 0.2], np.float32)
            for ox in (-0.25, 0.25):
                for oy in (-0.25, 0.25):
                    for oz in (-0.25, 0.25):
                        lc = -gp * v * 0.5 + (np.array([q[0], q[1], q[2]]) + 0.5 + np.array([ox, oy, oz])) * v
                        w = pos + R @ lc
                        i = np.floor((w - g.lo) / g.cell).astype(int)
                        if np.all(i >= 0) and np.all(i < np.array(N)):
                            vc[i[0], i[1], i[2]] = rgb
                            vk[i[0], i[1], i[2]] = k
                            have[i[0], i[1], i[2]] = True
    order = sorted(N26, key=lambda o: abs(o[0]) + abs(o[1]) + abs(o[2]))
    for _ in range(40):
        if have.all():
            break
        for o in order:
            sh = _shift(have, o, False)
            take = ~have & sh
            if not take.any():
                continue
            vc[take] = _shift3(vc, o)[take]
            vk[take] = _shift(vk, o, 8)[take]
            have |= take
    h2 = N[0] // 2
    vc[:h2] = vc[h2:][::-1]
    vk[:h2] = vk[h2:][::-1]
    return vc, vk


def _shift3(a, o):
    out = np.zeros_like(a)
    src = [slice(None)] * 3
    dst = [slice(None)] * 3
    for ax in range(3):
        if o[ax] > 0:
            src[ax] = slice(0, -o[ax])
            dst[ax] = slice(o[ax], None)
        elif o[ax] < 0:
            src[ax] = slice(-o[ax], None)
            dst[ax] = slice(0, o[ax])
    out[tuple(dst)] = a[tuple(src)]
    return out


def main(out_dir, only):
    beasts = json.load(open("data/beasts.json"))
    os.makedirs(out_dir, exist_ok=True)
    for name, sp in beasts.items():
        if (name not in BS.SCULPTS and name not in BS.KIT) or (only and name not in only):
            continue
        g = world_grid(sp)
        own, vid = labels(sp, g)
        extra = {}
        if name in BS.KIT:
            vc, vk = voxel_paint(sp, g, name)
            d, col, kind = BS.KIT[name](sp, g, vc, vk)
        else:
            made = BS.SCULPTS[name](sp, g)
            d, col, kind = made[:3]
            # (What else a sculpt may say: the parts whose joints are not drawn as one skin, "stiff".)
            extra = made[3] if len(made) > 3 else {}
        names = [p["name"] for p in sp["parts"]]
        parts = {}
        total = 0
        for pi, p in enumerate(sp["parts"]):
            # The parts it is jointed to: its parent and its children.
            fan = NECKS_SIDE_BY_SIDE.get(name)
            kin = {}
            if p.get("parent") in names:
                kin[names.index(p["parent"])] = fan[0] if fan else JOINT_OVERLAP
            for qi, q in enumerate(sp["parts"]):
                if q.get("parent") == p["name"]:
                    kin[qi] = fan[0] if fan else JOINT_OVERLAP
            if fan:
                for qi, q in enumerate(sp["parts"]):
                    if not q["name"].startswith("neck"):
                        continue
                    if p["name"].startswith("neck") and (q["name"] == p["name"] or q.get("parent") != p.get("parent")):
                        continue
                    if p["name"].startswith("neck") or q.get("parent") == p["name"]:
                        kin[qi] = fan[1]   # (a neck beside it, or one of its own necks)
                if p["name"].startswith("neck") and p.get("parent") in names:
                    kin[names.index(p["parent"])] = fan[1]   # (the body its root is in)
            r = part_cells(pi, p, g, d, col, kind, own, vid, kin)
            if r is not None:
                if p["name"] in extra.get("stiff", ()):
                    r["stiff"] = 1
                parts[p["name"]] = r
                total += len(r["cells"]) // CELL
        with open(os.path.join(out_dir, name + ".json"), "w") as fh:
            json.dump({"res": RES, "margin": MARGIN, "parts": parts}, fh, separators=(",", ":"))
        print(name, total, "cells", flush=True)


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "data/fine_beasts", sys.argv[2:])
