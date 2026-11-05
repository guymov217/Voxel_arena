#!/usr/bin/env python3
"""The fine body: a man as he is built, drawn in voxels half the size of the body's own, over the
game's own parts and joints (the colliders, the voxels that are hit, cut and bled are the game's;
drawing only). Three builds: the champion (lean, a lighter fighter), the hero (broad back, narrow
waist) and the brute (heavy, a belly, a bull neck). Every cell of each part's skin with the body
voxel it lies over and the shade the muscles under it give it; for every body voxel, which of its
eight half-size cells are inside the man and how deep (what a wound opens on: skin, fat, then the
voxel's own flesh, organ or bone); the outline of each limb by height and angle (where armour is
laid); the size of his head (the fine head drawn smaller: tools/gen_fine_head.py).

    python3 tools/gen_fine_body.py data/fine_body.json

Coordinates: the man stands as data/body.json lays him (the arms hanging, the legs straight),
facing +z; a part's cells are counted in half voxels from its grid's corner (some stand outside
it: a deltoid, a fist, a foot). numpy."""
import json, math, sys
import numpy as np

RES = 2
VF = 0.0275                 # the body's voxel
FV = VF / RES               # a fine cell
BODY = "data/body.json"

BUILDS = {
    # The head (of the game's head: the fine head drawn this much smaller), the neck's radius, the
    # chest's half width and depth, waist, hips, deltoid, upper arm, forearm, thigh, calf radii.
    "champion": dict(head=0.92, neck=0.056, chest=(0.168, 0.118), waist=(0.128, 0.098), hips=(0.152, 0.104),
                     delt=0.066, upper=(0.054, 0.044), fore=(0.047, 0.03), thigh=(0.086, 0.052), calf=(0.056, 0.032),
                     trap=0.036, lat=1.0, belly=0.0),
    "hero": dict(head=0.88, neck=0.066, chest=(0.198, 0.13), waist=(0.118, 0.094), hips=(0.148, 0.102),
                 delt=0.084, upper=(0.067, 0.05), fore=(0.055, 0.033), thigh=(0.099, 0.056), calf=(0.064, 0.035),
                 trap=0.05, lat=1.45, belly=0.0),
    "brute": dict(head=0.98, neck=0.074, chest=(0.19, 0.142), waist=(0.158, 0.13), hips=(0.162, 0.115),
                  delt=0.078, upper=(0.066, 0.052), fore=(0.056, 0.035), thigh=(0.1, 0.06), calf=(0.064, 0.037),
                  trap=0.058, lat=1.1, belly=1.0),
    # The giants of myth (MonsterLook): each a body of its own over the same joints (the game draws
    # him bigger), his head its own (tools/gen_fine_head.py, data/fine_head_<kind>.json). Their
    # palette: what is painted on them other than their skin ([r, g, b, kind, of the skin]), and
    # what their loincloth is.
    "cyclops": dict(head=1.0, neck=0.085, chest=(0.205, 0.15), waist=(0.172, 0.142), hips=(0.172, 0.122),
                    delt=0.088, upper=(0.074, 0.058), fore=(0.064, 0.04), thigh=(0.108, 0.066), calf=(0.07, 0.041),
                    trap=0.068, lat=1.15, belly=1.3, kind="cyclops", paunch=1.3,
                    palette=[[0.14, 0.1, 0.07, 2, 0]], cloth=[0.36, 0.24, 0.14, 8]),
    "polyphemus": dict(head=1.0, neck=0.088, chest=(0.2, 0.15), waist=(0.185, 0.16), hips=(0.175, 0.125),
                       delt=0.082, upper=(0.07, 0.056), fore=(0.062, 0.039), thigh=(0.104, 0.064), calf=(0.068, 0.04),
                       trap=0.066, lat=1.05, belly=1.6, kind="polyphemus", paunch=2.2, mantle=True,
                       palette=[[0.42, 0.38, 0.34, 2, 0], [0.86, 0.83, 0.74, 8, 0]], cloth=[0.82, 0.79, 0.7, 8]),
    "minotaur": dict(head=1.05, neck=0.1, chest=(0.212, 0.152), waist=(0.13, 0.108), hips=(0.152, 0.106),
                     delt=0.092, upper=(0.074, 0.056), fore=(0.062, 0.037), thigh=(0.104, 0.06), calf=(0.068, 0.038),
                     trap=0.08, lat=1.5, belly=0.0, kind="minotaur", hooves=True, tail=True,
                     palette=[[0.62, 0.62, 0.62, 8, 1], [0.13, 0.1, 0.08, 2, 0], [0.1, 0.07, 0.05, 8, 0]], cloth=[0.3, 0.2, 0.12, 8]),
    "troll": dict(head=1.0, neck=0.08, chest=(0.19, 0.15), waist=(0.18, 0.165), hips=(0.162, 0.118),
                  delt=0.074, upper=(0.064, 0.05), fore=(0.06, 0.038), thigh=(0.094, 0.058), calf=(0.06, 0.036),
                  trap=0.07, lat=1.0, belly=1.4, kind="troll", paunch=2.0, hump=True,
                  palette=[[0.25, 0.37, 0.15, 8, 0], [0.8, 0.8, 0.8, 0, 1], [0.86, 0.86, 0.86, 0, 1]], cloth=[0.42, 0.38, 0.27, 1]),
    "titan": dict(head=0.92, neck=0.072, chest=(0.205, 0.134), waist=(0.12, 0.096), hips=(0.15, 0.104),
                  delt=0.088, upper=(0.07, 0.052), fore=(0.058, 0.034), thigh=(0.102, 0.058), calf=(0.066, 0.036),
                  trap=0.054, lat=1.5, belly=0.0, kind="titan",
                  palette=[[1.0, 1.0, 1.0, 4, 1]], cloth=[0.86, 0.66, 0.3, 4]),
}


