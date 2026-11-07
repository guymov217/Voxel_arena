#!/usr/bin/env python3
"""The fine head: a man's head sculpted in voxels three to the body's voxel each way (drawing only:
the body's own voxels are what is hit, cut and bled). A rounded skull, the brow, sockets with eyes in
them, the nose, cheekbones, lips, a jaw narrowing to the chin, ears; every cell of its shell with the
part of the face it is (an eye's white, its iris, a lip...) and the places a haircut or a beard can
cover it, so the game colours it for each man (Physique.fine_head) without working out the shape.

    python3 tools/gen_fine_head.py data/fine_head.json

Cells are in fine voxels from the head grid's corner (the game's head is 10 x 12 x 10 voxels: 30 x
36 x 30 fine ones); a few stand out of it (the nose, the ears). Face toward +z.

The face is a fighter's (user: the veteran's of the face sheet): a lean face, the jaw strong and
square, cheekbones set high and out, a heavy straight brow over deep sockets, the eyes narrow under
heavy lids, the mouth shut in a firm line, the hairline a man's, high at the temples; the nose broad.
The other noses a man may choose (Your gladiator) are written as what they change of it ("noses":
the cells each takes away and the cells each puts there instead)."""
import json, math, sys

RES = 3
GX, GY, GZ = 10, 12, 10
HX, HY, HZ = GX * RES / 2.0, GY * RES / 2.0, GZ * RES / 2.0   # the grid's half size (fine)

def smin(a, b, k):
    h = max(k - abs(a - b), 0.0) / k
    return min(a, b) - h * h * k * 0.25

def smax(a, b, k):
    return -smin(-a, -b, k)

def ell(p, c, r):
    x, y, z = (p[0]-c[0])/r[0], (p[1]-c[1])/r[1], (p[2]-c[2])/r[2]
    return (math.sqrt(x*x+y*y+z*z) - 1.0) * min(r)

EYE_X, EYE_Y = 5.2, 2.2

def rbox(p, c, b, r):
    q = [abs(p[i] - c[i]) - b[i] for i in range(3)]
    return math.sqrt(sum(max(v, 0.0) ** 2 for v in q)) + min(max(q), 0.0) - r

## The noses: breadth (of the straight one), the tip's lift (+ up) and how far it stands out (+),
## the bridge's hump (a Roman nose), its bend aside (a broken one: the ridge to one side and the
## tip back to the other), and its length (of the straight one).
NOSES = {
    "broad": {"w": 1.35, "tip_y": 0.0, "tip_z": 0.0, "hump": 0.0, "bend": 0.0, "len": 1.0},
    "straight": {"w": 1.0, "tip_y": 0.0, "tip_z": 0.0, "hump": 0.0, "bend": 0.0, "len": 1.0},
    "roman": {"w": 1.05, "tip_y": -0.5, "tip_z": 0.3, "hump": 1.0, "bend": 0.0, "len": 1.08},
    "broken": {"w": 1.25, "tip_y": 0.0, "tip_z": -0.3, "hump": 0.45, "bend": 1.0, "len": 1.0},
    "small": {"w": 0.85, "tip_y": 0.5, "tip_z": -0.6, "hump": 0.0, "bend": 0.0, "len": 0.86},
}
NOSE = "broad"

def nose_sdf(p, nz):
    x, y, z = p
    w = nz["w"]
    # (A broken nose: the bridge set over to one side below the brow, the tip bent back the other.)
    bx = nz["bend"] * (0.75 * max(0.0, min(1.0, (2.5 - y) / 4.0)) - 0.5 * max(0.0, min(1.0, (-2.5 - y) / 2.0)))
    q = (x - bx, y, z)
    ln = nz["len"]
    nose = ell(q, (0, 0.3 + 4.4 * (1.0 - ln) * 0.5, 12.5), (1.5 * w, 4.4 * ln, 2.1))
    if nz["hump"] > 0.0:
        nose = smin(nose, ell(q, (0, 1.4, 13.4 + 0.25 * nz["hump"]), (1.15 * w, 1.6, 1.3 * nz["hump"] + 0.4)), 1.0)
    ty = -4.2 + nz["tip_y"] + 4.4 * (1.0 - ln)
    nose = smin(nose, ell(q, (0, ty, 13.9 - 0.4 * (w - 1.0) + nz["tip_z"]), (1.9 * w, 1.6, 1.9)), 1.4)
    for sx in (-1, 1):
        nose = smin(nose, ell(q, (sx * 2.0 * w, ty - 0.5, 12.6 + 0.5 * nz["tip_z"]), (1.2 * w, 1.1, 1.2)), 1.0)
    return nose

