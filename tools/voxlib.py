"""Voxel sculpting, meshing and .glb export for the arena's art (tools/gen_voxel_art.py).

A model is a dense grid of cells. Each cell holds 0 (empty) or a packed colour:
material << 24 | r << 16 | g << 8 | b, in sRGB bytes. The mesher draws only the faces that
touch air, bakes ambient occlusion into the vertex colours (the dark creases that make voxel
art read), merges flat unoccluded runs of one colour into larger quads, and writes one
primitive per material, named so the game can give each its own shader settings.
"""
import json
import struct

import numpy as np
from numba import njit

# Materials: id -> name. The game maps each name to a shader (scripts/game/voxel_art.gd).
MATS = {1: "stone", 2: "wood", 3: "iron", 4: "bronze", 5: "gold", 6: "cloth", 7: "ember",
        8: "plaster", 9: "marble", 10: "terracotta", 11: "straw", 12: "glow"}
MAT_ID = {v: k for k, v in MATS.items()}
AO_CURVE = np.array([0.42, 0.62, 0.82, 1.0], np.float32)


def srgb_to_linear(c):
    c = np.asarray(c, np.float32)
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def pack(mat, rgb):
    """Packs a material name and colours (k, 3) in 0..1 (or one colour) into cell values."""
    rgb = np.clip(np.asarray(rgb, np.float32), 0.0, 1.0)
    b = np.round(rgb * 255).astype(np.uint32)
    m = np.uint32(MAT_ID[mat])
    if b.ndim == 1:
        return np.uint32(m << 24 | b[0] << 16 | b[1] << 8 | b[2])
    return (m << 24) | (b[:, 0] << 16) | (b[:, 1] << 8) | b[:, 2]


def hash3(ix, iy, iz, seed=0):
    """A float in [0, 1) per integer triple, the same every run."""
    h = (np.asarray(ix, np.int64) * 73856093) ^ (np.asarray(iy, np.int64) * 19349663) ^ \
        (np.asarray(iz, np.int64) * 83492791) ^ (seed * 2654435761)
    h = (h ^ (h >> 13)) * 1274126177
    h = h ^ (h >> 16)
    return (h & 0xFFFF).astype(np.float32) / 65536.0


def vnoise(x, y, z, scale, seed=0):
    """Smooth value noise in [0, 1] at world positions (trilinear between lattice hashes)."""
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


def tint(base, amount, *noises):
    """`base` colour scaled by (1 + amount * (n - 0.5) * 2) for each noise array, as (k, 3)."""
    k = len(noises[0])
    c = np.tile(np.asarray(base, np.float32), (k, 1))
    for n in noises:
        c *= (1.0 + amount * (np.asarray(n, np.float32) - 0.5) * 2.0)[:, None]
    return c


