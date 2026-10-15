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

# ---------------- body: a barrel, deeper than it is wide, the chest to the front (+z) ----------------
body = part("beastBody", "Gorilla body", [12, 14, 13], 320, None, None, None, [0, 1.55, 0], mult=0.55)
g = body["grid"]
for x in range(g[0]):
    for y in range(g[1]):
        for z in range(g[2]):
            # The trunk: a rounded barrel, broader at the shoulders (front) and the belly low.
            front = z / (g[2] - 1)
            rx = 11.2 + 1.2 * front
            ry = 11.0 + 0.8 * front
            # Below the barrel hangs the loincloth: a red flap down the front, the skull on it.
            if y < 4:
                flap = 0.55 < front < 0.96 and abs(x - 11.5) < 6.5 and (y > 0 or abs(x - 11.5) < 4.5)
                if not flap:
                    continue
                c = fur(RED if (y + z + x) % 3 else RED_D, 0.05)
                if front > 0.88 and abs(x - 11.5) <= 2.0 and 1 <= y <= 3:
                    add(body, x, y, z, rgb(BONE), 1)
                    continue
                add(body, x, y, z, c)
                continue
            if not inside_ellipsoid(x, y, z, g, rx, ry, 12.6, cy=15.5):
                continue
            c = fur(FUR_L if rng.random() < 0.18 else FUR)   # the pelt catches light in tufts
            chest = front > 0.68 and 8 <= y <= 23 and abs(x - 11.5) < 9.5
            if chest:
                c = fur(GREY, 0.08)
            # The silver saddle over the back.
            if y >= 21 and 0.1 < front < 0.72 and abs(x - 11.5) < 10:
                c = fur(SILVER, 0.06)
            # The loincloth: a red cloth hung low round the belly, a skull at its front.
            cloth = y <= 7 and abs(x - 11.5) < 11 and 0.15 < front
            if cloth:
                c = fur(RED if (y + z + x) % 3 else RED_D, 0.05)
            if y == 8 and 0.1 < front and abs(x - 11.5) < 11.5:
                c = rgb(GOLD)   # the belt
            add(body, x, y, z, c)

# ---------------- head: a cranium with a crest, a heavy brow over sunken eyes, a jutting grey
# muzzle, the mouth open on long canines ----------------
head = part("beastHead", "Gorilla head", [9, 9, 9], 55, "beastBody", [0, 0.36, 0.34], [0, -0.06, -0.19], [0, 0, 0],
            head=True, bite=True, jaw={"from": 0.6, "y": 0.3}, mult=1.3)
g = head["grid"]
FACE_Z = 14          # the plane of the face; the brow and the muzzle stand out in front of it
for x in range(g[0]):
    for y in range(g[1]):
        for z in range(g[2]):
            # The cranium: an egg, tallest a little behind the middle, cut flat at the face.
            cran = inside_ellipsoid(x, y, z, g, 8.6, 9.2, 8.2, cx=8.5, cy=9.5, cz=7.5) and z <= FACE_Z and y >= 6
            # The crest along the top of the skull.
            crest = abs(x - 8.5) < 1.5 and 4 <= z <= 12 and inside_ellipsoid(x, y, z, g, 8.6, 10.2, 8.2, cx=8.5, cy=9.5, cz=7.5) and y >= 15
            # The brow: a shelf of bone and fur jutting over the eyes.
            brow = 12 <= y <= 13 and 3 <= x <= 14 and FACE_Z - 1 <= z <= FACE_Z + 2 and not (z == FACE_Z + 2 and (x < 4 or x > 13))
            # The muzzle: a broad grey block standing out below the eyes, rounded at the corners.
            muz = 2 <= y <= 9 and 4 <= x <= 13 and FACE_Z - 1 <= z <= FACE_Z + 3
            if muz and z == FACE_Z + 3 and (x in (4, 13) or y in (2, 9)):
                muz = False
            if muz and z >= FACE_Z + 2 and ((x in (4, 13) and y in (2, 3, 8, 9)) or (y == 2 and x in (4, 5, 12, 13))):
                muz = False
            if muz and y <= 3 and (x in (4, 13)):
                muz = False   # the chin narrower than the cheeks
            # The cheeks and the sides of the face, back from the muzzle.
            cheek = 6 <= y <= 11 and 1 <= x <= 16 and z == FACE_Z and not (4 <= x <= 13 and 9 <= y <= 11)
            # Eye sockets: hollows under the brow (no voxel at the face plane there).
            socket = 9 <= y <= 11 and (4 <= x <= 6 or 11 <= x <= 13) and z == FACE_Z
            # The lower jaw under the muzzle, back to the throat.
            jaw = 2 <= y <= 5 and 5 <= x <= 12 and 8 <= z < FACE_Z - 1
            ear = 8 <= y <= 11 and 7 <= z <= 10 and (x == 0 or x == g[0] - 1)
            if socket:
                continue
            if not (cran or crest or brow or muz or cheek or jaw or ear):
                continue
            if muz:
                c = fur(GREY if y >= 6 else GREY_D, 0.06)
                if y == 5 and z >= FACE_Z + 1:
                    c = rgb(BLACK)          # the mouth, a dark line between the lips
                if y in (4, 3) and z == FACE_Z + 3 and 6 <= x <= 11:
                    c = rgb(BLACK)          # the gape
            elif brow:
                c = fur(FUR_D, 0.05)
            elif cheek:
                c = fur(GREY_D, 0.08)
            elif ear:
                c = fur(FUR_D, 0.05)
            else:
                c = fur(FUR_L if rng.random() < 0.18 else FUR, 0.14)
                if crest:
                    c = fur(FUR_D, 0.06)
            add(head, x, y, z, c)