def sdf(p, nose=None):
    x, y, z = p
    nz = NOSES[nose or NOSE]
    EX = EYE_X
    # Skull and face: the face a touch longer and leaner than a boy's round one.
    d = smin(ell(p, (0, 3.2, -1.2), (13.3, 15.3, 14.0)), ell(p, (0, -4.2, 0.6), (10.6, 13.4, 10.7)), 6.0)
    # The jaw, its corners set out under the ears, narrowing to the chin.
    d = smin(d, ell(p, (0, -10.2, 2.4), (9.8, 7.0, 8.9)), 4.5)
    for sx in (-1, 1):
        d = smin(d, ell(p, (sx * 8.8, -9.8, 2.8), (3.0, 3.6, 6.0)), 3.0)
    # Cheekbones, high and set out.
    for sx in (-1, 1):
        d = smin(d, ell(p, (sx * 8.6, 0.2, 9.0), (3.8, 2.0, 2.8)), 2.2)
    # A heavy brow over deep sockets.
    d = smin(d, ell(p, (0, 4.7, 12.1), (10.8, 2.1, 2.4)), 1.8)
    for sx in (-1, 1):
        d = smax(d, -ell(p, (sx * EX, 2.3, 13.7), (3.0, 2.0, 2.6)), 1.3)
    for sx in (-1, 1):
        d = min(d, ell(p, (sx * EX, EYE_Y, 9.6), (2.6, 2.0, 2.2)))
    d = smin(d, nose_sdf(p, nz), 1.2)
    # Firm lips, not full.
    d = smin(d, ell(p, (0, -8.4, 11.2), (3.0, 0.8, 1.2)), 0.9)
    d = smin(d, ell(p, (0, -9.8, 10.9), (2.6, 0.9, 1.25)), 0.9)
    # A square chin.
    d = smin(d, rbox(p, (0, -14.2, 9.3), (3.0, 1.5, 1.6), 1.1), 2.0)
    for sx in (-1, 1):
        d = smin(d, ell(p, (sx * 13.4, 0.5, -0.5), (1.7, 4.2, 2.6)), 1.2)
    return max(d, -(y + HY))

# VoxelPart.AO_FACES: a face's normal and its two axes across.
AO_FACES = [((1, 0, 0), 1, 2), ((-1, 0, 0), 1, 2), ((0, 1, 0), 0, 2), ((0, -1, 0), 0, 2), ((0, 0, 1), 0, 1), ((0, 0, -1), 0, 1)]

# What a cell is (FEAT) and what can cover it (bits), see FineHead.
FEAT = ["skin", "white", "iris", "pupil", "lid", "brow", "lip", "lip_line", "nostril", "shade", "blush", "light", "ear_in", "lid_low"]
CAP, CAP_RECEDE_OFF, NAPE, LONG, SIDE, JAW, CHIN, LIP_TOP, GOATEE = 1, 2, 4, 8, 16, 32, 64, 128, 256