class Sculpt:
    """A box of voxels of size `vs` whose lowest corner sits at `lo` (metres)."""

    def __init__(self, vs, lo, hi):
        self.vs = vs
        self.lo = np.asarray(lo, np.float64)
        n = np.ceil((np.asarray(hi) - self.lo) / vs - 1e-6).astype(int)
        self.c = np.zeros(tuple(n), np.uint32)
        self._centers = None

    @property
    def shape(self):
        return self.c.shape

    def axis(self, a):
        """Cell centres along axis a."""
        return self.lo[a] + (np.arange(self.c.shape[a]) + 0.5) * self.vs

    def grids(self):
        if self._centers is None:
            x = self.axis(0)[:, None, None]
            y = self.axis(1)[None, :, None]
            z = self.axis(2)[None, None, :]
            self._centers = (x, y, z)
        return self._centers

    def put(self, mask, col):
        """Fills the cells in `mask` (bool, the grid's shape) with `col`: a packed value, or a
        function f(ix, iy, iz, x, y, z) of index and centre arrays returning packed values."""
        idx = np.nonzero(mask)
        if len(idx[0]) == 0:
            return
        if callable(col):
            x = self.lo[0] + (idx[0] + 0.5) * self.vs
            y = self.lo[1] + (idx[1] + 0.5) * self.vs
            z = self.lo[2] + (idx[2] + 0.5) * self.vs
            self.c[idx] = col(idx[0], idx[1], idx[2], x, y, z)
        else:
            self.c[idx] = col

    def carve(self, mask):
        self.c[mask] = 0

    def recolor(self, mask, col):
        self.put(mask & (self.c != 0), col)

    # ---- shapes, all in metres ----
    def box_mask(self, a, b):
        x, y, z = self.grids()
        return (x >= a[0]) & (x < b[0]) & (y >= a[1]) & (y < b[1]) & (z >= a[2]) & (z < b[2])

    def box(self, a, b, col):
        self.put(self.box_mask(a, b), col)

    def cyl_mask(self, c, r, y0, y1, axis=1, r_in=0.0):
        x, y, z = self.grids()
        if axis == 1:
            d2 = (x - c[0]) ** 2 + (z - c[2]) ** 2
            along = (y >= y0) & (y < y1)
        elif axis == 0:
            d2 = (y - c[1]) ** 2 + (z - c[2]) ** 2
            along = (x >= y0) & (x < y1)
        else:
            d2 = (x - c[0]) ** 2 + (y - c[1]) ** 2
            along = (z >= y0) & (z < y1)
        return (d2 < r * r) & (d2 >= r_in * r_in) & along

    def cyl(self, c, r, y0, y1, col, axis=1, r_in=0.0):
        self.put(self.cyl_mask(c, r, y0, y1, axis, r_in), col)

    def sphere_mask(self, c, r, scale=(1, 1, 1)):
        x, y, z = self.grids()
        return ((x - c[0]) / scale[0]) ** 2 + ((y - c[1]) / scale[1]) ** 2 + ((z - c[2]) / scale[2]) ** 2 < r * r

    def sphere(self, c, r, col, scale=(1, 1, 1)):
        self.put(self.sphere_mask(c, r, scale), col)

    def lathe_mask(self, c, profile, y0, y1, thick=0.0):
        """A solid of revolution round the vertical through c: radius profile(t), t in 0..1 from
        y0 to y1. With `thick`, only a shell that thick (open at the top)."""
        x, y, z = self.grids()
        t = np.clip((y - y0) / (y1 - y0), 0, 1)
        r = profile(t)
        d = np.sqrt((x - c[0]) ** 2 + (z - c[2]) ** 2)
        m = (d < r) & (y >= y0) & (y < y1)
        if thick > 0:
            m &= (d >= r - thick) | (y < y0 + thick)
        return m

    def seg_mask(self, a, b, r):
        """A rod of radius r from a to b."""
        x, y, z = self.grids()
        a = np.asarray(a, float)
        b = np.asarray(b, float)
        ab = b - a
        L2 = float(ab @ ab)
        t = ((x - a[0]) * ab[0] + (y - a[1]) * ab[1] + (z - a[2]) * ab[2]) / L2
        t = np.clip(t, 0, 1)
        dx = x - (a[0] + ab[0] * t)
        dy = y - (a[1] + ab[1] * t)
        dz = z - (a[2] + ab[2] * t)
        return dx * dx + dy * dy + dz * dz < r * r

    def seg(self, a, b, r, col):
        self.put(self.seg_mask(a, b, r), col)


# ---------------------------------------------------------------- meshing

@njit(cache=True)
def _solid(c, x, y, z):
    if x < 0 or y < 0 or z < 0 or x >= c.shape[0] or y >= c.shape[1] or z >= c.shape[2]:
        return 0
    return 1 if c[x, y, z] != 0 else 0


@njit(cache=True)
def _same_ao(ao, u0, v0, u1, v1):
    for i in range(4):
        if ao[u0, v0, i] != ao[u1, v1, i]:
            return False
    return True


