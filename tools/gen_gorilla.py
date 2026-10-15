"""Writes the gorilla into data/beasts.json: a voxel ape after the reference art (a barrel body
hunched forward, long heavy arms on knuckles, short hind legs, a grey chest and face, a red
loincloth with a skull). Parts follow the bear's layout so Beast's gait, rearing and hugging
work unchanged: beastBody, beastHead, legFL/FR (the arms, FLLo/FRLo the forearms and fists),
legBL/BR (the legs, Lo the shins).  python3 tools/gen_gorilla.py
"""
import json, math, random

SCALE = 2.5
U = 0.0275 * SCALE          # one fine voxel in metres
rng = random.Random(7)

FUR = (0x54, 0x52, 0x57)
FUR_D = (0x30, 0x2f, 0x34)
FUR_L = (0x74, 0x72, 0x78)
GREY = (0xa6, 0xa2, 0x9c)
GREY_D = (0x82, 0x7e, 0x78)
SILVER = (0xc6, 0xc3, 0xbc)
RED = (0x9a, 0x1c, 0x1c)
RED_D = (0x6e, 0x12, 0x12)
GOLD = (0xc8, 0x9c, 0x3c)
BONE = (0xe8, 0xe0, 0xc8)
EYE = (0xff, 0x96, 0x28)
BLACK = (0x1c, 0x18, 0x16)   # (true black on a head is read as a glowing eye by BeastStyle)
NAIL = (0x3a, 0x34, 0x30)

def rgb(c, k=1.0):
    r, g, b = (min(255, max(0, int(v * k))) for v in c)
    return (r << 16) | (g << 8) | b

def fur(c=FUR, var=0.14):
    return rgb(c, 1.0 + rng.uniform(-var, var))

def part(name, label, dims, mass, parent, pa, ca, pos, leg=False, lower=False, head=False, bite=False, jaw=None, mult=1.0, splay=0):
    return {"name": name, "label": label, "dims": dims, "mass": mass, "mult": mult, "parent": parent,
            "pos": [round(v, 4) for v in pos], "rot": [0, 0, 0, 1], "pa": pa, "ca": ca, "leg": leg, "lower": lower,
            "head": head, "bite": bite, "jaw": jaw, "wing": 0, "point": False,
            "grid": [dims[0] * 2, dims[1] * 2, dims[2] * 2], "scale": SCALE, "splay": splay, "root": None, "voxels": []}