def _round_feature(p, n):
    x, y, z = p
    for sx in (-1, 1):
        ex = sx * EYE_X
        if ((x-ex)/2.7)**2 + ((y-EYE_Y)/2.1)**2 < 1.0 and 9.5 < z < 12.6:
            if y - EYE_Y > 1.2:
                return "lid"
            if y - EYE_Y < -1.4:
                return "lid_low"
            if abs(x - ex) < 1.25 and abs(y - EYE_Y) < 1.15:
                return "pupil" if abs(x - ex) < 0.55 and abs(y - EYE_Y - 0.1) < 0.55 else "iris"
            return "white"
        bx = (x - ex) * sx
        arch = 4.6 + 0.9 * (1.0 - (bx / 3.8) ** 2)
        if -3.0 < bx < 3.9 and arch - (0.9 if bx < 0 else 0.6) < y < arch + 0.5 and z > 11.0:
            return "brow"
    if abs(x) < 3.0 and -10.0 < y < -9.0 and z > 10.6:
        return "lip_line" if abs(x) < 2.6 else "shade"
    if abs(x) < 3.5 and -9.0 <= y < -7.6 and z > 11.0 and (y < -8.0 or abs(x) < 2.6):
        return "lip"
    if abs(x) < 2.8 and -11.0 < y <= -10.0 and z > 10.6:
        return "lip"
    if abs(x) > 12.2 and abs(y - 0.5) < 4.6 and abs(z + 0.5) < 3.0:
        return "ear_in" if abs(x) > 13.6 and abs(y - 0.5) < 2.4 and abs(z + 0.5) < 1.2 else "skin"
    if abs(abs(x) - 1.9) < 0.9 and -5.9 < y < -4.6 and z > 11.5 and n[1] < 0.2:
        return "nostril"
    if abs(x) < 2.6 and -6.6 < y < -5.6 and z > 11.2:
        return "shade"
    if abs(x) < 2.8 and -11.8 < y < -10.9 and z > 10.6:
        return "shade"
    if abs(abs(x) - 7.5) < 1.6 and -4.0 < y < -1.5 and z > 9.5:
        return "blush"
    if abs(x) < 0.9 and -3.0 < y < 3.0 and z > 12.6:
        return "light"
    return "skin"

def _round_cover(p, feat):
    x, y, z = p
    bits = 0
    ear = abs(x) > 12.2 and abs(y - 0.5) < 4.6 and abs(z + 0.5) < 3.0
    if feat in ("skin", "light", "blush", "shade") and not ear:
        line = 8.5 + 0.9 * min(1.0, abs(x) / 6.0) - 0.7 * max(0.0, 1.0 - abs(x) / 2.0) - (1.4 if abs(x) > 9.5 else 0.0)
        if y > line - 0.15 * max(0.0, z):
            bits |= CAP
            if y < line + 3.8 - 0.15 * max(0.0, z) + 2.6 * max(0.0, 1.0 - abs(abs(x) - 4.5) / 4.0) - 1.2:
                bits |= CAP_RECEDE_OFF   # (bare on a receding head)
        if z < 1.5 and y > -8.0 + 0.25 * z:
            bits |= NAPE
        if z < 1.5 and y > -13.0 + 0.25 * z:
            bits |= LONG
        if abs(x) > 11.5 and 1.5 <= z < 5.0 and y > -2.5:
            bits |= SIDE
        if y < -3.0 and z > -1.0 and (abs(x) > 8.0 or y < -7.0) and not (abs(x) < 4.0 and -11.4 < y < -7.0 and z > 10.0):
            bits |= JAW
        if y < -10.5 and z > 4.0 and abs(x) < 6.0:
            bits |= CHIN
        if -7.6 < y < -5.8 and abs(x) < 4.4 and z > 10.0:
            bits |= LIP_TOP
        if abs(x) < 4.0 and -12.5 < y < -10.0 and z > 9.0:
            bits |= GOATEE
    return bits