@njit(cache=True)
def _mesh(c, vs, ox, oy, oz, cull_r, cull_floor):
    """Greedy meshing with per-vertex AO. Returns quads: corners (n, 4, 3), normal axis/sign
    (n, 2), colour (n,) and AO (n, 4)."""
    nx, ny, nz = c.shape
    cap = 1 << 16
    pos = np.zeros((cap, 4, 3), np.float32)
    nrm = np.zeros((cap, 2), np.int8)
    col = np.zeros(cap, np.uint32)
    aos = np.zeros((cap, 4), np.uint8)
    n = 0
    dims = (nx, ny, nz)
    org = (ox, oy, oz)
    for a in range(3):
        u_ax = (a + 1) % 3
        v_ax = (a + 2) % 3
        du = dims[u_ax]
        dv = dims[v_ax]
        for s in (-1, 1):
            for k in range(dims[a]):
                key = np.zeros((du, dv), np.uint32)
                ao = np.zeros((du, dv, 4), np.uint8)
                single = np.zeros((du, dv), np.uint8)
                plane = org[a] + (k + (1 if s > 0 else 0)) * vs
                for u in range(du):
                    for v in range(dv):
                        p = [0, 0, 0]
                        p[a] = k
                        p[u_ax] = u
                        p[v_ax] = v
                        cv = c[p[0], p[1], p[2]]
                        if cv == 0:
                            continue
                        q = [p[0], p[1], p[2]]
                        q[a] = k + s
                        if _solid(c, q[0], q[1], q[2]):
                            continue
                        # Culling: floors never seen from below, the far side of the bowl.
                        if a == 1 and s < 0 and plane <= cull_floor:
                            continue
                        # A face whose plane lies further than cull_r out along its own
                        # normal faces away from every camera inside that radius.
                        if cull_r > 0 and a != 1:
                            cx = ox + (p[0] + 0.5) * vs
                            cz = oz + (p[2] + 0.5) * vs
                            if a == 0 and s * plane > cull_r:
                                continue
                            if a == 2 and s * plane > cull_r:
                                continue
                        # AO from the 8 cells round the face, in the air layer in front of it.
                        allfull = True
                        for ci in range(4):
                            su = -1 if (ci == 0 or ci == 3) else 1
                            sv = -1 if (ci == 0 or ci == 1) else 1
                            t1 = [q[0], q[1], q[2]]
                            t1[u_ax] += su
                            t2 = [q[0], q[1], q[2]]
                            t2[v_ax] += sv
                            t3 = [q[0], q[1], q[2]]
                            t3[u_ax] += su
                            t3[v_ax] += sv
                            s1 = _solid(c, t1[0], t1[1], t1[2])
                            s2 = _solid(c, t2[0], t2[1], t2[2])
                            s3 = _solid(c, t3[0], t3[1], t3[2])
                            val = 0 if (s1 == 1 and s2 == 1) else 3 - (s1 + s2 + s3)
                            ao[u, v, ci] = val
                            if val != 3:
                                allfull = False
                        key[u, v] = cv
                        # Which way this face may merge: shading constant along u, along v, or both.
                        cu_ok = ao[u, v, 0] == ao[u, v, 1] and ao[u, v, 3] == ao[u, v, 2]
                        cv_ok = ao[u, v, 0] == ao[u, v, 3] and ao[u, v, 1] == ao[u, v, 2]
                        single[u, v] = 0 if allfull else ((1 if cu_ok else 0) | (2 if cv_ok else 0) | 4)
                used = np.zeros((du, dv), np.uint8)
                for v in range(dv):
                    for u in range(du):
                        kv = key[u, v]
                        if kv == 0 or used[u, v]:
                            continue
                        w = 1
                        h = 1
                        mode = single[u, v]
                        can_u = mode == 0 or (mode & 1) != 0
                        can_v = mode == 0 or (mode & 2) != 0
                        if can_u:
                            while u + w < du and key[u + w, v] == kv and single[u + w, v] == mode and used[u + w, v] == 0 and _same_ao(ao, u, v, u + w, v):
                                w += 1
                        if can_v:
                            done = False
                            while v + h < dv and not done:
                                for uu in range(u, u + w):
                                    if key[uu, v + h] != kv or single[uu, v + h] != mode or used[uu, v + h] != 0 or not _same_ao(ao, u, v, uu, v + h):
                                        done = True
                                        break
                                if not done:
                                    h += 1
                        for uu in range(u, u + w):
                            for vv in range(v, v + h):
                                used[uu, vv] = 1
                        if n >= pos.shape[0]:
                            pos2 = np.zeros((pos.shape[0] * 2, 4, 3), np.float32)
                            pos2[:n] = pos[:n]
                            pos = pos2
                            nrm2 = np.zeros((nrm.shape[0] * 2, 2), np.int8)
                            nrm2[:n] = nrm[:n]
                            nrm = nrm2
                            col2 = np.zeros(col.shape[0] * 2, np.uint32)
                            col2[:n] = col[:n]
                            col = col2
                            aos2 = np.zeros((aos.shape[0] * 2, 4), np.uint8)
                            aos2[:n] = aos[:n]
                            aos = aos2
                        u0 = org[u_ax] + u * vs
                        u1 = org[u_ax] + (u + w) * vs
                        v0 = org[v_ax] + v * vs
                        v1 = org[v_ax] + (v + h) * vs
                        cu = (u0, u1, u1, u0)
                        cvv = (v0, v0, v1, v1)
                        for ci in range(4):
                            pos[n, ci, a] = plane
                            pos[n, ci, u_ax] = cu[ci]
                            pos[n, ci, v_ax] = cvv[ci]
                            aos[n, ci] = ao[u, v, ci] if mode else 3
                        nrm[n, 0] = a
                        nrm[n, 1] = s
                        col[n] = kv
                        n += 1
    return pos[:n], nrm[:n], col[:n], aos[:n]