def nrm(v):
    v = np.asarray(v, float)
    return v / np.linalg.norm(v)


# --- distances (P: a tuple of coordinate arrays) -----------------------------------------------
def ell(P, c, r):
    x = (P[0] - c[0]) / r[0]
    y = (P[1] - c[1]) / r[1]
    z = (P[2] - c[2]) / r[2]
    return (np.sqrt(x * x + y * y + z * z) - 1.0) * min(r)


def cap(P, a, b, ra, rb=None):
    rb = ra if rb is None else rb
    a = np.asarray(a, float)
    b = np.asarray(b, float)
    ab = b - a
    L2 = float(ab @ ab)
    t = np.clip(((P[0] - a[0]) * ab[0] + (P[1] - a[1]) * ab[1] + (P[2] - a[2]) * ab[2]) / L2, 0.0, 1.0)
    dx, dy, dz = P[0] - (a[0] + ab[0] * t), P[1] - (a[1] + ab[1] * t), P[2] - (a[2] + ab[2] * t)
    return np.sqrt(dx * dx + dy * dy + dz * dz) - (ra + (rb - ra) * t)


def smin(a, b, k):
    h = np.clip(k - np.abs(a - b), 0.0, None) / k
    return np.minimum(a, b) - h * h * k * 0.25


# --- the man ------------------------------------------------------------------------------------
class Man:
    """The game's joints (data/body.json), and the man's shapes about them."""

    def __init__(self, parts, B):
        self.B = B
        by = {p["name"]: p for p in parts}
        self.parts = by
        pos = lambda n: np.array(by[n]["pos"], float)
        self.S, self.E, self.W, self.Hj, self.K, self.A = {}, {}, {}, {}, {}, {}
        for sx, side in ((-1, "R"), (1, "L")):
            ua = pos("upperArm" + side)
            fa = pos("forearm" + side)
            th = pos("thigh" + side)
            sh = pos("shin" + side)
            self.S[sx] = ua + np.array(by["upperArm" + side]["ca"])        # the shoulder joint
            self.E[sx] = fa + np.array(by["forearm" + side]["ca"])         # the elbow
            self.W[sx] = fa + np.array([0.0, -0.07, 0.0])                    # the wrist
            self.Hj[sx] = th + np.array(by["thigh" + side]["ca"])          # the hip
            self.K[sx] = sh + np.array(by["shin" + side]["ca"])            # the knee
            self.A[sx] = np.array([sh[0], 0.075, -0.012])                    # the ankle
        self.neck = pos("torso") + np.array(by["head"]["pa"])              # the neck's pivot

    def shapes(self, P):
        """[(part, name, sdf, kind)]: every shape of him, the part it belongs to, and whether it is
        muscle (its edges meeting another's are a groove)."""
        B = self.B
        cw, cd = B["chest"]
        ww, wd = B["waist"]
        hw, hd = B["hips"]
        out = []

        def add(part, name, d, kind="muscle"):
            out.append((part, name, d, kind))

        add("torso", "ribs", ell(P, (0, 1.29, -0.008), (cw, 0.19, cd)))
        add("torso", "waist", ell(P, (0, 1.06, -0.004 + 0.012 * B["belly"]), (ww, 0.15, wd)))
        add("torso", "pelvis", ell(P, (0, 0.935, -0.012), (hw, 0.085, hd)))
        add("torso", "abs", ell(P, (0, 1.065, wd * 0.42 + 0.012 * B["belly"]), (0.082, 0.152, 0.062 + 0.012 * B["belly"])))
        for sx in (-1, 1):
            add("torso", "pec", smin(cap(P, (sx * 0.028, 1.37, cd * 0.74), (sx * 0.22, 1.415, 0.04), 0.058, 0.032),
                                     ell(P, (sx * 0.088, 1.35, cd * 0.6), (0.094, 0.07, 0.054)), 0.03))
            add("torso", "oblique", ell(P, (sx * (ww - 0.012), 1.04, 0.0), (0.055, 0.11, wd * 0.82)))
            add("torso", "lat", smin(ell(P, (sx * 0.13, 1.26, -0.05), (0.078 * B["lat"], 0.15, 0.066)),
                                     cap(P, (sx * 0.08, 1.11, -0.065), (sx * 0.235, 1.395, -0.02), 0.045, 0.034), 0.03))
            add("torso", "glute", ell(P, (sx * 0.07, 0.905, -0.068), (0.08, 0.09, 0.066)))
            add("torso", "erector", cap(P, (sx * 0.034, 0.95, -0.086), (sx * 0.03, 1.4, -0.088), 0.03, 0.022))
            add("torso", "trap", cap(P, (0, 1.56, -0.055), (sx * 0.245, 1.468, -0.024), B["trap"] + 0.004, 0.028))
            add("torso", "trapb", ell(P, (sx * 0.12, 1.5, -0.034), (0.085, 0.036 + B["trap"] * 0.35, 0.05)))
            add("torso", "cuff", cap(P, (sx * 0.11, 1.468, -0.008), (sx * 0.275, 1.462, 0.0), 0.046, 0.052))
            add("torso", "scm", cap(P, (sx * 0.05, 1.625, -0.012), (sx * 0.017, 1.478, 0.05), 0.017))
        add("torso", "upperback", ell(P, (0, 1.39, -0.066), (0.11, 0.1, 0.052)))
        add("torso", "neck", cap(P, (0, 1.44, -0.016), (0, 1.62, 0.0), B["neck"], B["neck"] * 0.9))
        for sx, side in ((-1, "R"), (1, "L")):
            S, E, W = self.S[sx], self.E[sx], self.W[sx]
            u = nrm(E - S)
            f = nrm(W - E)
            ua, ub = B["upper"]
            fa, fb = B["fore"]
            up, fo = "upperArm" + side, "forearm" + side
            add(up, "delt", ell(P, S + u * 0.03 + np.array([sx * 0.008, -0.01, 0]), (B["delt"], 0.1, B["delt"] * 1.06)))
            add(up, "upper", cap(P, S, E, ua, ub * 0.92))
            mid = S + u * 0.2
            add(up, "biceps", ell(P, mid + np.array([0, -0.01, 0.022]), (ua * 0.72, 0.105, ua * 0.74)))
            add(up, "triceps", ell(P, mid + np.array([sx * 0.004, 0.02, -0.024]), (ua * 0.78, 0.125, ua * 0.74)))
            add(fo, "fore", cap(P, E, W, fa, fb))
            add(fo, "brachio", ell(P, E + f * 0.07 + np.array([sx * 0.016, 0, 0.012]), (fa * 0.78, 0.075, fa * 0.78)))
            add(fo, "flexor", ell(P, E + f * 0.08 + np.array([-sx * 0.012, 0, -0.008]), (fa * 0.74, 0.08, fa * 0.74)))
            # The fist closed round the grip (the weapon runs on out of it along the forearm): the
            # knuckles forward, the thumb across the front of the fingers.
            fc = W + f * 0.055 + np.array([0, 0, 0.006])
            add(fo, "fist", ell(P, fc, (0.041, 0.052, 0.047)), "skin")
            add(fo, "knuckles", ell(P, fc + np.array([0, -0.006, 0.026]), (0.04, 0.03, 0.026)), "skin")
            add(fo, "thumb", cap(P, fc + np.array([-sx * 0.022, 0.02, 0.028]), fc + np.array([-sx * 0.004, -0.006, 0.044]), 0.013, 0.011), "skin")
        for sx, side in ((-1, "R"), (1, "L")):
            Hj, K, A = self.Hj[sx], self.K[sx], self.A[sx]
            ta, tb = B["thigh"]
            ca, cb = B["calf"]
            th, sh = "thigh" + side, "shin" + side
            add(th, "thigh", cap(P, Hj + np.array([sx * 0.02, 0.03, 0]), K, ta, tb))
            add(th, "vlat", ell(P, (sx * 0.155, 0.66, 0.012), (ta * 0.58, 0.17, ta * 0.7)))
            add(th, "vmed", ell(P, (sx * 0.075, 0.525, 0.032), (ta * 0.5, 0.068, ta * 0.52)))
            add(th, "rfem", ell(P, (sx * 0.115, 0.7, 0.048), (ta * 0.52, 0.16, ta * 0.46)))
            add(th, "ham", ell(P, (sx * 0.11, 0.665, -0.045), (ta * 0.7, 0.17, ta * 0.58)))
            add(th, "adductor", ell(P, (sx * 0.06, 0.745, 0.0), (ta * 0.52, 0.12, ta * 0.68)))
            add(sh, "knee", ell(P, K + np.array([0, 0.005, 0.032]), (0.042, 0.042, 0.032)), "skin")
            add(sh, "shin", cap(P, K, A + np.array([0, 0.02, 0]), ca, cb))
            add(sh, "gmed", ell(P, (sx * 0.09, 0.33, -0.044), (ca * 0.76, 0.092, ca * 0.76)))
            add(sh, "glat", ell(P, (sx * 0.134, 0.345, -0.04), (ca * 0.64, 0.08, ca * 0.66)))
            add(sh, "tib", ell(P, (sx * 0.126, 0.3, 0.028), (ca * 0.46, 0.11, ca * 0.44)))
            add(sh, "achilles", cap(P, (sx * 0.11, 0.21, -0.047), (sx * 0.11, 0.055, -0.052), 0.013), "skin")
            add(sh, "heel", ell(P, (sx * 0.11, 0.036, -0.052), (0.032, 0.036, 0.038)), "skin")
            add(sh, "foot", ell(P, (sx * 0.118, 0.032, 0.05), (0.045, 0.031, 0.105)), "skin")
            add(sh, "toes", ell(P, (sx * 0.126, 0.017, 0.152), (0.046, 0.018, 0.036)), "skin")
            add(sh, "ankle", ell(P, A + np.array([0, 0.005, 0]), (0.034, 0.03, 0.034)), "skin")
        # A giant's own: a paunch, a hump, knobbed joints and big feet, warts; hooves and a tail.
        if B.get("paunch"):
            b = B["paunch"]
            add("torso", "paunch", ell(P, (0, 1.03, 0.05 + 0.022 * b), (0.13 + 0.018 * b, 0.13 + 0.01 * b, 0.075 + 0.03 * b)), "skin")
        if B.get("hump"):
            add("torso", "hump", ell(P, (0, 1.43, -0.085), (0.17, 0.12, 0.085)))
            for sx, side in ((-1, "R"), (1, "L")):
                add("upperArm" + side, "knob_e", ell(P, self.E[sx] + np.array([0, 0.0, -0.03]), (0.045, 0.045, 0.04)), "skin")
                add("thigh" + side, "knob_k", ell(P, self.K[sx] + np.array([0, 0.0, 0.035]), (0.05, 0.05, 0.04)), "skin")
                add("shin" + side, "bigfoot", ell(P, (sx * 0.12, 0.035, 0.06), (0.058, 0.04, 0.125)), "skin")
            rng = np.random.default_rng(7)
            for i in range(13):
                c = np.array([rng.uniform(0.02, 0.25), rng.uniform(1.0, 1.5), rng.uniform(-0.16, 0.16)])
                for sx in (-1.0, 1.0):   # (in pairs, the same both sides)
                    add("torso", "wart", ell(P, c * np.array([sx, 1.0, 1.0]), (0.012, 0.012, 0.012)), "skin")
        if B.get("hooves"):
            for sx, side in ((-1, "R"), (1, "L")):
                add("shin" + side, "hoof", cap(P, (sx * 0.118, 0.0, 0.035), (sx * 0.118, 0.07, 0.03), 0.06, 0.052), "skin")
        if B.get("tail"):
            # (straight down his back's middle: swung off to one side it was the one thing on him
            # not the same both sides)
            pts = [np.array(q) for q in ((0, 0.97, -0.115), (0.0, 0.9, -0.18), (0.0, 0.8, -0.2), (0.0, 0.7, -0.18), (0.0, 0.6, -0.16), (0.0, 0.55, -0.15))]
            for i in range(len(pts) - 1):
                add("torso", "tail", cap(P, pts[i], pts[i + 1], 0.016, 0.014), "skin")
            add("torso", "tuft", ell(P, (0.0, 0.5, -0.15), (0.03, 0.06, 0.03)), "skin")
        return out

    def field(self, P):
        """The skin's distance (negative inside), the shape nearest each point, the margin to the
        next one (a groove where two muscles meet), and the parts of the shapes."""
        sh = self.shapes(P)
        D = np.stack([d for _, _, d, _ in sh], 0)
        d = D[0]
        for k in range(1, len(sh)):
            d = smin(d, D[k], 0.022)
        d = np.maximum(d, -P[1])
        self.wool = None
        if self.B.get("mantle"):
            X, Y, Z = P
            lump = 0.008 * np.sin(X * 90.0) * np.sin(Y * 70.0 + Z * 50.0)
            band = (d < 0.03 + lump) & (d > -0.004)
            mant = band & (Z < -0.03 + 0.02 * np.sin(Y * 30.0)) & (Y > 0.7 + 0.06 * np.sin(X * 40.0)) & (Y < 1.53) & (np.abs(X) < 0.29)
            mant |= band & (Y > 1.41) & (Y < 1.53) & (np.abs(X) < 0.3) & (Z < 0.07)
            self.wool = mant & (d >= 0.0)
            d = np.where(mant, np.minimum(d, -0.0005), d)
        order = np.argsort(D, axis=0)
        first = order[0]
        gap = np.take_along_axis(D, order[1:2], 0)[0] - np.take_along_axis(D, order[0:1], 0)[0]
        d1 = np.take_along_axis(D, order[0:1], 0)[0]
        return d, first, gap, d1, sh