def inside_ellipsoid(x, y, z, g, rx, ry, rz, cx=None, cy=None, cz=None):
    cx = (g[0] - 1) / 2 if cx is None else cx
    cy = (g[1] - 1) / 2 if cy is None else cy
    cz = (g[2] - 1) / 2 if cz is None else cz
    return ((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2 + ((z - cz) / rz) ** 2 <= 1.0

def add(p, x, y, z, color, fixed=0):
    g = p["grid"]
    if 0 <= x < g[0] and 0 <= y < g[1] and 0 <= z < g[2]:
        p["voxels"].append([x, y, z, color, fixed])

# A chunky pelt: the fur falls in clumps of two or three voxels, light and dark, as in the
# reference art, not a per-voxel sparkle.
def pelt(x, y, z, base=FUR, cell=3, var=0.22):
    h = (x // cell) * 73856093 ^ (y // cell) * 19349663 ^ (z // cell) * 83492791
    r = ((h & 0xffff) / 65535.0) * 2.0 - 1.0
    return rgb(base, 1.0 + var * r + rng.uniform(-0.04, 0.04))

# ---------------- body: a hulking upper body, the shoulders far broader than the hips, no neck,
# a grey chest plate down the front, the red loincloth with its skull below ----------------
body = part("beastBody", "Gorilla body", [14, 14, 15], 340, None, None, None, [0, 1.55, 0], mult=0.55)
g = body["grid"]
for x in range(g[0]):
    for y in range(g[1]):
        for z in range(g[2]):
            up = y / (g[1] - 1)
            # Hunched forward as an ape stands: the shoulders carried well ahead of the hips,
            # the back sloping up and forward from the rump.
            zc = 14.5 + (up - 0.45) * 8.0
            # Broad at the shoulders (up near 1), narrowing to the hips (up near 0.3).
            rx = 9.8 + 4.0 * min(1.0, max(0.0, (up - 0.25) / 0.6))
            rz = 9.6 + 1.6 * min(1.0, max(0.0, (up - 0.3) / 0.6))
            front = (z - (zc - rz)) / (2 * rz)     # 0 the back of this row, 1 its front
            if y < 5:
                # The loincloth: a red flap down the front, the skull on it.
                flap = 0.55 < front < 1.02 and abs(x - 13.5) < 6.5 and (y > 0 or abs(x - 13.5) < 4.5)
                if not flap:
                    continue
                c = fur(RED if (y + z + x) % 3 else RED_D, 0.05)
                if front > 0.9 and abs(x - 13.5) <= 2.0 and 1 <= y <= 3:
                    c = rgb(BONE)
                    add(body, x, y, z, c, 1)
                    continue
                add(body, x, y, z, c)
                continue
            if not inside_ellipsoid(x, y, z, g, rx, 12.6, rz, cy=14.5, cz=zc):
                continue
            # The shoulders round off: no voxel in the top corners.
            if (y >= 24 and abs(x - 13.5) > 11.5) or (y >= 26 and abs(x - 13.5) > 9.5) or (y >= 22 and abs(x - 13.5) > 12.5):
                continue
            c = pelt(x, y, z)
            # The grey chest: a plate down the front, the two pectorals parted by a dark seam.
            chest = front > 0.72 and 11 <= y <= 24 and abs(x - 13.5) < 9.5 - max(0, 16 - y) * 0.7
            if chest:
                c = pelt(x, y, z, GREY, 4, 0.1)
                if abs(x - 13.5) < 0.6 and 13 <= y <= 22:
                    c = fur(GREY_D, 0.05)
            # The belly below the chest, a shade lighter than the back.
            if front > 0.7 and 8 <= y < 11 and abs(x - 13.5) < 7:
                c = pelt(x, y, z, FUR_L, 3, 0.1)
            # The silverback's saddle, a faint silvering over the shoulders behind.
            if y >= 20 and front < 0.45 and abs(x - 13.5) < 9:
                c = pelt(x, y, z, GREY_D, 3, 0.12)
            # The loincloth round the hips, and the belt above it.
            if y <= 7 and 0.1 < front:
                c = fur(RED if (y + z + x) % 3 else RED_D, 0.05)
            if y == 8 and 0.08 < front:
                c = rgb(GOLD)
            add(body, x, y, z, c)

# ---------------- head: built in profile, as a gorilla's skull is: the cranium an egg behind,
# the brow a shelf jutting over deep-set eyes, the face hollow under it, then the muzzle thrust
# far forward with the nose on top of it and the mouth across its front ----------------
head = part("beastHead", "Gorilla head", [8, 8, 8], 50, "beastBody", [0, 0.25, 0.32], [0, -0.1, -0.06], [0, 0, 0],
            head=True, bite=True, jaw={"from": 0.6, "y": 0.3}, mult=1.3)
g = head["grid"]
FACE = (0x9a, 0x96, 0x92)
LIP = (0xa8, 0xa4, 0x9e)
NOSE = (0x5c, 0x58, 0x58)
# Per row (y, 0 the chin and 15 the crest): how far forward the face reaches (z), the face's
# half width, and how far forward the fur beside and above it reaches. The muzzle (the middle
# of the lower rows) stands further forward still.
FRONT = {  # y: (face front z, face half width, fur front z)
    15: (None, 0.0, 3), 14: (None, 0.0, 5), 13: (None, 0.0, 7), 12: (None, 0.0, 8), 11: (None, 0.0, 9),
    10: (12, 6.5, 9),    # the brow shelf (fur)
    9: (12, 6.5, 9),     # the eyes, right under it
    8: (12, 6.5, 10),    # the cheekbones
    7: (12, 6.0, 10),    # the bridge of the nose
    6: (12, 6.0, 10),    # the nose
    5: (12, 5.5, 10),    # the upper lip
    4: (12, 5.5, 10),    # the mouth
    3: (12, 5.0, 10),    # the lower lip
    2: (11, 4.0, 9),     # the chin
    1: (10, 3.0, 9), 0: (None, 0.0, 8),
}
MUZZLE = {7: (13, 2.0), 6: (14, 2.0), 5: (15, 4.0), 4: (15, 4.0), 3: (14, 3.5), 2: (12, 2.5)}   # y: (front z, half width)
for x in range(g[0]):
    for y in range(g[1]):
        ff, hw, fz = FRONT[y]
        cx = abs(x - 7.5)
        in_face = ff is not None and cx < hw
        mz, mw = MUZZLE.get(y, (0, 0))
        in_muz = in_face and cx < mw and mz > 0
        for z in range(g[2]):
            cran = inside_ellipsoid(x, y, z, g, 7.2, 9.0, 6.6, cx=7.5, cy=6.5, cz=5.0)
            crest = cx < 2.2 - max(0, y - 13) * 0.6 and 2 <= z <= 9 and 13 <= y <= 15 and inside_ellipsoid(x, y, z, g, 7.4, 10.4, 7.4, cx=7.5, cy=8.0, cz=6.0)
            ear = 7 <= y <= 9 and 3 <= z <= 6 and (x == 0 or x == g[0] - 1)
            front_fur = z <= fz and cx < 7.5 and y >= 1 and (cran or z >= 7)
            face = in_face and z <= ff and z >= 7 and not (y == 10 and z >= 11 and cx > 5.0)   # the brow rounds off at its ends
            muz = in_muz and z <= mz
            if not (cran or crest or ear or front_fur or face or muz):
                continue
            # Colour by what the voxel is, the face parts over the fur.
            if y == 10 and (face or front_fur) and z >= 9:
                c = fur(FUR_D, 0.06)                     # the brow shelf
            elif muz:
                if y == 6 and z == mz and (cx < 0.6 or 1.5 < cx < 2.5):
                    c = rgb(BLACK) if 1.5 < cx < 2.5 else rgb(NOSE)   # the nostrils, the septum
                elif y in (6, 7) and z >= mz - 1:
                    c = rgb(NOSE)                        # the flat nose on top of the muzzle
                elif y == 4 and z == mz:
                    c = rgb(BLACK) if cx < 3.0 else rgb(BONE)   # the mouth, the canines at its corners
                elif y == 3 and z == mz and 2.5 < cx < 3.5:
                    c = rgb(BONE)                        # the canine tips over the lower lip
                else:
                    c = fur(LIP, 0.05)
            elif face:
                c = fur(FACE if y >= 2 else GREY_D, 0.05)
                if y == 9 and z == ff and 1.5 < cx < 3.5:
                    c = rgb(EYE)                         # the eyes: amber, under the brow
                elif y == 9 and z == ff and cx < 1.5:
                    c = rgb(NOSE)                        # the bridge between them, in shadow
            elif ear or crest:
                c = fur(FUR_D, 0.06)
            else:
                c = pelt(x, y, z, FUR_D if (y == 10 and z >= 7) else FUR_L, 2, 0.2)
            add(head, x, y, z, c, 1 if (face or muz) and z >= 10 else 0)

# ---------------- arms: long, thick, from the shoulders to fists on the sand ----------------
def limb(name, label, dims, mass, parent, pa, ca, fist=False, lower=False, splay=0):
    p = part(name, label, dims, mass, parent, pa, ca, [0, 0, 0], leg=True, lower=lower, splay=splay)
    g = p["grid"]
    for x in range(g[0]):
        for y in range(g[1]):
            for z in range(g[2]):
                t = y / (g[1] - 1)
                r = g[0] / 2 - 0.5
                # A forearm tapers to the wrist, then the fist swells.
                if fist:
                    k = 1.0 - 0.2 * t if t > 0.3 else 0.95
                    if t < 0.28:
                        k = 1.1
                else:
                    k = 1.0 - 0.1 * t
                if ((x - r) / (r * k + 0.01)) ** 2 + ((z - r) / (r * k + 0.01)) ** 2 > 1.0:
                    continue
                c = pelt(x, y + (7 if fist else 0), z, FUR, 3, 0.22)
                if fist and t < 0.22:
                    c = pelt(x, y, z, GREY_D, 2, 0.12)
                p["voxels"].append([x, y, z, c, 0])
    return p

armL = limb("legFL", "Gorilla left arm", [6, 11, 6], 28, "beastBody", [-0.32, 0.33, 0.26], [0, 0.30, 0], splay=0.1)
armR = limb("legFR", "Gorilla right arm", [6, 11, 6], 28, "beastBody", [0.32, 0.33, 0.26], [0, 0.30, 0], splay=-0.1)
foreL = limb("legFLLo", "Gorilla left fist", [7, 9, 7], 28, "legFL", [0, -0.30, 0], [0, 0.24, 0], fist=True, lower=True)
foreR = limb("legFRLo", "Gorilla right fist", [7, 9, 7], 28, "legFR", [0, -0.30, 0], [0, 0.24, 0], fist=True, lower=True)
legL = limb("legBL", "Gorilla left leg", [6, 5, 6], 16, "beastBody", [-0.2, -0.26, -0.2], [0, 0.13, 0])
legR = limb("legBR", "Gorilla right leg", [6, 5, 6], 16, "beastBody", [0.2, -0.26, -0.2], [0, 0.13, 0])
shinL = limb("legBLLo", "Gorilla left foot", [6, 5, 6], 12, "legBL", [0, -0.13, 0], [0, 0.13, 0], fist=True, lower=True)
shinR = limb("legBRLo", "Gorilla right foot", [6, 5, 6], 12, "legBR", [0, -0.13, 0], [0, 0.13, 0], fist=True, lower=True)

parts = [body, head, armL, foreL, armR, foreR, legL, shinL, legR, shinR]
by = {p["name"]: p for p in parts}
# Positions from the anchors (pos = parent's anchor - own anchor; all rotations identity).
for p in parts:
    if p["parent"] is None:
        continue
    par = by[p["parent"]]
    p["pos"] = [round(par["pos"][i] + p["pa"][i] * SCALE - p["ca"][i] * SCALE, 4) for i in range(3)]
# A fist and a foot sit on the sand: the body's height is set so the feet reach it.
foot_bottom = by["legBRLo"]["pos"][1] - (by["legBRLo"]["grid"][1] / 2) * U
drop = foot_bottom - 0.02
for p in parts:
    p["pos"][1] = round(p["pos"][1] - drop, 4)
height = by["beastBody"]["pos"][1] / SCALE

d = json.load(open("data/beasts.json"))
d["gorilla"] = {"name": "The Gorilla", "scale": SCALE, "height": round(height, 4), "ai": "hugger", "speed": 4.6, "bite": 34,
                "lunge": 3.0, "lungeUp": 0, "stalkRadius": 2.2, "cooldown": 1.1, "maul": False, "flies": False, "breath": None,
                "breathRange": 0, "harmless": False, "multiHead": False, "mult": 0.5, "fur": rgb(FUR), "parts": parts}
json.dump(d, open("data/beasts.json", "w"), separators=(",", ":"))
print("gorilla: height %.2f, %d voxels" % (height, sum(len(p["voxels"]) for p in parts)))
for p in parts:
    print(" ", p["name"], p["pos"], len(p["voxels"]))
