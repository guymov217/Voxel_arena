"""Writes the gorilla into data/beasts.json: a voxel ape after the reference art (a barrel body
hunched forward, long heavy arms on knuckles, short hind legs, a grey chest and face, a red
loincloth with a skull). Parts follow the bear's layout so Beast's gait, rearing and hugging
work unchanged: beastBody, beastHead, legFL/FR (the arms, FLLo/FRLo the forearms and fists),
legBL/BR (the legs, Lo the shins).  python3 tools/gen_gorilla.py
"""
import json, math, random

SCALE = 2.0
U = 0.0275 * SCALE          # one fine voxel in metres
rng = random.Random(7)

FUR = (0x64, 0x5d, 0x58)
FUR_D = (0x34, 0x30, 0x2e)
FUR_L = (0x8a, 0x82, 0x7b)
GREY = (0xb6, 0xb2, 0xaa)
GREY_D = (0x80, 0x7c, 0x76)
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
body = part("beastBody", "Gorilla body", [14, 14, 12], 340, None, None, None, [0, 1.55, 0], mult=0.55)
g = body["grid"]
for x in range(g[0]):
    for y in range(g[1]):
        for z in range(g[2]):
            front = z / (g[2] - 1)
            up = y / (g[1] - 1)
            # Broad at the shoulders (up near 1), narrowing to the hips (up near 0.3).
            rx = 9.8 + 4.0 * min(1.0, max(0.0, (up - 0.25) / 0.6))
            rz = 10.6 + 1.6 * min(1.0, max(0.0, (up - 0.3) / 0.6))
            if y < 5:
                # The loincloth: a red flap down the front, the skull on it.
                flap = 0.55 < front < 0.97 and abs(x - 13.5) < 6.5 and (y > 0 or abs(x - 13.5) < 4.5)
                if not flap:
                    continue
                c = fur(RED if (y + z + x) % 3 else RED_D, 0.05)
                if front > 0.86 and abs(x - 13.5) <= 2.0 and 1 <= y <= 3:
                    c = rgb(BONE)
                    add(body, x, y, z, c, 1)
                    continue
                add(body, x, y, z, c)
                continue
            if not inside_ellipsoid(x, y, z, g, rx, 12.6, rz, cy=14.5):
                continue
            # The shoulders round off: no voxel in the top corners.
            if (y >= 24 and abs(x - 13.5) > 11.5) or (y >= 26 and abs(x - 13.5) > 9.5) or (y >= 22 and abs(x - 13.5) > 12.5):
                continue
            c = pelt(x, y, z)
            # The grey chest: a plate down the front, the two pectorals parted by a dark seam.
            chest = front > 0.72 and 12 <= y <= 23 and abs(x - 13.5) < 8.5 - max(0, 17 - y) * 0.6
            if chest:
                c = pelt(x, y, z, GREY, 4, 0.1)
                if abs(x - 13.5) < 0.6 and 13 <= y <= 22:
                    c = fur(GREY_D, 0.05)
            # The belly below the chest, a shade lighter than the back.
            if front > 0.7 and 8 <= y < 12 and abs(x - 13.5) < 7:
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

# ---------------- head: small for the body and sunk between the shoulders, a crest on the
# skull, a dark brow shelf over small amber eyes, a flat grey face with a broad nose, the mouth
# open on long canines ----------------
head = part("beastHead", "Gorilla head", [7, 7, 7], 45, "beastBody", [0, 0.25, 0.2], [0, -0.1, -0.11], [0, 0, 0],
            head=True, bite=True, jaw={"from": 0.55, "y": 0.3}, mult=1.3)