# --- which part a point of him is drawn with ---------------------------------------------------
# Round a joint both parts are drawn, so a bent limb closes over it (the shoulder and the hip
# larger: the limb is thicker there).
JOINT_R = {"shoulder": 0.075, "elbow": 0.055, "hip": 0.085, "knee": 0.06}


def part_of(man, P):
    """For every point, the part it is drawn with: the bone it is nearest, each limb's by its own
    thickness, the trunk's by its own."""
    segs = []
    for sx, side in ((-1, "R"), (1, "L")):
        segs.append(("upperArm" + side, man.S[sx], man.E[sx], 0.06))
        segs.append(("forearm" + side, man.E[sx], man.W[sx] + np.array([0, -0.11, 0]), 0.06))
        segs.append(("thigh" + side, man.Hj[sx], man.K[sx], 0.08))
        segs.append(("shin" + side, man.K[sx], man.A[sx] + np.array([0, -0.06, 0.0]), 0.06))
    names = ["torso"] + [s[0] for s in segs]
    best = np.full(P[0].shape, np.inf)
    who = np.zeros(P[0].shape, np.int32)
    # The trunk: its own spine and its breadth.
    # (Narrow enough that the inside of an arm hanging by his side is the arm's: drawn with the trunk
    # it stayed by his hip, a bar in the air, when the arm came up.)
    tr = np.maximum(0.0, np.abs(P[0]) - 0.09) / 0.13 + np.maximum(0.0, P[1] - 1.5) / 0.1 + np.maximum(0.0, 0.9 - P[1]) / 0.08
    best = tr
    for k, (n, a, b, r) in enumerate(segs):
        d = cap(P, a, b, 0.0) / r
        m = d < best
        best = np.where(m, d, best)
        who = np.where(m, k + 1, who)
    return names, who