def mesh(sc, cull_r=0.0, cull_floor=-1e9):
    """Quads of a Sculpt, in its own coordinates."""
    return _mesh(sc.c, float(sc.vs), float(sc.lo[0]), float(sc.lo[1]), float(sc.lo[2]),
                 float(cull_r), float(cull_floor))


def primitives(quads, split=None):
    """Vertex arrays per (group, material) from quads. `split(centres) -> group ids` breaks a big
    model into chunks the renderer can cull."""
    pos, nrm, col, ao = quads
    if len(pos) == 0:
        return {}
    centres = pos.mean(axis=1)
    groups = split(centres) if split else np.zeros(len(pos), int)
    mats = (col >> 24).astype(int)
    rgb = np.stack([(col >> 16) & 255, (col >> 8) & 255, col & 255], 1).astype(np.float32) / 255.0
    lin = srgb_to_linear(rgb)
    normal = np.zeros((len(pos), 3), np.float32)
    normal[np.arange(len(pos)), nrm[:, 0].astype(int)] = nrm[:, 1]
    vcol = lin[:, None, :] * AO_CURVE[ao][:, :, None]          # (n, 4, 3)
    # Winding: counter-clockwise seen from outside (glTF). Flip the diagonal where AO says so.
    e1 = pos[:, 1] - pos[:, 0]
    e2 = pos[:, 2] - pos[:, 0]
    ccw = (np.cross(e1, e2) * normal).sum(1) > 0
    flip = ao[:, 0].astype(int) + ao[:, 2] < ao[:, 1].astype(int) + ao[:, 3]
    out = {}
    for g in np.unique(groups):
        for m in np.unique(mats[groups == g]):
            sel = np.nonzero((groups == g) & (mats == m))[0]
            P = pos[sel].reshape(-1, 3)
            N = np.repeat(normal[sel], 4, axis=0)
            C = vcol[sel].reshape(-1, 3)
            base = (np.arange(len(sel)) * 4)[:, None]
            # Triangles (0,1,2)(0,2,3) or, flipped, (1,2,3)(1,3,0); reversed if clockwise.
            t_norm = np.array([0, 1, 2, 0, 2, 3])
            t_flip = np.array([1, 2, 3, 1, 3, 0])
            tri = np.where(flip[sel][:, None], t_flip[None, :], t_norm[None, :])
            rev = ~ccw[sel]
            tri[rev] = tri[rev][:, [0, 2, 1, 3, 5, 4]]
            I = (base + tri).reshape(-1).astype(np.uint32)
            out[(int(g), MATS[int(m)])] = (P.astype(np.float32), N, C, I)
    return out