g = head["grid"]
FACE_Z = 10          # the plane of the cheeks; the brow and the nose stand out in front of it
for x in range(g[0]):
    for y in range(g[1]):
        for z in range(g[2]):
            # The cranium: an egg, cut flat at the face and the chin.
            cran = inside_ellipsoid(x, y, z, g, 6.6, 7.4, 6.4, cx=6.5, cy=7.0, cz=5.5) and z <= FACE_Z and y >= 1
            # The sagittal crest along the top.
            crest = abs(x - 6.5) < 2.0 - (y - 11) * 0.4 and 3 <= z <= 9 and 11 <= y <= 14 and inside_ellipsoid(x, y, z, g, 6.6, 9.4, 6.6, cx=6.5, cy=7.0, cz=5.5)
            # The brow: a shelf of dark fur jutting over the eyes.
            brow = 8 <= y <= 9 and 2 <= x <= 11 and FACE_Z <= z <= FACE_Z + 2 and not (z == FACE_Z + 2 and (x < 3 or x > 10))
            # The face: a flat grey plate from the brow to the chin, a voxel ahead of the cheeks.
            face = 1 <= y <= 7 and 3 <= x <= 10 and z == FACE_Z + 1 and not (y <= 1 and x in (3, 10)) and not (y == 7 and x in (3, 4, 9, 10))
            # The nose: a broad flat bump between the eyes and the mouth.
            nose = 4 <= y <= 5 and 4 <= x <= 9 and z == FACE_Z + 2 and not (y == 5 and x in (4, 9))
            # The cheeks and the sides of the face, at the face plane.
            cheek = 1 <= y <= 9 and 1 <= x <= 12 and z == FACE_Z
            # The lower jaw back to the throat.
            jaw = 1 <= y <= 3 and 4 <= x <= 9 and 6 <= z < FACE_Z
            ear = 5 <= y <= 7 and 4 <= z <= 7 and (x == 0 or x == g[0] - 1)
            if not (cran or crest or brow or face or nose or cheek or jaw or ear):
                continue
            if nose:
                c = rgb((0x5a, 0x56, 0x52))
            elif face:
                c = fur(GREY if y >= 1 else GREY_D, 0.06)
                if 1 <= y <= 3 and 4 <= x <= 9:
                    c = rgb(BLACK)          # the mouth, open
                    if y == 3 and 5 <= x <= 8:
                        c = rgb(BONE)       # the upper teeth
                    if y == 1 and 5 <= x <= 8:
                        c = rgb((0x7a, 0x22, 0x26))   # the tongue
            elif brow:
                c = fur(FUR_D, 0.05)
            elif cheek:
                c = fur(GREY_D, 0.08) if 3 <= x <= 10 and y <= 7 else pelt(x, y, z, FUR_D, 2, 0.15)
            elif ear:
                c = fur(FUR_D, 0.05)
            elif crest:
                c = fur(FUR_D, 0.06)
            else:
                c = pelt(x, y, z, FUR, 2, 0.2)
            add(head, x, y, z, c)
# The eyes: small, amber, deep under the brow (the socket row is left open at the face plate).
for x in (3, 4, 9, 10):
    add(head, x, 7, FACE_Z + 1, rgb(EYE) if x in (4, 9) else rgb(BLACK), 1)
# Nostrils: two dark pits at the foot of the nose.
for x in (5, 8):
    add(head, x, 4, FACE_Z + 3, rgb(BLACK), 1)
# Teeth: a row of small teeth in the gape, and the canines, long, at the corners of the mouth.
for x in (4, 9):
    for y in (3, 2):
        add(head, x, y, FACE_Z + 2, rgb(BONE), 1)

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

armL = limb("legFL", "Gorilla left arm", [6, 11, 6], 28, "beastBody", [-0.32, 0.33, 0.14], [0, 0.30, 0], splay=0.1)
armR = limb("legFR", "Gorilla right arm", [6, 11, 6], 28, "beastBody", [0.32, 0.33, 0.14], [0, 0.30, 0], splay=-0.1)
foreL = limb("legFLLo", "Gorilla left fist", [7, 9, 7], 28, "legFL", [0, -0.30, 0], [0, 0.24, 0], fist=True, lower=True)
foreR = limb("legFRLo", "Gorilla right fist", [7, 9, 7], 28, "legFR", [0, -0.30, 0], [0, 0.24, 0], fist=True, lower=True)
legL = limb("legBL", "Gorilla left leg", [6, 5, 6], 16, "beastBody", [-0.2, -0.26, -0.1], [0, 0.13, 0])
legR = limb("legBR", "Gorilla right leg", [6, 5, 6], 16, "beastBody", [0.2, -0.26, -0.1], [0, 0.13, 0])
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