def joints_of(man):
    """Each joint: its pivot, the two parts that meet there, and the ball both draw round it."""
    js = []
    for sx, side in ((-1, "R"), (1, "L")):
        js.append((man.S[sx], "torso", "upperArm" + side, JOINT_R["shoulder"]))
        js.append((man.E[sx], "upperArm" + side, "forearm" + side, JOINT_R["elbow"]))
        js.append((man.Hj[sx], "torso", "thigh" + side, JOINT_R["hip"]))
        js.append((man.K[sx], "thigh" + side, "shin" + side, JOINT_R["knee"]))
    return js


# --- a part's cells ------------------------------------------------------------------------------
NA = 32    # ways round a part's line for its outline and its map
CELL = 9   # a cell's numbers: ix, iy, iz (fine, from the grid's corner), cx, cy, cz (its voxel), shade, ao, paint
AO_FACES = [((1, 0, 0), 1, 2), ((-1, 0, 0), 1, 2), ((0, 1, 0), 0, 2), ((0, -1, 0), 0, 2), ((0, 0, 1), 0, 1), ((0, 0, -1), 0, 1)]
MARGIN = 10   # fine cells round the part's grid (a deltoid, a fist and a foot stand out of it)


def _shift(a, d):
    out = np.zeros_like(a)
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


