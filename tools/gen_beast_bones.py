#!/usr/bin/env python3
"""The beasts' skeletons, laid into their voxels in data/beasts.json (user: every beast's insides as
they should be, the skeleton, the muscles and the organs). The trunk gets a spine down the middle of
the back, ribs round the chest every other row (a point gets between them), a breastbone under
it, shoulder blades and a pelvis; every head a skull round the brain, the jaw with it; a limb, a
neck or a tail with no bone in it a core down its length; horns, tusks and a dragon's spines are
bone all through; a bat's wing (a dragon's, a manticore's) its arm along the front edge and the
fingers spread from the wrist; whatever else lies under the skin is muscle. Each bone lies under the flesh, as deep as a man's ribs lie under
his (the trunk's three voxels in: the beast's own rule, Beast._bury_bones), and is drawn as bone
when a wound bares it; the muscle is the flesh between. The organs are laid at load
(Anatomy.dress_beasts) in what flesh is left, inside the bones.

The single slab of bone the trunks and heads were modelled with (straight through the middle, no
bone a body has) gives way to these. Scorpions and spiders have no bones: their shell is their
skeleton.

    python3 tools/gen_beast_bones.py            (rewrites data/beasts.json)
    python3 tools/gen_beast_bones.py --check    (prints what it would lay, writes nothing)

numpy."""
import json
import math
import sys

import numpy as np

BONE = 0xE8E0C8
FLESH = 0x9E1B1B
FLESH2 = 0x6E0F0F
SHELLED = ("scorpion", "spider")
HARD = ("horn", "tusk", "spines", "stinger", "fang")   # parts that are bone (horn, ivory) all through


def depth_of(vox, grid):
    """Every voxel's depth under the skin: 0 on the outside, 1 under that... (6-neighbour)."""
    occ = np.zeros(tuple(int(g) + 2 for g in grid), bool)
    for v in vox:
        occ[v[0] + 1, v[1] + 1, v[2] + 1] = True
    depth = np.zeros(occ.shape, np.int16)
    cur = occ.copy()
    k = 0
    while cur.any() and k < 64:
        er = cur.copy()
        er[1:, :, :] &= cur[:-1, :, :]
        er[:-1, :, :] &= cur[1:, :, :]
        er[:, 1:, :] &= cur[:, :-1, :]
        er[:, :-1, :] &= cur[:, 1:, :]
        er[:, :, 1:] &= cur[:, :, :-1]
        er[:, :, :-1] &= cur[:, :, 1:]
        er[0, :, :] = er[-1, :, :] = False
        er[:, 0, :] = er[:, -1, :] = False
        er[:, :, 0] = er[:, :, -1] = False
        k += 1
        depth[er] = k
        cur = er
    return {(v[0], v[1], v[2]): int(depth[v[0] + 1, v[1] + 1, v[2] + 1]) for v in vox}


def _box(vox):
    xs = [v[0] for v in vox]
    ys = [v[1] for v in vox]
    zs = [v[2] for v in vox]
    lo = (min(xs), min(ys), min(zs))
    hi = (max(xs), max(ys), max(zs))
    return lo, [hi[i] - lo[i] + 1 for i in range(3)]


def _is_head(d):
    return bool(d.get("head")) or d["name"] == "beastHead"


