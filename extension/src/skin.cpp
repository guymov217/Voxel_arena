#include "voxel_core.h"

#include <cstdint>
#include <cmath>
#include <cstring>
#include <vector>

using namespace godot;

// VoxelSkin.build's surface, step for step as the script does it (Surface Nets on the part's
// living voxels, `relax` passes toward the neighbours' mean). Returns [verts, idx, qcol]: the
// vertices in the part's frame, two triangles per quad and the voxel each quad covers.
Array VoxelCore::skin_net(const PackedInt32Array &fx, const PackedInt32Array &fy, const PackedInt32Array &fz, const PackedByteArray &alive, const Vector3i &g, double vs, int relax, double relax_k) const {
	Array res;
	const int64_t n = fx.size();
	if (fy.size() < n || fz.size() < n || alive.size() < n) {
		return res;
	}
	const int sx = g.x + 2;
	const int sxy = sx * (g.y + 2);
	std::vector<uint8_t> occ((size_t)sxy * (g.z + 2), 0);
	std::vector<int32_t> who(occ.size(), -1);
	bool any = false;
	for (int64_t i = 0; i < n; i++) {
		if (alive[i]) {
			const int k = (fx[i] + 1) + (fy[i] + 1) * sx + (fz[i] + 1) * sxy;
			occ[k] = 1;
			who[k] = (int32_t)i;
			any = true;
		}
	}
	if (!any) {
		return res;
	}
	const int cx = g.x + 1;
	const int cxy = cx * (g.y + 1);
	std::vector<int32_t> vid((size_t)cxy * (g.z + 1), -1);
	const int corner[8] = { 0, 1, sx, sx + 1, sxy, sxy + 1, sxy + sx, sxy + sx + 1 };
	const Vector3 cofs[8] = { Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(1, 1, 0), Vector3(0, 0, 1), Vector3(1, 0, 1), Vector3(0, 1, 1), Vector3(1, 1, 1) };
	const int edges[12][2] = { { 0, 1 }, { 2, 3 }, { 4, 5 }, { 6, 7 }, { 0, 2 }, { 1, 3 }, { 4, 6 }, { 5, 7 }, { 0, 4 }, { 1, 5 }, { 2, 6 }, { 3, 7 } };
	const Vector3 centre = Vector3(g.x - 1, g.y - 1, g.z - 1) * 0.5;
	const real_t s = (real_t)vs;
	std::vector<Vector3> verts;
	for (int z = 0; z <= g.z; z++) {
		for (int y = 0; y <= g.y; y++) {
			for (int x = 0; x <= g.x; x++) {
				const int base = x + y * sx + z * sxy;
				int mask = 0;
				for (int d = 0; d < 8; d++) {
					if (occ[base + corner[d]]) {
						mask |= 1 << d;
					}
				}
				if (mask == 0 || mask == 255) {
					continue;
				}
				Vector3 sum;
				int cnt = 0;
				for (int e = 0; e < 12; e++) {
					const int a = edges[e][0];
					const int b = edges[e][1];
					if (((mask >> a) & 1) != ((mask >> b) & 1)) {
						sum += (cofs[a] + cofs[b]) * 0.5;
						cnt++;
					}
				}
				const Vector3 p = Vector3(x, y, z) + sum / (real_t)cnt - Vector3(1, 1, 1);
				vid[x + y * cx + z * cxy] = (int32_t)verts.size();
				verts.push_back((p - centre) * s);
			}
		}
	}
	std::vector<int32_t> idx;
	std::vector<int32_t> qcol;
	std::vector<std::vector<int32_t>> nb(verts.size());
	for (int z = 0; z <= g.z; z++) {
		for (int y = 0; y <= g.y; y++) {
			for (int x = 0; x <= g.x; x++) {
				const int k = x + y * sx + z * sxy;
				const uint8_t a = occ[k];
				for (int ax = 0; ax < 3; ax++) {
					const int k2 = k + (ax == 0 ? 1 : (ax == 1 ? sx : sxy));
					const uint8_t b = occ[k2];
					if (a == b) {
						continue;
					}
					const Vector3i c0(x, y, z);
					const Vector3i u = ax == 0 ? Vector3i(0, 1, 0) : (ax == 1 ? Vector3i(0, 0, 1) : Vector3i(1, 0, 0));
					const Vector3i v = ax == 0 ? Vector3i(0, 0, 1) : (ax == 1 ? Vector3i(1, 0, 0) : Vector3i(0, 1, 0));
					const Vector3i os[4] = { Vector3i(), u, u + v, v };
					int32_t q[4];
					bool ok = true;
					for (int o = 0; o < 4; o++) {
						const Vector3i cc = c0 - u - v + os[o];
						if (cc.x < 0 || cc.y < 0 || cc.z < 0 || cc.x > g.x || cc.y > g.y || cc.z > g.z) {
							ok = false;
							break;
						}
						const int32_t id = vid[cc.x + cc.y * cx + cc.z * cxy];
						if (id < 0) {
							ok = false;
							break;
						}
						q[o] = id;
					}
					if (!ok) {
						continue;
					}
					if (a) {
						idx.insert(idx.end(), { q[0], q[2], q[1], q[0], q[3], q[2] });
					} else {
						idx.insert(idx.end(), { q[0], q[1], q[2], q[0], q[2], q[3] });
					}
					qcol.push_back(a ? who[k] : who[k2]);
					for (int e = 0; e < 4; e++) {
						const int32_t p0 = q[e];
						const int32_t p1 = q[(e + 1) % 4];
						nb[p0].push_back(p1);
						nb[p1].push_back(p0);
					}
				}
			}
		}
	}
	if (idx.empty()) {
		return res;
	}
	for (int r = 0; r < relax; r++) {
		std::vector<Vector3> out = verts;
		for (size_t i = 0; i < verts.size(); i++) {
			if (nb[i].empty()) {
				continue;
			}
			Vector3 m;
			for (int32_t j : nb[i]) {
				m += verts[j];
			}
			out[i] = verts[i].lerp(m / (real_t)nb[i].size(), (real_t)relax_k);
		}
		verts.swap(out);
	}
	PackedVector3Array pv;
	pv.resize(verts.size());
	for (size_t i = 0; i < verts.size(); i++) {
		pv.set(i, verts[i]);
	}
	PackedInt32Array pi;
	pi.resize(idx.size());
	memcpy(pi.ptrw(), idx.data(), idx.size() * sizeof(int32_t));
	PackedInt32Array pq;
	pq.resize(qcol.size());
	memcpy(pq.ptrw(), qcol.data(), qcol.size() * sizeof(int32_t));
	res.append(pv);
	res.append(pi);
	res.append(pq);
	return res;
}