# The eyes, small and deep in their sockets, catching the torchlight.
for x in (5, 12):
    add(head, x, 10, FACE_Z - 1, rgb(EYE), 1)
    add(head, x + 1, 10, FACE_Z - 1, rgb(EYE), 1)
    add(head, x, 9, FACE_Z - 1, rgb(BLACK), 1)
    add(head, x + 1, 9, FACE_Z - 1, rgb(BLACK), 1)
    add(head, x, 11, FACE_Z - 1, rgb(FUR_D), 1)
    add(head, x + 1, 11, FACE_Z - 1, rgb(FUR_D), 1)
# Nostrils: two dark pits on the top of the muzzle.
for x in (7, 10):
    add(head, x, 8, FACE_Z + 3, rgb(BLACK), 1)
    add(head, x, 8, FACE_Z + 2, rgb(BLACK), 1)
# Teeth: a row of small teeth in the gape, and the canines, long, at the corners of the mouth.
for x in range(6, 12):
    add(head, x, 4, FACE_Z + 3, rgb(BONE), 1)
for x in (5, 12):
    for y in (6, 5, 4, 3):
        add(head, x, y, FACE_Z + 3, rgb(BONE), 1)
    add(head, x, 2, FACE_Z + 3, rgb(BONE), 1)

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
                c = fur(FUR_L if rng.random() < 0.18 else FUR, 0.14)
                if fist and t < 0.22:
                    c = fur(FUR_D if (x + z) % 2 else NAIL, 0.1)
                p["voxels"].append([x, y, z, c, 0])
    return p

armL = limb("legFL", "Gorilla left arm", [7, 10, 7], 30, "beastBody", [-0.34, 0.32, 0.24], [0, 0.27, 0], splay=0.1)
armR = limb("legFR", "Gorilla right arm", [7, 10, 7], 30, "beastBody", [0.34, 0.32, 0.24], [0, 0.27, 0], splay=-0.1)
foreL = limb("legFLLo", "Gorilla left fist", [7, 9, 7], 26, "legFL", [0, -0.27, 0], [0, 0.24, 0], fist=True, lower=True)
foreR = limb("legFRLo", "Gorilla right fist", [7, 9, 7], 26, "legFR", [0, -0.27, 0], [0, 0.24, 0], fist=True, lower=True)
legL = limb("legBL", "Gorilla left leg", [5, 5, 5], 14, "beastBody", [-0.19, -0.24, -0.16], [0, 0.13, 0])
legR = limb("legBR", "Gorilla right leg", [5, 5, 5], 14, "beastBody", [0.19, -0.24, -0.16], [0, 0.13, 0])
shinL = limb("legBLLo", "Gorilla left foot", [5, 5, 5], 10, "legBL", [0, -0.13, 0], [0, 0.13, 0], fist=True, lower=True)
shinR = limb("legBRLo", "Gorilla right foot", [5, 5, 5], 10, "legBR", [0, -0.13, 0], [0, 0.13, 0], fist=True, lower=True)

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