## The veteran's eyes, brows and mouth over the round head's (its ears, its blush and the light on
## the ridge of the nose as they were).
def feature(p, n):
    x, y, z = p
    EX, EY = EYE_X, EYE_Y
    for sx in (-1, 1):
        ex = sx * EX
        # The eye narrower and lidded heavier: the iris most of what shows (a steady look, not a
        # wide-eyed one).
        if ((x - ex) / 2.7) ** 2 + ((y - EY) / 2.0) ** 2 < 1.0 and 9.5 < z < 12.6:
            if y - EY > 0.75:
                return "lid"
            if y - EY < -1.15:
                return "lid_low"
            if abs(x - ex) < 1.3 and abs(y - EY) < 1.0:
                return "pupil" if abs(x - ex) < 0.55 and abs(y - EY - 0.1) < 0.55 else "iris"
            return "white"
        # Brows thick, low and straight.
        bx = (x - ex) * sx
        arch = 4.0 + 0.35 * (1.0 - (bx / 3.8) ** 2)
        if -3.2 < bx < 4.0 and arch - 1.0 < y < arch + 0.6 and z > 11.0:
            return "brow"
    # The mouth shut: a firm line, a thin lower lip under it, the upper lip the skin's own.
    if abs(x) < 2.6 and -10.0 < y < -9.0 and z > 10.4:
        return "lip_line" if abs(x) < 2.1 else "shade"
    if abs(x) < 1.6 and -11.0 < y <= -10.0 and z > 10.4:
        return "lip"
    if abs(x) < 1.0 and -11.8 < y < -10.9 and z > 10.6:
        return "shade"   # (the dip under the lower lip, only in the middle)
    if abs(x) < 2.8 and -11.8 < y < -10.0 and z > 10.4:
        return "skin"
    # The nostrils only underneath, not two dark spots on the face, and the shade under the nose
    # only right under its tip.
    if abs(abs(x) - 1.9) < 1.0 and -5.9 < y < -4.6 and z > 11.5:
        return "nostril" if n[1] < -0.45 else "skin"
    if abs(x) < 2.6 and -6.6 < y < -5.6 and z > 11.2:
        return "shade" if abs(x) < 1.0 else "skin"
    f = _round_feature(p, n)
    if f in ("brow", "lid", "lid_low", "white", "iris", "pupil", "lip", "lip_line", "blush"):
        return "skin"   # (what the round head's eyes, brows and mouth were, where these are not)
    return f

## The hairline higher at the temples (a man's, not a boy's fringe straight across).
def cover(p, feat):
    x, y, z = p
    bits = _round_cover(p, feat)
    if bits & CAP:
        lift = 0.9 + 0.7 * max(0.0, 1.0 - abs(abs(x) - 6.0) / 3.0) + 0.7 * max(0.0, 1.0 - abs(x) / 2.0)
        line = 8.5 + 0.9 * min(1.0, abs(x) / 6.0) - 0.7 * max(0.0, 1.0 - abs(x) / 2.0) - (1.4 if abs(x) > 9.5 else 0.0)
        if z > 6.0 and y <= line - 0.15 * max(0.0, z) + lift:
            bits &= ~CAP
    return bits