// VoxelSkin.build's crisp drawing: smooth normals from the faces round each vertex, then every
// quad its own four corners in the colour of its voxel (`colors` over its `grain`, opaque) and
// its data for voxel_skin.gdshader (kind / 16, fire, poison from the sparse `glow_i`/`glow_v`,
// and a seed); with `flat` each quad shaded by its own face. Returns [verts, normals, colours,
// idx, custom0 (four floats a vertex)].
Array VoxelCore::skin_crisp(const PackedVector3Array &verts, const PackedInt32Array &idx, const PackedInt32Array &qcol, const PackedColorArray &colors, const PackedFloat32Array &grain, const PackedByteArray &kinds, const PackedInt32Array &glow_i, const PackedVector2Array &glow_v, bool flat) const {
	Array res;
	const int64_t nv = verts.size();
	const int64_t nq = qcol.size();
	const int64_t nvox = colors.size();
	if (idx.size() < nq * 6 || grain.size() < nvox || kinds.size() < nvox) {
		return res;
	}
	std::vector<Vector2> glow(nvox);
	for (int64_t j = 0; j < glow_i.size() && j < glow_v.size(); j++) {
		if (glow_i[j] >= 0 && glow_i[j] < nvox) {
			glow[glow_i[j]] = glow_v[j];
		}
	}
	const Vector3 *v = verts.ptr();
	const int32_t *ix = idx.ptr();
	std::vector<Vector3> norms(nv);
	for (int64_t t = 0; t + 2 < idx.size(); t += 3) {
		const Vector3 a = v[ix[t]];
		const Vector3 fn = (v[ix[t + 2]] - a).cross(v[ix[t + 1]] - a);
		norms[ix[t]] += fn;
		norms[ix[t + 1]] += fn;
		norms[ix[t + 2]] += fn;
	}
	for (int64_t i = 0; i < nv; i++) {
		norms[i] = norms[i].length_squared() > 1e-12 ? norms[i].normalized() : Vector3(0, 1, 0);
	}
	PackedVector3Array v2;
	PackedVector3Array n2;
	PackedColorArray c2;
	PackedInt32Array i2;
	PackedFloat32Array u2;
	u2.resize(nq * 16);
	float *wu = u2.ptrw();
	v2.resize(nq * 4);
	n2.resize(nq * 4);
	c2.resize(nq * 4);
	i2.resize(idx.size());
	Vector3 *wv = v2.ptrw();
	Vector3 *wn = n2.ptrw();
	Color *wc = c2.ptrw();
	int32_t *wi = i2.ptrw();
	for (int64_t qi = 0; qi < nq; qi++) {
		const int32_t vi = qcol[qi];
		Color col(0.5, 0.5, 0.5);
		Color cus(0.5, 0, 0, 0);
		if (vi >= 0 && vi < nvox) {
			col = colors[vi] / grain[vi];
			col.a = 1.0;
			// The voxel boxes' seed (voxel_body.gdshader), from the voxel's index.
			const double sd = std::sin((double)vi * 12.9898 + 4.1414) * 43758.5453;
			cus = Color(kinds[vi] / 16.0, glow[vi].x, glow[vi].y, (float)(sd - std::floor(sd)));
		}
		const int64_t t = qi * 6;
		bool have_f = false;
		Vector3 fnq;
		if (flat) {
			const Vector3 a0 = v[ix[t]];
			fnq = (v[ix[t + 2]] - a0).cross(v[ix[t + 1]] - a0) + (v[ix[t + 5]] - v[ix[t + 3]]).cross(v[ix[t + 4]] - v[ix[t + 3]]);
			fnq = fnq.length_squared() > 1e-12 ? fnq.normalized() : Vector3(0, 1, 0);
			have_f = true;
		}
		int32_t seen[4] = { -1, -1, -1, -1 };
		int used = 0;
		for (int j = 0; j < 6; j++) {
			const int32_t o = ix[t + j];
			int slot = -1;
			for (int s = 0; s < used; s++) {
				if (seen[s] == o) {
					slot = s;
					break;
				}
			}
			if (slot < 0) {
				slot = used < 4 ? used++ : 3;
				seen[slot] = o;
				const int64_t w = qi * 4 + slot;
				wv[w] = v[o];
				wn[w] = have_f ? fnq : norms[o];
				wc[w] = col;
				wu[w * 4] = cus.r;
				wu[w * 4 + 1] = cus.g;
				wu[w * 4 + 2] = cus.b;
				wu[w * 4 + 3] = cus.a;
			}
			wi[t + j] = (int32_t)(qi * 4 + slot);
		}
	}
	res.append(v2);
	res.append(n2);
	res.append(c2);
	res.append(i2);
	res.append(u2);
	return res;
}