def part_cells(man, name, pdef):
    """The part's skin cells and its voxels' inner cells."""
    g = np.array(pdef["grid"])
    pos = np.array(pdef["pos"], float)
    lo = -g * VF * 0.5 - MARGIN * FV                     # the lattice's corner, part frame
    n = g * RES + 2 * MARGIN
    ix = [np.arange(n[a]) for a in range(3)]
    IX, IY, IZ = np.meshgrid(*ix, indexing="ij")
    X = pos[0] + lo[0] + (IX + 0.5) * FV
    Y = pos[1] + lo[1] + (IY + 0.5) * FV
    Z = pos[2] + lo[2] + (IZ + 0.5) * FV
    P = (X, Y, Z)
    d, first, gap, d1, sh = man.field(P)
    names, who = part_of(man, P)
    mine = who == names.index(name)
    # Round a joint, both parts that meet there (inside the ball about its pivot).
    for piv, a, b, jr in joints_of(man):
        if name in (a, b):
            r = np.sqrt((X - piv[0]) ** 2 + (Y - piv[1]) ** 2 + (Z - piv[2]) ** 2)
            mine |= r < jr
    inside = d < 0.0
    occ = inside & mine
    # The skin: his cells with the outside of the part next to them. Not only the outside of him:
    # where the part ends inside him (the ball round a joint, the end of its share of him) it is
    # closed too, so a bent elbow or a raised arm opens on him, never on nothing.
    out_n = np.zeros_like(inside)
    for ax in range(3):
        for dl in (-1, 1):
            dd = [0, 0, 0]
            dd[ax] = dl
            out_n |= ~_shift(occ, (-dd[0], -dd[1], -dd[2]))
    skin = occ & out_n
    # The shade the muscles give the skin: a groove where two meet, darker; the lines of the
    # abdomen, the nipples, the navel.
    kinds = np.array([k for _, _, _, k in sh])
    groove = (gap < 0.0028) & (d1 > -0.007) & (kinds[first] == "muscle")
    shade = np.full(X.shape, 200, np.int32)
    shade[groove] = 176
    front = Z > 0.03
    abs_l = front & (np.abs(X) < 0.07) & ((np.abs(Y - 1.172) < FV * 0.5) | (np.abs(Y - 1.106) < FV * 0.5) | (np.abs(Y - 1.04) < FV * 0.5))
    abs_l |= front & (np.abs(X) < FV * 0.5) & (Y > 0.99) & (Y < 1.22)
    shade[abs_l & (name == "torso")] = 170
    for sx in (-1, 1):
        shade[(np.abs(X - sx * 0.096) < 0.009) & (np.abs(Y - 1.34) < 0.009) & front & (name == "torso")] = 128
    shade[(np.abs(X) < 0.008) & (np.abs(Y - 1.0) < 0.008) & front & (name == "torso")] = 100
    # Corner shading against the whole of him (VoxelPart.ao_bits).
    ao = np.zeros(X.shape, np.int64)
    at = lambda dd: _shift(inside, (-dd[0], -dd[1], -dd[2]))
    for fi, (fn, ua, va) in enumerate(AO_FACES):
        open_face = ~at(fn)
        for c in range(4):
            du = [0, 0, 0]
            du[ua] = 1 if c & 1 else -1
            dv = [0, 0, 0]
            dv[va] = 1 if c & 2 else -1
            a1 = at((fn[0] + du[0], fn[1] + du[1], fn[2] + du[2]))
            b1 = at((fn[0] + dv[0], fn[1] + dv[1], fn[2] + dv[2]))
            c1 = at((fn[0] + du[0] + dv[0], fn[1] + du[1] + dv[1], fn[2] + du[2] + dv[2]))
            ao |= np.where(skin & open_face & (a1 | b1 | c1), 1 << (fi * 4 + c), 0)
    # His outline by fine row and angle round the part's own line (x = z = 0 in its frame), and
    # how much of the part's box that is each way: the box is drawn mapped onto him (k), so every
    # voxel of it lies somewhere on him, the outer ones on his skin.
    lx = lo[0] + (IX + 0.5) * FV
    lz = lo[2] + (IZ + 0.5) * FV
    rows = int(n[1])
    ang = (np.floor((np.arctan2(lz, lx) + math.pi) / (2 * math.pi) * NA).astype(int)) % NA
    rad = np.sqrt(lx * lx + lz * lz)
    prof = np.zeros((rows, NA))
    np.maximum.at(prof, (IY[occ], ang[occ]), rad[occ] + FV * 0.5)
    prof = _fill(prof)
    th = (np.arange(NA) + 0.5) / NA * 2 * math.pi - math.pi
    hx, hz = g[0] * VF * 0.5, g[2] * VF * 0.5
    rbox = np.minimum(hx / np.maximum(np.abs(np.cos(th)), 1e-6), hz / np.maximum(np.abs(np.sin(th)), 1e-6))
    K = np.clip(prof / rbox[None, :], 0.25, 3.0)
    ylo = lo[1]
    # The voxel each cell lies over: where on the box its place on him maps back to.
    sx_, sy_, sz_ = lx[skin], lo[1] + (IY[skin] + 0.5) * FV, lz[skin]
    kk = _k_at(K, ylo, sx_, sy_, sz_)
    bx, by, bz = sx_ / kk, sy_, sz_ / kk
    half = g * VF * 0.5
    cx = np.clip(np.floor((bx + half[0]) / VF).astype(int), 0, g[0] - 1)
    cy = np.clip(np.floor((by + half[1]) / VF).astype(int), 0, g[1] - 1)
    cz = np.clip(np.floor((bz + half[2]) / VF).astype(int), 0, g[2] - 1)
    # What is on the box's outside other than skin (a baldric, the belt, the loincloth, a
    # sandal's straps): a cell near one is drawn as it, so a strap a voxel wide reads as a strap on
    # him, not as a dashed line where the cells happen to fall on it.
    deco = _decorations(name, pdef)
    if deco.any():
        best = np.full(cx.shape, np.inf)
        nx, ny, nz = cx.copy(), cy.copy(), cz.copy()
        for ox in (-1, 0, 1):
            for oy in (-1, 0, 1):
                for oz in (-1, 0, 1):
                    qx = np.clip(cx + ox, 0, g[0] - 1)
                    qy = np.clip(cy + oy, 0, g[1] - 1)
                    qz = np.clip(cz + oz, 0, g[2] - 1)
                    dd = (bx - (-half[0] + (qx + 0.5) * VF)) ** 2 + (by - (-half[1] + (qy + 0.5) * VF)) ** 2 + (bz - (-half[2] + (qz + 0.5) * VF)) ** 2
                    m = deco[qx, qy, qz] & (dd < (0.85 * VF) ** 2) & (dd < best)
                    best[m] = dd[m]
                    nx[m], ny[m], nz[m] = qx[m], qy[m], qz[m]
        cx, cy, cz = nx, ny, nz
    paint = _paint(man, P, d, first, sh, skin)
    idx = np.argwhere(skin)
    cells = np.stack([idx[:, 0] - MARGIN, idx[:, 1] - MARGIN, idx[:, 2] - MARGIN, cx, cy, cz, shade[skin], ao[skin], paint[skin]], 1).astype(np.int64)
    cells = [int(v) for v in cells.reshape(-1)]
    # Each voxel's eight half cells, where they map to on him: inside him (and his part's, or the
    # joint's) and how deep: 1 skin, 2 the fat under it, 3 the voxel's own flesh, organ or bone.
    # Two bits a cell.
    si = [np.arange(g[a] * RES) for a in range(3)]
    SI, SJ, SK = np.meshgrid(*si, indexing="ij")
    px = -half[0] + (SI + 0.5) * FV
    py = -half[1] + (SJ + 0.5) * FV
    pz = -half[2] + (SK + 0.5) * FV
    k2 = _k_at(K, ylo, px, py, pz)
    MP = (pos[0] + px * k2, pos[1] + py, pos[2] + pz * k2)
    d2, _, _, _, _ = man.field(MP)
    nm2, who2 = part_of(man, MP)
    mine2 = who2 == nm2.index(name)
    for piv, a, b, jr in joints_of(man):
        if name in (a, b):
            r = np.sqrt((MP[0] - piv[0]) ** 2 + (MP[1] - piv[1]) ** 2 + (MP[2] - piv[2]) ** 2)
            mine2 |= r < jr
    depth = -d2
    code = np.where((d2 < 0) & mine2, np.where(depth < FV, 1, np.where(depth < 2.2 * FV, 2, 3)), np.where(d2 < 0, 3, 0))
    sub = np.zeros(tuple(g), np.int64)
    for a in range(RES):
        for b in range(RES):
            for c in range(RES):
                s = a + RES * b + RES * RES * c
                sub |= code[a::RES, b::RES, c::RES].astype(np.int64) << (2 * s)
    return {"lo": [MARGIN, MARGIN, MARGIN], "cells": cells, "sub": [int(v) for v in sub.reshape(-1)],
            "prof": [[round(float(v), 4) for v in row] for row in prof], "k": [[round(float(v), 4) for v in row] for row in K]}


