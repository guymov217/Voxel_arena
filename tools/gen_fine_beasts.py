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
import json, os, sys, math
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
    return {"cells": [int(x) for x in cells.reshape(-1)], "sub": [int(x) for x in sub.reshape(-1)]}


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
        if name in BS.KIT:
            vc, vk = voxel_paint(sp, g, name)
            d, col, kind = BS.KIT[name](sp, g, vc, vk)
        else:
            d, col, kind = BS.SCULPTS[name](sp, g)
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
                parts[p["name"]] = r
                total += len(r["cells"]) // CELL
        with open(os.path.join(out_dir, name + ".json"), "w") as fh:
            json.dump({"res": RES, "parts": parts}, fh, separators=(",", ":"))
        print(name, total, "cells", flush=True)


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "data/fine_beasts", sys.argv[2:])