# ---------------------------------------------------------------- glTF

def write_glb(path, meshes, vs):
    """meshes: {node name: {material: (P, N, C, I)}}. Material names carry the voxel size in
    centimetres ("stone@10") so the game's shader can find each voxel's cell."""
    buf = bytearray()
    views, accs, gl_meshes, nodes, mats = [], [], [], [], []
    mat_index = {}

    def add_view(data, target):
        while len(buf) % 4:
            buf.append(0)
        off = len(buf)
        buf.extend(data)
        views.append({"buffer": 0, "byteOffset": off, "byteLength": len(data), "target": target})
        return len(views) - 1

    def add_acc(arr, ctype, typ, target, normalized=False, minmax=False):
        v = add_view(arr.tobytes(), target)
        a = {"bufferView": v, "componentType": ctype, "count": int(arr.shape[0]), "type": typ}
        if normalized:
            a["normalized"] = True
        if minmax:
            a["min"] = arr.min(0).tolist()
            a["max"] = arr.max(0).tolist()
        accs.append(a)
        return len(accs) - 1

    tag = "%g" % round(vs * 100, 2)
    for name, prims in meshes.items():
        gp = []
        for mat, (P, N, C, I) in prims.items():
            key = "%s@%s" % (mat, tag)
            if key not in mat_index:
                mat_index[key] = len(mats)
                mats.append({"name": key, "pbrMetallicRoughness": {"baseColorFactor": [1, 1, 1, 1],
                             "metallicFactor": 0.0, "roughnessFactor": 0.9}})
            cb = np.clip(np.round(C * 255), 0, 255).astype(np.uint8)
            cb = np.concatenate([cb, np.full((len(cb), 1), 255, np.uint8)], 1)
            gp.append({
                "attributes": {
                    "POSITION": add_acc(P, 5126, "VEC3", 34962, minmax=True),
                    "NORMAL": add_acc(N, 5126, "VEC3", 34962),
                    "COLOR_0": add_acc(cb, 5121, "VEC4", 34962, normalized=True),
                },
                "indices": add_acc(I, 5125, "SCALAR", 34963),
                "material": mat_index[key],
            })
        if not gp:
            continue
        gl_meshes.append({"name": name, "primitives": gp})
        nodes.append({"name": name, "mesh": len(gl_meshes) - 1})
    gltf = {"asset": {"version": "2.0", "generator": "voxel arena tools/voxlib.py"},
            "scene": 0, "scenes": [{"nodes": list(range(len(nodes)))}], "nodes": nodes,
            "meshes": gl_meshes, "materials": mats, "accessors": accs, "bufferViews": views,
            "buffers": [{"byteLength": len(buf)}]}
    js = json.dumps(gltf, separators=(",", ":")).encode()
    while len(js) % 4:
        js += b" "
    while len(buf) % 4:
        buf.append(0)
    total = 12 + 8 + len(js) + 8 + len(buf)
    with open(path, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, total))
        f.write(struct.pack("<II", len(js), 0x4E4F534A))
        f.write(js)
        f.write(struct.pack("<II", len(buf), 0x004E4942))
        f.write(buf)
    tris = sum(len(p[3]) // 3 for m in meshes.values() for p in m.values())
    return tris


def export(sc, path, name=None, cull_r=0.0, cull_floor=-1e9, split=None, split_names=None):
    q = mesh(sc, cull_r, cull_floor)
    prims = primitives(q, split)
    meshes = {}
    for (g, m), arr in prims.items():
        nm = (split_names[g] if split_names else (name or "model")) if split else (name or "model")
        meshes.setdefault(nm, {})[m] = arr
    tris = write_glb(path, meshes, sc.vs)
    return tris