def _paint(man, P, d, first, sh, skin):
    """What is painted on a giant's skin (an index into his palette, 0 his skin)."""
    B = man.B
    k = B.get("kind", "")
    X, Y, Z = P
    paint = np.zeros(X.shape, np.int64)
    if k == "":
        return paint
    # (each cell's fleck the same as its mirror's: a giant is the same both sides)
    ix, iy, iz = (np.floor(np.abs(X) / FV)).astype(np.int64), (np.floor(Y / FV)).astype(np.int64), (np.floor(Z / FV)).astype(np.int64)
    hh = (ix * 73856093) ^ (iy * 19349663) ^ (iz * 83492791) ^ 3
    hh = (hh ^ (hh >> 13)) * 1274126177
    noise = ((hh ^ (hh >> 16)) & 0xFFFF).astype(np.float64) / 65536.0
    names = np.array([n for _, n, _, _ in sh])
    nm = names[first]
    if k in ("cyclops", "polyphemus"):
        hairy = (Z > 0.04) & (((Y > 1.18) & (Y < 1.4) & (np.abs(X) < 0.12)) | ((Y > 1.0) & (Y < 1.18) & (np.abs(X) < 0.03)))
        paint[hairy & (noise < 0.55)] = 1
    if k == "polyphemus" and man.wool is not None:
        paint[man.wool] = 2
    if k == "minotaur":
        furry = (Y > 1.28) | ((Z < -0.05) & (Y > 1.0)) | (nm == "tail")
        paint[furry] = 1
        paint[nm == "hoof"] = 2
        paint[nm == "tuft"] = 3
    if k == "troll":
        patch = (np.sin(np.abs(X) * 31.0) + np.sin(Z * 27.0 + Y * 13.0)) > 0.4
        paint[((Y > 1.42) | ((Z < -0.09) & (Y > 1.2))) & patch & (noise < 0.8)] = 1
        paint[nm == "wart"] = 2
        paint[(paint == 0) & (noise < 0.18)] = 3
    if k == "titan":
        paint[:] = 1
    return paint