def trunk_bones(vox, dep):
    """The trunk's: the spine, the ribs and the breastbone, the shoulder blades, the pelvis."""
    lo, ext = _box(vox)
    deep = max(dep.values())
    lay = min(3, max(1, deep - 1))   # (as deep as the body allows: three in on a big one)
    mid_x = lo[0] + (ext[0] - 1) * 0.5
    # The top of the back over each slice: the spine runs `lay` under it down the middle.
    top = {}
    for v in vox:
        if abs(v[0] - mid_x) <= 0.6:
            top[v[2]] = max(top.get(v[2], -1), v[1])
    out = {}
    for v in vox:
        key = (v[0], v[1], v[2])
        dd = dep[key]
        u = (v[0] - lo[0] + 0.5) / ext[0]
        vv = (v[1] - lo[1] + 0.5) / ext[1]
        w = (v[2] - lo[2] + 0.5) / ext[2]
        side = abs(u - 0.5)
        if abs(v[0] - mid_x) <= 0.6 and v[2] in top and top[v[2]] - v[1] == lay and dd >= lay and 0.04 < w < 0.97:
            out[key] = "spine"
            continue
        if dd != lay:
            continue
        if 0.48 < w < 0.86 and (v[2] - lo[2]) % 2 == 0 and (v[2] not in top or v[1] < top[v[2]] - lay):
            out[key] = "ribs"            # round the chest, every other row
        elif 0.48 < w < 0.86 and vv < 0.3 and side < 0.12:
            out[key] = "ribs"            # the breastbone joining them under it
        elif 0.66 < w < 0.88 and vv > 0.55 and side > 0.18:
            out[key] = "scapula"
        elif 0.03 < w < 0.2 and vv < 0.72:
            out[key] = "pelvis"
    return out


def _brain(lo, ext, v):
    """Where the brain lies in a head (Anatomy.beast_organ_at's): the skull goes round it."""
    u = (v[0] - lo[0] + 0.5) / ext[0]
    vv = (v[1] - lo[1] + 0.5) / ext[1]
    w = (v[2] - lo[2] + 0.5) / ext[2]
    return 0.12 < w < 0.45 and 0.5 < vv < 0.85 and abs(u - 0.5) < 0.22


def head_bones(d, vox, dep):
    """A head's skull: a shell under the skin all round the brain (not through it: a small head's
    shell is where its brain is), the jaw with it; open underneath where the neck comes into it (the
    hole the cord goes through, the neck's muscles: a blade takes the head off there through flesh,
    as it did)."""
    deep = max(dep.values())
    lay = 2 if deep >= 4 else 1
    if deep < 2:
        return {}
    lo, ext = _box(vox)
    hole = None
    ca = d.get("ca")
    if ca is not None:
        g = d["grid"]
        hole = [float(ca[i]) / 0.0275 + g[i] * 0.5 - 0.5 for i in range(3)]
    r = 0.42 * min(ext)
    out = {}
    for v in vox:
        if dep[(v[0], v[1], v[2])] != lay or _brain(lo, ext, v):
            continue
        if hole is not None and math.sqrt(sum((v[i] - hole[i]) ** 2 for i in range(3))) < r:
            continue
        out[(v[0], v[1], v[2])] = "skull"
    return out


def core_bones(vox, dep):
    """A limb's bone (a neck's, a tail's) down its middle along its length, under the flesh."""
    lo, ext = _box(vox)
    long_ = int(np.argmax(ext))
    thin = min(ext[a] for a in range(3) if a != long_)
    if thin < 2:
        return {}
    mid = [lo[i] + (ext[i] - 1) * 0.5 for i in range(3)]
    r = max(0.75, thin * 0.2)
    out = {}
    for v in vox:
        off = [v[i] - mid[i] for i in range(3)]
        off[long_] = 0.0
        if math.sqrt(sum(o * o for o in off)) <= r and (dep[(v[0], v[1], v[2])] >= 1 or thin < 3):
            # (too thin for flesh all round it, a rat's shin, a thin tail: its middle is bone all
            # the same, breaking as bone does; it keeps the skin's colour, being the outside too)
            out[(v[0], v[1], v[2])] = "core" if thin >= 3 else "thin"
    return out


