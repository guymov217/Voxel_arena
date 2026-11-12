#!/usr/bin/env python3
"""The fine body: a man as he is built, drawn in voxels half the size of the body's own, over the
game's own parts and joints (the colliders, the voxels that are hit, cut and bled are the game's;
drawing only). Three builds: the champion (lean, a lighter fighter), the hero (broad back, narrow
waist) and the brute (heavy, a belly, a bull neck). Every cell of each part's skin with the body
voxel it lies over and the shade the muscles under it give it; for every body voxel, which of its
eight half-size cells are inside the man and how deep (what a wound opens on: skin, fat, then the
voxel's own flesh, organ or bone); the outline of each limb by height and angle (where armour is
laid); the size of his head (the fine head drawn smaller: tools/gen_fine_head.py). The three
fighters in broad forms only (Man.shapes_chunky: a sculptor's blocking out, chunky in voxels, not
every small muscle and groove); the giants with all of theirs.

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

# What is painted on a fighter other than his own voxels' colours (_paint: his feet in their
# sandals; the game's own voxels there are a boot's): his skin, a strap, the sole.
SANDAL = [[1.0, 1.0, 1.0, 0, 1], [0.36, 0.23, 0.13, 2, 0], [0.13, 0.085, 0.05, 2, 0]]
FOOT_TOP = 0.108   # under the first of the straps round his ankle (the game's own voxels from there up)

BUILDS = {
    # The head (of the game's head: the fine head drawn this much smaller), the neck's radius, the
    # chest's half width and depth, waist, hips, deltoid, upper arm, forearm, thigh, calf radii.
    "champion": dict(head=0.92, neck=0.056, chest=(0.168, 0.118), waist=(0.128, 0.098), hips=(0.152, 0.104),
                     delt=0.066, upper=(0.054, 0.044), fore=(0.047, 0.03), thigh=(0.086, 0.052), calf=(0.056, 0.032),
                     trap=0.036, lat=1.0, belly=0.0, palette=SANDAL),
    "hero": dict(head=0.88, neck=0.066, chest=(0.198, 0.13), waist=(0.118, 0.094), hips=(0.148, 0.102),
                 delt=0.084, upper=(0.067, 0.05), fore=(0.055, 0.033), thigh=(0.099, 0.056), calf=(0.064, 0.035),
                 trap=0.05, lat=1.45, belly=0.0, palette=SANDAL),
    "brute": dict(head=0.98, neck=0.074, chest=(0.19, 0.142), waist=(0.158, 0.13), hips=(0.162, 0.115),
                  delt=0.078, upper=(0.066, 0.052), fore=(0.056, 0.035), thigh=(0.1, 0.06), calf=(0.064, 0.037),
                  trap=0.058, lat=1.1, belly=1.0, palette=SANDAL),
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


# The three fighters' arms and legs heavier with muscle than their builds' radii (user; and a
# little more again, with the bellies of their muscles on them, shapes_chunky).
LIMB_K = {"upper": 1.15, "fore": 1.12, "delt": 1.1, "thigh": 1.12, "calf": 1.12}
# How full the bellies of the limbs' muscles are (shapes_chunky), of the limb's own thickness.
BELLY = {"arm": 0.84, "fore": 0.8, "thigh": 0.78, "calf": 0.8}
# How lean a fighter's leg is where it is not muscle, of his build's radii: at the hip, the mass
# of the thigh, the thigh's end at the knee, the shin's top there, and the ankle.
LEAN = {"hip": 0.96, "quad": 0.93, "knee": 0.88, "shin": 0.78, "ankle": 0.9}
# A fighter's flanks (shapes_chunky): how far out past the waist's own half width they stand, and
# how thick they are; and how far over the hip joint the thigh's round top is.
FLANK = 0.046
FLANK_R = 0.06
FLANK_HIP = 0.032   # thicker by this much where they meet the hips
FLANK_MAX = 0.176   # (a man thick in the waist already has them)
HIP_UP = 0.03


# A fighter's foot (user: better feet; one egg of a shape, it read as a boot's lump): where its
# middle line lies out from the shin's (the middle of a fine cell, so its toes fall on whole
# cells), and the foot.
FOOT_X = 0.11 + FV * 0.5


def foot(P, sx):
    """The heel, the instep down from the ankle to the ball of the foot, the ball its widest, and
    the toes: the big one inside and the longest, the others shorter out to the little one. Its
    own shapes run together closely (the body's are blended wide, and it was a lump again)."""
    x0 = sx * FOOT_X
    d = ell(P, (sx * 0.113, 0.034, -0.046), (0.033, 0.04, 0.035))                             # the heel
    d = smin(d, cap(P, (sx * 0.112, 0.06, -0.004), (x0, 0.028, 0.088), 0.036, 0.026), 0.016)   # the instep
    d = smin(d, ell(P, (x0, 0.022, 0.092), (0.05, 0.026, 0.046)), 0.016)                       # the ball
    d = smin(d, ell(P, (x0 - sx * 0.031, 0.016, 0.142), (0.019, 0.018, 0.03)), 0.012)          # the big toe
    d = smin(d, ell(P, (x0 + sx * 0.006, 0.014, 0.136), (0.022, 0.016, 0.03)), 0.012)          # the toes beside it
    d = smin(d, ell(P, (x0 + sx * 0.03, 0.013, 0.124), (0.02, 0.015, 0.028)), 0.012)           # out to the little one
    return d


def back_v2(P, B, add):
    """A fighter's back (user): flat across (the rib cage cut off behind, a plane, not a dome rising
    to its middle), two ridges down the spine with the groove between them, the lats broad up by
    the shoulder blades and drawn in to a narrow waist."""
    cw, cd = B["chest"]
    zb = -0.008 - cd * 0.78
    add("torso", "ribs", np.maximum(ell(P, (0, 1.29, -0.008), (cw, 0.19, cd)), zb - P[2]))
    for sx in (-1, 1):
        add("torso", "lat", smin(ell(P, (sx * 0.128, 1.335, -0.05), (0.088, 0.13, 0.062)),
                                 cap(P, (sx * 0.075, 1.08, -0.06), (sx * 0.215, 1.405, -0.03), 0.04, 0.034), 0.03))
        add("torso", "erector", cap(P, (sx * 0.036, 0.97, zb + 0.022), (sx * 0.034, 1.42, zb + 0.016), 0.026, 0.02))


# --- the man ------------------------------------------------------------------------------------
class Man:
    """The game's joints (data/body.json), and the man's shapes about them."""

    def __init__(self, parts, B, plain=False):
        # (`plain`: a fighter in his broad forms alone, no belly to a muscle and his foot one
        # shape: what the fight reads of him is read off that, part_cells' "keep".)
        self.plain = plain
        self.made_of = (parts, B)
        if not B.get("kind"):
            B = dict(B)
            for k, m in LIMB_K.items():
                B[k] = tuple(v * m for v in B[k]) if isinstance(B[k], tuple) else B[k] * m
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
        self.hinge = {}

    def shapes(self, P):
        """[(part, name, sdf, kind)]: every shape of him, the part it belongs to, and whether it is
        muscle (its edges meeting another's are a groove)."""
        return self.shapes_full(P) if self.B.get("kind") else self.shapes_chunky(P)

    def shapes_full(self, P):
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

    def shapes_chunky(self, P):
        """His broad forms only, as a sculptor blocks a man out: the chest, the waist and the hips,
        a plate of the belly, the pectorals, the back (back_v2), the shoulders, the arms and legs
        each one mass with the swell of its muscle, a fist, a foot."""
        B = self.B
        ww, wd = B["waist"]
        hw, hd = B["hips"]
        cd = B["chest"][1]
        out = []

        def add(part, name, d, kind="muscle"):
            out.append((part, name, d, kind))

        back_v2(P, B, add)
        zb = -0.008 - cd * 0.78   # (the flat of his back, as back_v2 cuts it)
        add("torso", "waist", ell(P, (0, 1.06, -0.004 + 0.012 * B["belly"]), (ww + 0.006, 0.16, wd)))
        add("torso", "pelvis", ell(P, (0, 0.935, -0.012), (hw, 0.09, hd)))
        # His flanks: the trunk goes down into the hips without a step (user: the pelvis must join
        # the trunk as a man's does, no strange change of thickness; a waist half as wide as the
        # hips stood on them like a post on a shelf).
        fr = FLANK_R
        for sx in (-1, 1):
            fx = sx * (min(ww + FLANK, FLANK_MAX) - fr)
            add("torso", "flank", cap(P, (fx, 1.06, -0.006), (fx, 1.195, -0.006), fr))
            add("torso", "flank", cap(P, (fx, 0.94, -0.006), (fx, 1.06, -0.006), fr + FLANK_HIP, fr))
        add("torso", "abs", ell(P, (0, 1.07, wd * 0.38 + 0.012 * B["belly"]), (0.084, 0.16, 0.06 + 0.012 * B["belly"])))
        for sx in (-1, 1):
            add("torso", "pec", ell(P, (sx * 0.086, 1.355, cd * 0.6), (0.1, 0.075, 0.058)))
            add("torso", "glute", ell(P, (sx * 0.07, 0.905, -0.066), (0.08, 0.09, 0.066)))
            # The trapezius: a slope from the neck down to the shoulder, and the flat of it under
            # the slope, down between the shoulder blades (user: something strange on his back, at
            # the trapezius by the neck. A beam alone, it lay on the shoulders like a roll round
            # the neck, a fold under it across the back and a hump behind the neck).
            add("torso", "trap", cap(P, (0, 1.54, -0.036), (sx * 0.235, 1.47, -0.026), B["trap"], 0.03))
            add("torso", "trapb", ell(P, (sx * 0.105, 1.45, zb + 0.058), (0.125, 0.075, 0.058)))
            # (The shoulder's own mass between the trapezius and the deltoid: without it a raised
            # arm left the big cells open there, holes at the top of the back.)
            add("torso", "cuff", cap(P, (sx * 0.11, 1.468, -0.012), (sx * 0.27, 1.46, -0.004), 0.05, 0.055))
        add("torso", "nape", ell(P, (0, 1.43, zb + 0.052), (0.1, 0.11, 0.052)))
        add("torso", "neck", cap(P, (0, 1.44, -0.016), (0, 1.62, 0.0), B["neck"], B["neck"] * 0.92))
        for sx, side in ((-1, "R"), (1, "L")):
            S, E, W = self.S[sx], self.E[sx], self.W[sx]
            u = nrm(E - S)
            f = nrm(W - E)
            ua, ub = B["upper"]
            fa, fb = B["fore"]
            up, fo = "upperArm" + side, "forearm" + side
            add(up, "delt", ell(P, S + u * 0.03 + np.array([sx * 0.008, -0.01, 0]), (B["delt"], 0.1, B["delt"] * 1.04)))
            add(up, "upper", cap(P, S, E, ua, ub * 0.92))
            add(up, "arm", ell(P, S + u * 0.19 + np.array([0, 0.0, 0.004]), (ua * 0.86, 0.12, ua * 0.92)))
            # The arm's two muscles, each a belly of its own (user: a little more muscle on his
            # arms and legs, and the muscles of his limbs to be seen): the biceps in front, the
            # triceps behind and a little to the outside.
            ka, kf = BELLY["arm"], BELLY["fore"]
            if not self.plain:
                # (Both a little to the outside of the arm's line: fuller inward, the arm ran
                # into his side and the trunk's share of him grew out under the arm.)
                add(up, "biceps", ell(P, S + u * 0.205 + np.array([sx * 0.01, 0, ua * 0.36]), (ua * 0.6 * ka, 0.1, ua * 0.7 * ka)))
                add(up, "triceps", ell(P, S + u * 0.17 + np.array([sx * 0.016, 0, -ua * 0.38]), (ua * 0.64 * ka, 0.11, ua * 0.68 * ka)))
            add(fo, "fore", cap(P, E, W, fa, fb))
            add(fo, "forearm", ell(P, E + f * 0.075, (fa * 0.9, 0.085, fa * 0.86)))
            # The forearm's two groups, thick under the elbow and gone by the wrist: the long
            # muscles of its outside, and those of its inside.
            if not self.plain:
                add(fo, "ext", ell(P, E + f * 0.07 + np.array([sx * fa * 0.34, 0, fa * 0.1]), (fa * 0.66 * kf, 0.08, fa * 0.72 * kf)))
                add(fo, "flex", ell(P, E + f * 0.085 + np.array([-sx * fa * 0.3, 0, -fa * 0.06]), (fa * 0.62 * kf, 0.085, fa * 0.68 * kf)))
            add(fo, "elbow", ell(P, E + np.array([0, 0.0, -fa * 0.6]), (0.028, 0.032, fa * 0.52)), "skin")
            fc = W + f * 0.055 + np.array([0, 0, 0.008])
            add(fo, "fist", ell(P, fc, (0.044, 0.055, 0.05)), "skin")
        for sx, side in ((-1, "R"), (1, "L")):
            Hj, K, A = self.Hj[sx], self.K[sx], self.A[sx]
            ta, tb = B["thigh"]
            ca, cb = B["calf"]
            th, sh = "thigh" + side, "shin" + side
            if self.plain:
                add(th, "thigh", cap(P, Hj + np.array([sx * 0.02, HIP_UP, 0]), K, ta, tb))
                add(th, "quad", ell(P, (sx * 0.118, 0.68, 0.016), (ta * 0.84, 0.18, ta * 0.8)))
                add(sh, "shin", cap(P, K, A + np.array([0, 0.02, 0]), ca, cb))
                add(sh, "calf", ell(P, (sx * 0.11, 0.335, -0.03), (ca * 0.92, 0.1, ca * 0.86)))
                add(sh, "knee", ell(P, K + np.array([0, 0.012, ca * 0.62]), (0.035, 0.04, ca * 0.54)), "skin")
                add(sh, "foot", ell(P, (sx * 0.118, 0.034, 0.04), (0.048, 0.036, 0.118)), "skin")
                continue
            # A leg of muscle, not a thick one (user: the legs looked fat: as thick at the knee
            # and down the shin as in the thigh and the calf, a post): narrow at the knee and
            # at the ankle, and the bellies of its muscles standing out between them.
            kt, kc = BELLY["thigh"], BELLY["calf"]
            tk, ck, ce = tb * LEAN["knee"], ca * LEAN["shin"], cb * LEAN["ankle"]
            add(th, "thigh", cap(P, Hj + np.array([sx * 0.02, HIP_UP, 0]), K, ta * LEAN["hip"], tk))
            add(th, "quad", ell(P, (sx * 0.118, 0.69, 0.016), (ta * 0.82 * LEAN["quad"], 0.17, ta * 0.8 * LEAN["quad"])))
            # The thigh's muscles: its outer sweep, the straight one down its front, the drop
            # of muscle inside over the knee, and the back of the thigh.
            add(th, "vlat", ell(P, (sx * (0.11 + ta * 0.36), 0.69, 0.004), (ta * 0.6 * kt, 0.16, ta * 0.72 * kt)))
            add(th, "rect", ell(P, (sx * 0.114, 0.71, ta * 0.4), (ta * 0.46 * kt, 0.16, ta * 0.5 * kt)))
            add(th, "vmed", ell(P, (sx * (0.11 - ta * 0.26), 0.54, ta * 0.24), (ta * 0.34 * kt, 0.07, ta * 0.38 * kt)))
            add(th, "ham", ell(P, (sx * 0.112, 0.695, -ta * 0.36), (ta * 0.7 * kt, 0.165, ta * 0.6 * kt)))
            add(sh, "shin", cap(P, K, A + np.array([0, 0.02, 0]), ck, ce))
            add(sh, "calf", ell(P, (sx * 0.11, 0.33, -0.028), (ca * 0.84, 0.09, ca * 0.84)))
            # The calf's two heads behind, the inner one the lower and the fuller, and the
            # muscle beside the shin's bone in front.
            add(sh, "gastm", ell(P, (sx * (0.11 - ca * 0.4), 0.322, -ca * 0.46), (ca * 0.58 * kc, 0.085, ca * 0.6 * kc)))
            add(sh, "gastl", ell(P, (sx * (0.11 + ca * 0.36), 0.345, -ca * 0.44), (ca * 0.52 * kc, 0.075, ca * 0.56 * kc)))
            add(sh, "tib", ell(P, (sx * (0.11 + ca * 0.26), 0.33, ca * 0.26), (ca * 0.4 * kc, 0.08, ca * 0.44 * kc)))
            # The kneecap, and the point of the elbow (above): the two joints read as joints.
            add(sh, "knee", ell(P, K + np.array([0, 0.012, ck * 0.64]), (0.033, 0.04, ck * 0.58)), "skin")
            add(sh, "foot", foot(P, sx), "skin")
        return out

    def field(self, P):
        """The skin's distance (negative inside), the shape nearest each point, the margin to the
        next one (a groove where two muscles meet), and the parts of the shapes."""
        sh = self.shapes(P)
        D = np.stack([d for _, _, d, _ in sh], 0)
        d = D[0]
        kb = 0.022 if self.B.get("kind") else 0.04   # (the broad forms blended wider)
        for k in range(1, len(sh)):
            d = smin(d, D[k], kb)
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
    if not man.B.get("kind"):
        # A fighter's arm and leg are cut level at the elbow and the knee: by the nearer bone the
        # thicker part's share ran down over the thinner as a skirt, a rim in the air when the joint
        # bent.
        for sx, side in ((-1, "R"), (1, "L")):
            for up, low, piv in (("upperArm", "forearm", man.E[sx]), ("thigh", "shin", man.K[sx])):
                iu, il = names.index(up + side), names.index(low + side)
                both = (who == iu) | (who == il)
                who = np.where(both, np.where(P[1] >= piv[1], iu, il), who)
    return names, who


def joints_of(man):
    """Each joint: its pivot, the two parts that meet there, and the ball both draw round it."""
    js = []
    for sx, side in ((-1, "R"), (1, "L")):
        js.append((man.S[sx], "torso", "upperArm" + side, JOINT_R["shoulder"]))
        js.append((man.E[sx], "upperArm" + side, "forearm" + side, hinge_r(man, "elbow", sx)))
        js.append((man.Hj[sx], "torso", "thigh" + side, JOINT_R["hip"]))
        js.append((man.K[sx], "thigh" + side, "shin" + side, hinge_r(man, "knee", sx)))
    return js


def hinge_r(man, which, sx):
    """The ball both parts draw round a knee or an elbow. A fighter's: as big as the limb is across
    there, so the upper part ends in the joint's own round and the lower turns in it (user: the
    knee must look like a knee; a ball smaller than the limb left the thigh a rim that stood out
    over the shin when the knee bent). A giant's as it was."""
    if man.B.get("kind"):
        return JOINT_R[which]
    key = (which, sx)
    if key not in man.hinge:
        piv = man.K[sx] if which == "knee" else man.E[sx]
        a = np.arange(-0.16, 0.1601, 0.004)
        X, Z = np.meshgrid(piv[0] + a, piv[2] + a, indexing="ij")
        P = (X, np.full(X.shape, piv[1]), Z)
        side = "R" if sx < 0 else "L"
        own = (("thigh" if which == "knee" else "upperArm") + side, ("shin" if which == "knee" else "forearm") + side)
        # (The limb's own shapes, without the kneecap and the elbow's point, which stand out of it.)
        d = None
        for part, nm, dd, _ in man.shapes(P):
            if part in own and nm not in ("knee", "elbow"):
                d = dd if d is None else smin(d, dd, 0.04)
        r = np.sqrt((X - piv[0]) ** 2 + (Z - piv[2]) ** 2)
        m = d < 0.0
        # (A hair inside the limb: on its skin the round would lie in the skin of the part beside it.)
        man.hinge[key] = float(r[m].max()) - FV * 0.5 if m.any() else JOINT_R[which]
    return man.hinge[key]


# --- a part's cells ------------------------------------------------------------------------------
NA = 32    # ways round a part's line for its outline and its map
CELL = 9   # a cell's numbers: ix, iy, iz (fine, from the grid's corner), cx, cy, cz (its voxel), shade, ao, paint
AO_FACES = [((1, 0, 0), 1, 2), ((-1, 0, 0), 1, 2), ((0, 1, 0), 0, 2), ((0, -1, 0), 0, 2), ((0, 0, 1), 0, 1), ((0, 0, -1), 0, 1)]
MARGIN = 10   # fine cells round the part's grid (a deltoid, a fist and a foot stand out of it)


def _box3(a):
    """Each value the mean of its cell and the 26 round it (the edge's own value past the edge)."""
    pad = np.pad(a, 1, mode="edge")
    out = np.zeros_like(a)
    nx, ny, nz = a.shape
    for i in range(3):
        for j in range(3):
            for k in range(3):
                out += pad[i:i + nx, j:j + ny, k:k + nz]
    return out / 27.0


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


def _own_cells(man, name, P):
    """His field over the part's lattice (Man.field), and which of its cells are the part's."""
    X, Y, Z = P
    d, first, gap, d1, sh = man.field(P)
    if not man.B.get("kind"):
        d = _box3(d)   # (a fighter's skin evened: a single cell standing out or a pit a cell deep gone)
    names, who = part_of(man, P)
    mine = who == names.index(name)
    # Round a joint, both parts that meet there (inside the ball about its pivot).
    for piv, a, b, jr in joints_of(man):
        if name in (a, b):
            r = np.sqrt((X - piv[0]) ** 2 + (Y - piv[1]) ** 2 + (Z - piv[2]) ** 2)
            mine |= r < jr
    return d, first, gap, d1, sh, mine


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
    d, first, gap, d1, sh, mine = _own_cells(man, name, P)
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
    shade = np.full(X.shape, 200, np.int32)
    front = Z > 0.03
    if not man.B.get("kind"):
        # A fighter's few clean lines only: under the pectorals, down the belly and across it
        # twice, the navel.
        tor = name == "torso"
        pecl = front & (np.abs(Y - 1.282) < FV * 0.5) & (np.abs(X) > 0.018) & (np.abs(X) < 0.165)
        abs_l = front & (np.abs(X) < 0.062) & ((np.abs(Y - 1.17) < FV * 0.5) | (np.abs(Y - 1.09) < FV * 0.5))
        abs_l |= front & (np.abs(X) < FV * 0.5) & (Y > 1.0) & (Y < 1.28)
        shade[(pecl | abs_l) & tor] = 178
        shade[(np.abs(X) < FV * 0.5) & (np.abs(Y - 0.985) < FV * 0.5) & front & tor] = 120
    else:
        groove = (gap < 0.0028) & (d1 > -0.007) & (kinds[first] == "muscle")
        shade[groove] = 176
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
    # What the fight reads of a fighter (Fighter._outline: his arms are kept out of his trunk as
    # it is drawn): the trunk's and the arms' outlines in his broad forms alone, as they were
    # before the bellies of his muscles were put on him, and the rows he is in there. The fight
    # is not to change with a muscle drawn fuller (user: do not hurt the game).
    keep = None
    if not man.B.get("kind") and (name == "torso" or "rm" in name):
        pm = Man(man.made_of[0], man.made_of[1], True)
        dk, _, _, _, _, mk = _own_cells(pm, name, P)
        ok = (dk < 0.0) & mk
        kp = np.zeros((rows, NA))
        np.maximum.at(kp, (IY[ok], ang[ok]), rad[ok] + FV * 0.5)
        keep = (_fill(kp), int(IY[ok].min()) - MARGIN, int(IY[ok].max()) - MARGIN)
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
    # A fighter's body as it is drawn on his smooth skin (the game's smooth look only: the cubes
    # keep their few lines): where it differs from the shade above, [cell, shade] by turns. Not on
    # what he wears.
    lines = []
    if not man.B.get("kind"):
        base = shade[skin]
        worn = deco[cx, cy, cz] if deco.any() else np.zeros(base.shape, bool)
        worn = (worn & (paint[skin] != 1)) | (paint[skin] > 1)   # (his foot is bare in its sandal: _paint)
        det = _details(man, name, P, inside)[skin]
        det = np.where(det != 200, det, _form_tones(name, sh, skin, worn))
        det = np.where(worn, base, np.where(base < 150, base, det))   # (the navel stays)
        for i in np.flatnonzero(det != base):
            lines += [int(i), int(det[i])]
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
    out = {"lo": [MARGIN, MARGIN, MARGIN], "cells": cells, "sub": [int(v) for v in sub.reshape(-1)],
           "prof": [[round(float(v), 4) for v in row] for row in prof], "k": [[round(float(v), 4) for v in row] for row in K]}
    if lines:
        out["lines"] = lines
    if keep is not None:
        out["keep"] = [[round(float(v), 4) for v in row] for row in keep[0]]
        out["keep_rows"] = [keep[1], keep[2]]
    return out


# The tones a fighter's body is drawn in on his smooth skin (of 200, his skin as it is): what is
# drawn is brought to the nearest of them, so every fine cell is a tile of one flat tone, as a
# man is drawn in a few colours on squared paper.
TONES = np.array([112, 140, 168, 200, 218, 232])
LINE, SOFT, SHADE, LIGHT, BRIGHT = 112, 140, 168, 218, 232


# How much of a part's bare skin is drawn in the shade of its folds, in their deeper shade, and in
# the light of what stands out round.
FORM_SHARE = (0.13, 0.04, 0.16)


def _form_tones(name, sh, skin, worn):
    """His own shape drawn on his smooth skin in flat tones (with _details: the lines a shape as
    broad as his does not have): where he folds in, between the two halves of his chest, under
    it, down his spine, behind a knee, the shade a fold lies in, as far as the skin within a hand
    of it shuts the sky off; where he stands out round, the kneecap, a shoulder, a calf, a light.
    By the part's own limb alone (an arm by his side does not shade his flank: it moves). For each
    skin cell, 200 where none."""
    if name == "torso":
        group = {"torso"}
    else:
        group = {"upperArm" + name[-1], "forearm" + name[-1]} if "rm" in name else {"thigh" + name[-1], "shin" + name[-1]}
    d = None
    for part, nm, dd, _ in sh:
        if part in group:
            d = dd if d is None else smin(d, dd, 0.04)
    d = _box3(d)
    gx, gy, gz = np.gradient(d, FV)
    gl = np.sqrt(gx * gx + gy * gy + gz * gz) + 1e-9
    idx = np.argwhere(skin)
    i, j, l = idx[:, 0], idx[:, 1], idx[:, 2]
    n = d.shape
    nx, ny, nz = gx[i, j, l] / gl[i, j, l], gy[i, j, l] / gl[i, j, l], gz[i, j, l] / gl[i, j, l]
    occ = np.zeros(len(idx))
    for h in (1.5, 3.0, 4.5, 6.0):
        pi = np.clip(np.rint(i + nx * h).astype(int), 0, n[0] - 1)
        pj = np.clip(np.rint(j + ny * h).astype(int), 0, n[1] - 1)
        pl = np.clip(np.rint(l + nz * h).astype(int), 0, n[2] - 1)
        occ += np.clip(d[i, j, l] + h * FV - d[pi, pj, pl], 0.0, None) / (h * FV)
    # How round he is there (over 0 a swell), two fine cells across.
    k = 2
    pad = np.pad(d, k, mode="edge")
    lap = (pad[2 * k:, k:-k, k:-k] + pad[:-2 * k, k:-k, k:-k] + pad[k:-k, 2 * k:, k:-k] + pad[k:-k, :-2 * k, k:-k]
           + pad[k:-k, k:-k, 2 * k:] + pad[k:-k, k:-k, :-2 * k] - 6.0 * d) / (k * FV) ** 2
    c = _box3(lap)[i, j, l]
    out = np.full(len(idx), 200, np.int32)
    bare = ~worn
    if bare.sum() > 50:
        qo = np.quantile(occ[bare], [1.0 - FORM_SHARE[0], 1.0 - FORM_SHARE[1]])
        qc = np.quantile(c[bare], 1.0 - FORM_SHARE[2])
        out[c > qc] = LIGHT
        out[(occ > qo[0]) & (occ > 0.02)] = SHADE
        out[(occ > qo[1]) & (occ > 0.05)] = SOFT
    # Specks: a tile whose tone fewer than two of the tiles round it share is his skin's own.
    grid = np.full(n, -1, np.int32)
    grid[i, j, l] = out
    padg = np.pad(grid, 1, constant_values=-1)
    same = np.zeros(len(idx), np.int32)
    for a in (-1, 0, 1):
        for b in (-1, 0, 1):
            for e in (-1, 0, 1):
                if a or b or e:
                    same += padg[i + 1 + a, j + 1 + b, l + 1 + e] == out
    out[(out != 200) & (same < 2)] = 200
    return out


def _details(man, name, P, inside=None):
    """A fighter's body drawn on his smooth skin, each fine cell a tile of it a tone darker or
    lighter (200: his skin as it is; user: details over all his body, so that he is not a smooth
    wax doll, and still a man of voxels: the tones are few and flat, TONES). A man's body as it is
    drawn: the light on the belly of each muscle, the line where two meet, a shade under what
    stands out. On his chest the pectorals, the breastbone between them, the collarbones, the
    nipples; his belly's blocks, its middle line and the lines across it, the saw of muscle on his
    ribs; on his back the spine's groove between its two columns, the shoulder blades, the
    trapezius, the lower edge of the broad muscles, the two dimples over the hips; the deltoid's
    cap and its edge, the two muscles of the arm, the point of the elbow, the wrist, the fingers
    of the fist; the muscles of the thigh, the kneecap, the shin's bone, the calf's two halves,
    the tendon of the heel and the ankle's bones; the toes."""
    X, Y, Z = P
    B = man.B
    det = np.full(X.shape, 200.0)

    def mark(mask, dist, value, core=FV * 0.55, soft=FV * 1.0):
        k = np.clip((soft - np.abs(dist)) / (soft - core), 0.0, 1.0)
        v = 200.0 + (value - 200.0) * k
        m = mask & (k > 0)
        if value < 200:
            det[m] = np.minimum(det[m], v[m])
        else:
            det[m] = np.where(det[m] >= 200.0, np.maximum(det[m], v[m]), det[m])

    def patch(mask, value):
        mark(mask, np.zeros(X.shape), value)

    def seg(a, b, ax=(0, 1)):
        """How far from the line a..b, in the plane of the two axes `ax` (0 x, 1 y, 2 z)."""
        U, V = P[ax[0]], P[ax[1]]
        du, dv = b[0] - a[0], b[1] - a[1]
        t = np.clip(((U - a[0]) * du + (V - a[1]) * dv) / max(1e-12, du * du + dv * dv), 0.0, 1.0)
        return np.sqrt((U - a[0] - t * du) ** 2 + (V - a[1] - t * dv) ** 2)

    def ring(c, r, ax=(0, 1)):
        """How far from the ellipse round `c` of radii `r`, and how far out of it (1 on it)."""
        U, V = P[ax[0]], P[ax[1]]
        rr = np.sqrt(((U - c[0]) / r[0]) ** 2 + ((V - c[1]) / r[1]) ** 2)
        return (rr - 1.0) * min(r), rr

    front = Z > 0.02
    back = Z < -0.02
    if name == "torso":
        cw = B["chest"][0]
        for sx in (-1, 1):
            side = X * sx > 0.0
            # The pectoral's lower edge, a line from under the arm in to the breastbone.
            d_, rr = ring((sx * 0.086, 1.355), (0.1, 0.075))
            mark(front & side & (Y < 1.345) & (X * sx < cw - 0.012), d_, LINE)
            mark(front & (Z > 0.05), np.sqrt((X - sx * 0.098) ** 2 + (Y - 1.335) ** 2), LINE, FV * 0.55, FV * 0.85)   # a nipple
            mark(front & (Z > 0.03), seg((sx * 0.03, 1.456), (sx * 0.2, 1.474)), BRIGHT, FV * 0.5, FV * 1.2)            # a collarbone
            mark(front & (Z > 0.03), seg((sx * 0.03, 1.456 - FV * 1.6), (sx * 0.19, 1.474 - FV * 1.6)), SHADE, FV * 0.5, FV * 0.9)
            mark(front & (Y > 1.03) & (Y < 1.262), np.abs(X - sx * 0.076), SHADE)                                      # the belly's edge
            # The belly's blocks, each lit; the saw of muscle on the ribs beside them.
            for yc, ry in ((1.243, 0.013), (1.184, 0.019), (1.116, 0.019), (1.052, 0.016)):
                _, br = ring((sx * 0.038, yc), (0.021, ry))
                patch(front & (br < 1.0), LIGHT)
            for k in range(3):
                y0 = 1.262 - k * 0.046
                mark(front & side & (Z < 0.115), seg((sx * 0.104, y0), (sx * 0.146, y0 - 0.02)), SOFT, FV * 0.5, FV * 0.9)
            mark(front & (Z > 0.02), seg((sx * 0.014, 1.468), (sx * 0.056, 1.6)), SHADE, FV * 0.5, FV * 0.9)            # the neck's cord
            # The shoulder blade: its inner edge round to its point, lit within; the trapezius
            # down to its point; the broad muscle's lower edge; a dimple over the hip.
            d_, rr = ring((sx * 0.116, 1.378), (0.06, 0.088))
            mark(back & side & (X * sx < 0.126) & (Y < 1.41), d_, SOFT)
            patch(back & (rr < 0.5), LIGHT)
            mark(back & side, seg((sx * 0.012, 1.19), (sx * 0.062, 1.3)), SHADE, FV * 0.5, FV * 0.9)
            mark(back & side, seg((sx * 0.2, 1.29), (sx * 0.075, 1.09)), SHADE, FV * 0.5, FV * 0.95)
            mark(back, np.sqrt((X - sx * 0.047) ** 2 + (Y - 1.005) ** 2), SOFT, FV * 0.6, FV * 1.0)
            patch(back & (np.abs(X - sx * 0.04) < 0.013) & (Y > 1.03) & (Y < 1.24), LIGHT)                              # a column of the spine
        mark(front & (Y > 1.3) & (Y < 1.432), np.abs(X), SOFT, FV * 0.5, FV * 0.9)                                      # the breastbone
        mark(front & (Y > 1.03) & (Y < 1.3), np.abs(X), LINE, FV * 0.5, FV * 0.9)                                       # the belly's middle
        for ly in (1.218, 1.15, 1.082):
            mark(front & (np.abs(X) < 0.07), np.abs(Y - ly), SOFT, FV * 0.5, FV * 0.9)
        mark(back & (Y > 1.0) & (Y < 1.3), np.abs(X), SOFT, FV * 0.5, FV * 0.9)                                         # the spine's groove
        patch(back & (np.sqrt(X ** 2 + (Y - 1.468) ** 2) < 0.014), LIGHT)                                               # the knob at the neck's root
    elif name.startswith("upperArm"):
        sx = -1 if name.endswith("R") else 1
        S, E = man.S[sx], man.E[sx]
        u = nrm(E - S)
        lx = (X - S[0]) * sx        # out from the arm's line (inward under 0)
        dc = S + u * 0.03 + np.array([sx * 0.008, -0.01, 0])
        dl = ell(P, dc, (B["delt"], 0.1, B["delt"] * 1.04))
        # The deltoid's edge: down to a point on the outside of the arm, up again to the front and
        # the back (not a band round the arm).
        phi = np.arctan2(Z, lx)
        ye = dc[1] - 0.112 + 0.05 * np.abs(phi) / 1.6
        mark((np.abs(phi) < 1.9) & (lx > -0.02), Y - ye, SOFT, FV * 0.5, FV * 0.9)
        patch((dl < -0.016) & (Y > dc[1] - 0.03) & (lx > -0.01), LIGHT)                                                 # and its cap
        # Between the two muscles of the arm, down its outside from the deltoid's point and down
        # its inside; the biceps in front, lit, and the line under its belly; the triceps behind,
        # its two heads and the horseshoe they end in over the elbow.
        mark((lx > 0.02) & (Y < dc[1] - 0.125) & (Y > E[1] + 0.06), np.abs(Z + 0.004), SOFT, FV * 0.5, FV * 0.9)
        mark((lx < -0.02) & (Y < dc[1] - 0.1) & (Y > E[1] + 0.06), np.abs(Z + 0.002), SHADE, FV * 0.5, FV * 0.9)
        d_, br = ring((S[0] - sx * 0.004, S[1] - 0.205), (0.034, 0.082))
        patch(front & (br < 0.82), LIGHT)
        patch(front & (br < 0.36), BRIGHT)
        mark(front & (Y < S[1] - 0.235) & (Y > E[1] + 0.02), d_ - FV * 0.6, SHADE, FV * 0.5, FV * 0.9)
        d_, br = ring((S[0] + sx * 0.006, S[1] - 0.2), (0.046, 0.1))
        mark(back & (Y < S[1] - 0.22) & (Y > E[1] + 0.03), d_, SOFT, FV * 0.5, FV * 0.9)
        mark(back & (Y < dc[1] - 0.14) & (Y > S[1] - 0.26), np.abs(lx - 0.006), SHADE, FV * 0.5, FV * 0.9)
        for k in (-1, 1):
            _, br = ring((S[0] + sx * (0.006 + k * 0.024), S[1] - 0.19 - k * 0.012), (0.014, 0.055))
            patch(back & (br < 1.0), LIGHT)
    elif name.startswith("forearm"):
        sx = -1 if name.endswith("R") else 1
        E, W = man.E[sx], man.W[sx]
        f = nrm(W - E)
        lx = (X - E[0]) * sx
        fc = W + f * 0.055 + np.array([0, 0, 0.008])
        patch(back & (np.sqrt((X - E[0]) ** 2 + (Y - E[1]) ** 2) < 0.02), BRIGHT)                                       # the point of the elbow
        mark(back & (Y < E[1] - 0.01), ring((E[0], E[1]), (0.027, 0.03))[0], SHADE, FV * 0.5, FV * 0.9)
        # Between its two groups, down its outside and down its inside; the long muscle of its
        # outside lit under the elbow, and the inner one in front; the cords of the wrist.
        mark((lx > 0.015) & (Y < E[1] - 0.03) & (Y > E[1] - 0.17), np.abs(Z - 0.006), SOFT, FV * 0.5, FV * 0.9)
        mark((lx < -0.015) & (Y < E[1] - 0.03) & (Y > E[1] - 0.15), np.abs(Z + 0.004), SHADE, FV * 0.5, FV * 0.9)
        _, br = ring((E[0], E[1] - 0.085), (0.024, 0.055))
        patch(front & (br < 1.0), LIGHT)
        _, br = ring((E[1] - 0.075, 0.03), (0.06, 0.022), ax=(1, 2))
        patch((lx > 0.02) & (br < 1.0), LIGHT)
        _, br = ring((E[0] + sx * 0.004, E[1] - 0.08), (0.02, 0.05))
        patch(back & (br < 1.0), LIGHT)
        mark(back & (Y < E[1] - 0.05) & (Y > W[1] + 0.03), np.abs(lx - 0.03), SHADE, FV * 0.5, FV * 0.9)
        for k in (-1, 1):
            mark(front & (Y < W[1] + 0.075) & (Y > W[1] + 0.012), np.abs(lx - k * 0.011), SHADE, FV * 0.4, FV * 0.75)
        mark(np.abs(Z) < 1.0, np.abs(Y - (W[1] + 0.004)), SOFT, FV * 0.45, FV * 0.9)                                    # the wrist
        for k in (-1, 0, 1):
            mark((Z > fc[2] + 0.012) & (np.abs(Y - fc[1]) < 0.04), np.abs(X - (fc[0] + k * 0.021)), LINE, FV * 0.45, FV * 0.8)   # between the fingers
        mark((Z > fc[2] - 0.01) & (Y > fc[1] + 0.012), np.abs(Y - (fc[1] + 0.03)), BRIGHT, FV * 0.5, FV * 0.9)          # the knuckles
    elif name.startswith("thigh"):
        sx = -1 if name.endswith("R") else 1
        K = man.K[sx]
        lx = (X - K[0]) * sx
        # The straight muscle down its front, lit, between the outer one and the inner; the drop
        # of muscle inside over the knee and the cord down to the kneecap; down its outside, the
        # band between the front of the thigh and the back.
        _, br = ring((K[0] + sx * 0.006, 0.67), (0.026, 0.13))
        patch(front & (br < 1.0), LIGHT)
        mark(front & (Y > K[1] + 0.09) & (Y < 0.82), np.abs(lx - 0.047 - 0.012 * np.clip((Y - 0.6) / 0.2, 0.0, 1.0)), SOFT, FV * 0.5, FV * 0.9)
        mark(front & (Y > K[1] + 0.15) & (Y < 0.82), np.abs(lx + 0.036 + 0.01 * np.clip((Y - 0.6) / 0.2, 0.0, 1.0)), SHADE, FV * 0.5, FV * 0.9)
        d_, rr = ring((K[0] - sx * 0.03, K[1] + 0.085), (0.032, 0.056))
        mark(front & (Y < K[1] + 0.1) & (lx < -0.004), d_, SOFT, FV * 0.5, FV * 0.9)
        patch(front & (rr < 0.55), LIGHT)
        patch(front & (np.abs(lx - 0.006) < 0.012) & (Y > K[1] + 0.045) & (Y < K[1] + 0.085), BRIGHT)
        mark((lx > 0.05) & (Y > K[1] + 0.07) & (Y < 0.8), np.abs(Z + 0.014), SHADE, FV * 0.5, FV * 0.9)
        # Behind: its two muscles and the groove between them, the two cords beside the hollow
        # of the knee, and the fold across it.
        mark(back & (Y > K[1] + 0.09) & (Y < 0.82), np.abs(lx - 0.002), SOFT, FV * 0.5, FV * 0.9)
        for k in (-1, 1):
            _, br = ring((K[0] + sx * (0.002 + k * 0.034), 0.66), (0.018, 0.11))
            patch(back & (br < 1.0), LIGHT)
            patch(back & (np.abs(lx - 0.002 - k * 0.036) < 0.008) & (Y > K[1] + 0.022) & (Y < K[1] + 0.085), BRIGHT)
        mark(back & (np.abs(lx) < 0.07), np.abs(Y - (K[1] + 0.03)), SHADE, FV * 0.5, FV * 0.9)
    elif name.startswith("shin"):
        sx = -1 if name.endswith("R") else 1
        K, A = man.K[sx], man.A[sx]
        lx = (X - K[0]) * sx
        d_, rr = ring((K[0], K[1] + 0.012), (0.034, 0.04))
        patch(front & (rr < 0.8), BRIGHT)                                                                               # the kneecap
        mark(front & (Y < K[1] - 0.012), d_ - FV * 0.8, SOFT, FV * 0.5, FV * 0.9)                                       # and the shade under it
        mark(front & (Y < K[1] - 0.075) & (Y > A[1] + 0.05), np.abs(lx - 0.004), BRIGHT, FV * 0.5, FV * 0.9)            # the shin's bone
        mark(front & (Y < K[1] - 0.075) & (Y > A[1] + 0.07), np.abs(lx - 0.004 - FV * 2.0), SHADE, FV * 0.5, FV * 0.9)  # and the muscle beside it
        # The calf behind: its two heads, the inner one the lower, the groove between them and
        # the line each ends in over the flat of the tendon; the tendon down to the heel, a
        # hollow each side of it; from the side, the line between the calf and the shin.
        mark(back & (Y < K[1] - 0.04) & (Y > 0.25), np.abs(lx - 0.0), SOFT, FV * 0.5, FV * 0.9)
        for k in (-1, 1):
            yc = 0.33 - (0.012 if k < 0 else 0.0)
            d_, br = ring((K[0] + sx * k * 0.031, yc), (0.03, 0.075))
            patch(back & (br < 0.6), LIGHT)
            mark(back & (Y < yc - 0.03) & (lx * k > 0.004), d_, SOFT, FV * 0.5, FV * 0.9)
            mark(back & (Y < 0.2) & (Y > FOOT_TOP + 0.03), np.abs(lx - k * 0.02), SHADE, FV * 0.45, FV * 0.8)
        mark(back & (Y < 0.24) & (Y > 0.09), np.abs(lx), LIGHT, FV * 0.5, FV * 0.9)                                     # the heel's tendon
        for k in (-1, 1):
            mark((lx * k > 0.03) & (Y < K[1] - 0.05) & (Y > 0.24), seg((-0.008, K[1] - 0.04), (-0.034, 0.24), ax=(2, 1)), SHADE, FV * 0.5, FV * 0.9)
            patch((np.sqrt((Y - 0.088) ** 2 + (Z + 0.012) ** 2) < 0.016) & (lx * k > 0.02), BRIGHT)                     # an ankle bone
        # His toes: the big one apart from the rest, a nail on each (the end of each toe, where
        # nothing of him is in front of it or over it).
        zone = Y < FOOT_TOP
        ixl = np.floor((np.abs(X) - 0.11) / FV + 1e-6)
        iz = np.floor(Z / FV + 1e-6)
        patch(zone & (iz >= 8) & (ixl == -1) & (Y > FV), SOFT)
        if inside is not None:
            ahead = ~_shift(inside, (0, 0, -1))
            over = ~_shift(inside, (0, -1, 0))
            patch(zone & (iz >= 8) & (ixl != -1) & ahead & over & inside, BRIGHT)
    # Each tile the nearest of the few tones.
    q = TONES[np.argmin(np.abs(det[..., None] - TONES[None, None, None, :]), axis=-1)]
    return q.astype(np.int32)


def _paint(man, P, d, first, sh, skin):
    """What is painted on a giant's skin (an index into his palette, 0 his skin)."""
    B = man.B
    k = B.get("kind", "")
    X, Y, Z = P
    paint = np.zeros(X.shape, np.int64)
    if k == "":
        # A fighter's foot in its sandal (user: better feet; drawn as the game's own voxels there, a
        # boot's, it was a dark lump): his own skin, the toes bare, on a sole; a strap across the
        # root of the toes and one over the instep, a thong between them from between the big toe
        # and the next; the heel in its cup, a strap from it along each side and one up the back of
        # the heel to the strap round his ankle. By whole fine cells, so a strap is a row of tiles.
        zone = Y < FOOT_TOP
        ixl = np.floor((np.abs(X) - 0.11) / FV + 1e-6)   # cells out from the shin's line (inward under 0)
        iy = np.floor(Y / FV + 1e-6)
        iz = np.floor(Z / FV + 1e-6)
        strap = (iy >= 1) & ((iz == 7) | (iz == 3))
        strap |= (iy >= 2) & (ixl == -1) & (iz > 3) & (iz < 7)
        strap |= (iz <= -4) & (iy >= 1) & (iy <= 4)
        strap |= (iy == 2) & (iz > -4) & (iz < 3)
        strap |= (iz <= -5) & (iy > 4) & (ixl >= -1) & (ixl <= 0)
        paint[zone] = 1
        paint[zone & strap] = 2
        paint[zone & (iy < 1)] = 3
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