def _decorations(name, pdef):
    """The part's voxels on the outside of its box that are not skin (Fighter.build: a voxel of
    layer 0 or 2 on the box's surface; a sandal's straps on a shin, Fighter._strap)."""
    g = np.array(pdef["grid"])
    deco = np.zeros(tuple(g), bool)
    for v in pdef["voxels"]:
        x, y, z, layer = int(v[0]), int(v[1]), int(v[2]), int(v[3])
        surface = x in (0, g[0] - 1) or y in (0, g[1] - 1) or z in (0, g[2] - 1)
        if layer != 1 and surface:
            deco[x, y, z] = True
        elif layer == 1 and name.startswith("shin") and 4 <= y <= 8 and (y in (4, 7) or (z == g[2] - 1 and ((x + y) % 4 == 0 or (x - y + 16) % 4 == 0))):
            deco[x, y, z] = True
    return deco


def _fill(prof):
    """Rows and ways no cell of him reaches: as the nearest that has one (the box is still mapped)."""
    prof = prof.copy()
    rows, na = prof.shape
    for r in range(rows):
        row = prof[r]
        if row.max() <= 0:
            continue
        for _ in range(na):
            empty = row <= 0
            if not empty.any():
                break
            row[empty] = np.maximum(np.roll(row, 1), np.roll(row, -1))[empty]
    has = np.where(prof.max(1) > 0)[0]
    if has.size == 0:
        return prof + 0.05
    for r in range(rows):
        if prof[r].max() <= 0:
            prof[r] = prof[has[np.argmin(np.abs(has - r))]]
    return prof