def wing_bones(d, vox):
    """A bat's wing: the arm along its front edge from the root to the wrist, the fingers from the
    wrist to the far tip and spread back to the trailing edge (the membrane between)."""
    lo, ext = _box(vox)
    root_hi = float((d.get("ca") or [0, 0, 0])[0]) > 0.0   # (the root at the joint's end of it)
    span, chord = ext[0], ext[2]

    def at(a, b):   # a: 0 the root .. 1 the tip; b: 0 the trailing edge .. 1 the front edge
        x = lo[0] + (span - 1) * (1.0 - a if root_hi else a)
        return x, lo[2] + (chord - 1) * b

    wrist = (0.42, 0.92)
    lines = [((0.0, 0.92), wrist)] + [(wrist, t) for t in ((1.0, 0.9), (0.95, 0.5), (0.78, 0.15), (0.5, 0.0))]
    out = {}
    for v in vox:
        for (a0, b0), (a1, b1) in lines:
            p0 = np.array(at(a0, b0))
            p1 = np.array(at(a1, b1))
            q = np.array([v[0], v[2]], float)
            t = np.clip(np.dot(q - p0, p1 - p0) / max(np.dot(p1 - p0, p1 - p0), 1e-9), 0.0, 1.0)
            if np.linalg.norm(q - (p0 + (p1 - p0) * t)) <= 0.75:
                out[(v[0], v[1], v[2])] = "wing"
                break
    return out


def lay(beasts):
    report = {}
    for name, sp in beasts.items():
        if name in SHELLED:
            continue
        rows = []
        for d in sp["parts"]:
            vox = d["voxels"]
            if not vox:
                continue
            pn = d["name"].lower()
            dep = depth_of(vox, d["grid"])
            bones = {}
            redo = False
            if d.get("parent") is None and pn == "beastbody":
                bones = trunk_bones(vox, dep)
                redo = True
            elif _is_head(d):
                bones = head_bones(d, vox, dep)
                redo = True
            elif any(pn.startswith(h) or h in pn for h in HARD):
                bones = {(v[0], v[1], v[2]): "hard" for v in vox}
            elif pn.startswith("wing") and float(d.get("wing", 0)) != 0.0 and d["grid"][1] <= 3 and not any(v[4] for v in vox):
                bones = wing_bones(d, vox)
            elif not any(v[4] for v in vox) and (pn.startswith(("leg", "arm", "tail", "neck", "coil", "wing", "goatneck"))) and "fin" not in pn:
                bones = core_bones(vox, dep)
            # The muscle: whatever lies under the skin that is not bone is flesh (the gorilla was
            # modelled fur all through: cut open, it showed fur inside).
            n_meat = 0
            for v in vox:
                if dep[(v[0], v[1], v[2])] >= 1 and not v[4] and int(v[3]) not in (FLESH, FLESH2, BONE):
                    v[3] = FLESH if (v[0] + v[1] * 3 + v[2] * 5) % 3 else FLESH2
                    n_meat += 1
            if n_meat:
                rows.append("%s muscle %d" % (d["name"], n_meat))
            if not bones:
                continue   # (a head too small for a skull keeps the bone it was modelled with)
            n_old = sum(1 for v in vox if v[4])
            for v in vox:
                key = (v[0], v[1], v[2])
                if redo and v[4] and dep[key] > 0:
                    # (the old slab inside: flesh again, unless the new skeleton has it; what shows
                    # on the outside, a tooth, a horn's root, stays as it is)
                    v[4] = 0
                    if int(v[3]) == BONE:
                        v[3] = FLESH
                if key in bones:
                    v[4] = 1
                    if dep[key] > 0 and bones[key] not in ("wing", "thin"):
                        v[3] = BONE   # (under the skin: drawn as bone when a wound bares it)
            kinds = {}
            for k in bones.values():
                kinds[k] = kinds.get(k, 0) + 1
            rows.append("%s %d->%d %s" % (d["name"], n_old, sum(1 for v in vox if v[4]), kinds))
        report[name] = rows
    return report


def main():
    check = "--check" in sys.argv
    path = "data/beasts.json"
    s = open(path).read()
    beasts = json.loads(s)
    report = lay(beasts)
    for name, rows in report.items():
        print("==", name)
        for r in rows:
            print("   ", r)
    if not check:
        with open(path, "w") as fh:
            fh.write(json.dumps(beasts, separators=(",", ":")))
        print("written", path)


if __name__ == "__main__":
    main()