def shell(nose=None):
    """The head's shell with that nose: its cells as the game reads them (see main)."""
    occ = {}
    lo = (-int(HX) - 2, -int(HY), -int(HZ) - 2)
    hi = (int(HX) + 2, int(HY), int(HZ) + 3)
    for ix in range(lo[0], hi[0]):
        for iy in range(lo[1], hi[1]):
            for iz in range(lo[2], hi[2]):
                occ[(ix, iy, iz)] = sdf((ix + 0.5, iy + 0.5, iz + 0.5), nose) <= 0.0
    cells = []
    for (ix, iy, iz), on in sorted(occ.items()):
        if not on:
            continue
        if all(occ.get((ix+dx, iy+dy, iz+dz), False) for dx, dy, dz in ((1,0,0),(-1,0,0),(0,1,0),(0,-1,0),(0,0,1),(0,0,-1))):
            continue
        p = (ix + 0.5, iy + 0.5, iz + 0.5)
        e = 0.3
        n = (sdf((p[0]+e, p[1], p[2]), nose) - sdf((p[0]-e, p[1], p[2]), nose), sdf((p[0], p[1]+e, p[2]), nose) - sdf((p[0], p[1]-e, p[2]), nose), sdf((p[0], p[1], p[2]+e), nose) - sdf((p[0], p[1], p[2]-e), nose))
        ln = math.sqrt(n[0]**2 + n[1]**2 + n[2]**2) or 1.0
        n = (n[0]/ln, n[1]/ln, n[2]/ln)
        f = feature(p, n)
        # The shade of the skin there: the sockets and under the jaw darker, the nose's ridge lighter.
        k = 1.0
        for sx in (-1, 1):
            dd = math.hypot((p[0]-sx*EYE_X)/4.2, (p[1]-2.4)/3.2)
            if dd < 1.0 and p[2] > 9:
                k *= 0.86 + 0.14 * dd
        if p[1] < -12 and p[2] > 4:
            k *= 0.95
        # The body voxel it lies on: out along its normal to the last of the head's voxels it meets
        # (the face's on the front layer, the crown's on the top), so it goes with that one.
        q = (min(max(p[0], -HX + 0.01), HX - 0.01), min(max(p[1], -HY + 0.01), HY - 0.01), min(max(p[2], -HZ + 0.01), HZ - 0.01))
        last = q
        for st in range(1, 40):
            r = (q[0] + n[0] * 0.5 * st, q[1] + n[1] * 0.5 * st, q[2] + n[2] * 0.5 * st)
            if abs(r[0]) >= HX or abs(r[1]) >= HY or abs(r[2]) >= HZ:
                break
            last = r
        par = [int((last[0] + HX) // RES), int((last[1] + HY) // RES), int((last[2] + HZ) // RES)]
        # Its corners shut in by its neighbours (VoxelPart.ao_bits, on the fine grid).
        ao = 0
        for fi, (fn, ua, va) in enumerate(AO_FACES):
            nb = (ix + fn[0], iy + fn[1], iz + fn[2])
            if occ.get(nb, False):
                continue
            for c in range(4):
                su = 1 if c & 1 else -1
                sv = 1 if c & 2 else -1
                du = [0, 0, 0]; du[ua] = su
                dv = [0, 0, 0]; dv[va] = sv
                if occ.get((nb[0]+du[0], nb[1]+du[1], nb[2]+du[2]), False) or occ.get((nb[0]+dv[0], nb[1]+dv[1], nb[2]+dv[2]), False) or occ.get((nb[0]+du[0]+dv[0], nb[1]+du[1]+dv[1], nb[2]+du[2]+dv[2]), False):
                    ao |= 1 << (fi * 4 + c)
        # From the grid's corner, then: what it is, what may cover it, its shade, its body voxel, its corners.
        cells.append([ix + int(HX), iy + int(HY), iz + int(HZ), FEAT.index(f), cover(p, f), round(k, 3)] + par + [ao])
    return cells

def main(out):
    cells = shell()
    # The other noses: the cells of the face each changes (taken away, and put there instead).
    noses = {}
    base = {tuple(c[:3]): c for c in cells}
    for nm in NOSES:
        if nm == NOSE:
            continue
        other = {tuple(c[:3]): c for c in shell(nm)}
        drop = [list(k) for k in base if k not in other or other[k] != base[k]]
        add = [c for k, c in other.items() if k not in base or base[k] != c]
        noses[nm] = {"drop": drop, "add": add}
        print("nose %s: %d cells off, %d on" % (nm, len(drop), len(add)))
    # The body voxels wholly inside the fine head (drawn as they are: seen only through a wound);
    # every other one is under its shell or outside it, and not drawn while it is on.
    keep = []
    for cx in range(GX):
        for cy in range(GY):
            for cz in range(GZ):
                inside = True
                for a2 in range(RES):
                    for b2 in range(RES):
                        for c2 in range(RES):
                            fp = (cx * RES + a2 - HX + 0.5, cy * RES + b2 - HY + 0.5, cz * RES + c2 - HZ + 0.5)
                            if sdf(fp) > -0.6:
                                inside = False
                                break
                        if not inside:
                            break
                    if not inside:
                        break
                if inside:
                    keep.append([cx, cy, cz])
    data = {"res": RES, "grid": [GX, GY, GZ], "eye": [EYE_X, EYE_Y], "feats": FEAT, "cells": cells, "keep": keep, "nose": NOSE, "noses": noses}
    with open(out, "w") as fh:
        json.dump(data, fh, separators=(",", ":"))
    print("%d cells -> %s" % (len(cells), out))

if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "data/fine_head.json")