def _k_at(K, ylo, x, y, z):
    """The map's factor at (x, y, z) of the part's box (part frame): bilinear in the row (by y)
    and the way round (FineBody.k_at does the same)."""
    rows, na = K.shape
    fr = np.clip((y - ylo) / FV - 0.5, 0, rows - 1)
    r0 = np.floor(fr).astype(int)
    r1 = np.minimum(r0 + 1, rows - 1)
    wr = fr - r0
    fa = (np.arctan2(z, x) + math.pi) / (2 * math.pi) * na - 0.5
    a0f = np.floor(fa)
    wa = fa - a0f
    a0 = a0f.astype(int) % na
    a1 = (a0 + 1) % na
    k0 = K[r0, a0] * (1 - wa) + K[r0, a1] * wa
    k1 = K[r1, a0] * (1 - wa) + K[r1, a1] * wa
    return k0 * (1 - wr) + k1 * wr


def main(out):
    parts = json.load(open(BODY))["parts"]
    data = {"res": RES, "margin": MARGIN, "na": NA, "builds": {}}
    for bn, B in BUILDS.items():
        man = Man(parts, B)
        bd = {"head": B["head"], "parts": {}}
        if B.get("palette"):
            bd["palette"] = B["palette"]
        if B.get("cloth"):
            bd["cloth"] = B["cloth"]
        for p in parts:
            if p["name"] == "head":
                continue
            bd["parts"][p["name"]] = part_cells(man, p["name"], p)
        data["builds"][bn] = bd
        print(bn, {k: len(v["cells"]) // CELL for k, v in bd["parts"].items()}, flush=True)
    with open(out, "w") as fh:
        json.dump(data, fh, separators=(",", ":"))
    print("->", out)


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "data/fine_body.json")
