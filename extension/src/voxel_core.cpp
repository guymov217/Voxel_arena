#include "voxel_core.h"

#include <godot_cpp/core/class_db.hpp>

#include <cmath>
#include <cstdint>
#include <vector>

using namespace godot;

void VoxelCore::_bind_methods() {
	ClassDB::bind_method(D_METHOD("greedy_boxes", "w", "h", "d", "solid"), &VoxelCore::greedy_boxes);
	ClassDB::bind_method(D_METHOD("loose_lumps", "cell", "w", "h", "d", "axis", "edge"), &VoxelCore::loose_lumps);
	ClassDB::bind_method(D_METHOD("within", "fx", "fy", "fz", "alive", "grid", "vf", "scale", "p", "r", "limit"), &VoxelCore::within);
	ClassDB::bind_method(D_METHOD("motor_rel", "part", "parent", "rel_q", "wn", "max_t", "dt", "react"), &VoxelCore::motor_rel);
	ClassDB::bind_method(D_METHOD("pd_relative", "part", "parent", "rel_q", "wn", "zeta", "max_t", "dt", "boost", "react"), &VoxelCore::pd_relative);
	ClassDB::bind_method(D_METHOD("pd_axis", "part", "local_axis", "des", "wn", "zeta", "max_t", "dt", "scale", "w_des"), &VoxelCore::pd_axis);
	ClassDB::bind_method(D_METHOD("pd_twist", "part", "ref", "kp", "kd", "max_t", "dt"), &VoxelCore::pd_twist);
	ClassDB::bind_method(D_METHOD("quat_of", "body"), &VoxelCore::quat_of);
	ClassDB::bind_method(D_METHOD("rot_error", "to", "from"), &VoxelCore::rot_error);
	ClassDB::bind_method(D_METHOD("dir_error", "cur", "des"), &VoxelCore::dir_error);
	ClassDB::bind_method(D_METHOD("clamp_len", "v", "mx"), &VoxelCore::clamp_len);
	ClassDB::bind_method(D_METHOD("torque_for", "body", "alpha", "scale"), &VoxelCore::torque_for);
	ClassDB::bind_method(D_METHOD("skin_net", "fx", "fy", "fz", "alive", "grid", "vs", "relax", "relax_k"), &VoxelCore::skin_net);
	ClassDB::bind_method(D_METHOD("skin_crisp", "verts", "idx", "qcol", "colors", "grain", "kinds", "glow_i", "glow_v", "flat"), &VoxelCore::skin_crisp);
	ClassDB::bind_method(D_METHOD("skin_nearest", "fx", "fy", "fz", "alive", "grid", "vf", "scale", "half_ext", "max_depth", "want"), &VoxelCore::skin_nearest);
}

// VoxelPart.local_of, step for step as GDScript does it: the offsets in double, made a float
// vector, then scaled by the part's scale as a float.
namespace {
struct Frame {
	double cx, cy, cz, vf;
	real_t sc;
	Frame(const Vector3i &grid, double vf_, double scale) :
			cx((grid.x - 1) * 0.5), cy((grid.y - 1) * 0.5), cz((grid.z - 1) * 0.5), vf(vf_), sc((real_t)scale) {}
	Vector3 at(int x, int y, int z) const {
		return Vector3((real_t)((x - cx) * vf), (real_t)((y - cy) * vf), (real_t)((z - cz) * vf)) * sc;
	}
};

bool sizes_ok(const PackedInt32Array &fx, const PackedInt32Array &fy, const PackedInt32Array &fz, const PackedByteArray &alive) {
	return fy.size() >= fx.size() && fz.size() >= fx.size() && alive.size() >= fx.size();
}
} // namespace

PackedInt32Array VoxelCore::within(const PackedInt32Array &fx, const PackedInt32Array &fy, const PackedInt32Array &fz, const PackedByteArray &alive, const Vector3i &grid, double vf, double scale, const Vector3 &p, double r, int limit) const {
	PackedInt32Array out;
	if (!sizes_ok(fx, fy, fz, alive)) {
		return out;
	}
	const Frame f(grid, vf, scale);
	const int32_t *x = fx.ptr();
	const int32_t *y = fy.ptr();
	const int32_t *z = fz.ptr();
	const uint8_t *a = alive.ptr();
	const int64_t n = fx.size();
	for (int64_t i = 0; i < n; i++) {
		if (a[i] == 0) {
			continue;
		}
		if ((double)f.at(x[i], y[i], z[i]).distance_to(p) < r) {
			out.push_back((int32_t)i);
			if (limit > 0 && out.size() >= limit) {
				break;
			}
		}
	}
	return out;
}

PackedFloat64Array VoxelCore::skin_nearest(const PackedInt32Array &fx, const PackedInt32Array &fy, const PackedInt32Array &fz, const PackedByteArray &alive, const Vector3i &grid, double vf, double scale, const Vector3 &half_ext, double max_depth, const Vector3 &want) const {
	PackedFloat64Array out;
	out.resize(2);
	out.set(0, -1.0);
	out.set(1, INFINITY);
	if (!sizes_ok(fx, fy, fz, alive)) {
		return out;
	}
	const Frame f(grid, vf, scale);
	const int32_t *x = fx.ptr();
	const int32_t *y = fy.ptr();
	const int32_t *z = fz.ptr();
	const uint8_t *a = alive.ptr();
	const int64_t n = fx.size();
	int64_t best = -1;
	double bd = INFINITY;
	for (int64_t i = 0; i < n; i++) {
		if (a[i] == 0) {
			continue;
		}
		const Vector3 q = f.at(x[i], y[i], z[i]);
		const double depth = std::fmin(std::fmin((double)half_ext.x - std::fabs((double)q.x), (double)half_ext.y - std::fabs((double)q.y)), (double)half_ext.z - std::fabs((double)q.z));
		if (depth > max_depth) {
			continue;
		}
		const double d = (double)q.distance_squared_to(want);
		if (d < bd) {
			bd = d;
			best = i;
		}
	}
	out.set(0, (double)best);
	out.set(1, bd);
	return out;
}

Array VoxelCore::greedy_boxes(int w, int h, int d, const PackedByteArray &solid) const {
	Array out;
	const int n = w * h * d;
	if (w <= 0 || h <= 0 || d <= 0 || solid.size() < n) {
		return out;
	}
	const uint8_t *s = solid.ptr();
	std::vector<uint8_t> used(n, 0);
	auto free_at = [&](int x, int y, int z) {
		const int c = x + w * (y + h * z);
		return s[c] != 0 && used[c] == 0;
	};
	auto row = [&](int x0, int x1, int y, int z) {
		for (int x = x0; x <= x1; x++) {
			if (!free_at(x, y, z)) {
				return false;
			}
		}
		return true;
	};
	for (int z = 0; z < d; z++) {
		for (int y = 0; y < h; y++) {
			for (int x = 0; x < w; x++) {
				if (!free_at(x, y, z)) {
					continue;
				}
				int x1 = x;
				while (x1 + 1 < w && free_at(x1 + 1, y, z)) {
					x1++;
				}
				int y1 = y;
				while (y1 + 1 < h && row(x, x1, y1 + 1, z)) {
					y1++;
				}
				int z1 = z;
				while (z1 + 1 < d) {
					bool ok = true;
					for (int yy = y; yy <= y1 && ok; yy++) {
						ok = row(x, x1, yy, z1 + 1);
					}
					if (!ok) {
						break;
					}
					z1++;
				}
				for (int cz = z; cz <= z1; cz++) {
					for (int cy = y; cy <= y1; cy++) {
						for (int cx = x; cx <= x1; cx++) {
							used[cx + w * (cy + h * cz)] = 1;
						}
					}
				}
				Array b;
				b.append(x);
				b.append(y);
				b.append(z);
				b.append(x1);
				b.append(y1);
				b.append(z1);
				out.append(b);
			}
		}
	}
	return out;
}

namespace {

// Breadth-first fill over face neighbours from the queued cells, tagging them; returns the voxels.
PackedInt32Array fill(const int32_t *cl, std::vector<int> &mk, std::vector<int32_t> &q, int tag, int w, int h, int d) {
	PackedInt32Array out;
	const int sx = h * d;
	const int sy = d;
	size_t head = 0;
	while (head < q.size()) {
		const int c = q[head++];
		out.append(cl[c] - 1);
		const int x = c / sx;
		const int y = (c % sx) / sy;
		const int z = c % sy;
		const int nb[6] = { x > 0 ? c - sx : -1, x < w - 1 ? c + sx : -1, y > 0 ? c - sy : -1, y < h - 1 ? c + sy : -1, z > 0 ? c - 1 : -1, z < d - 1 ? c + 1 : -1 };
		for (int k = 0; k < 6; k++) {
			const int m = nb[k];
			if (m >= 0 && cl[m] != 0 && mk[m] == 0) {
				mk[m] = tag;
				q.push_back(m);
			}
		}
	}
	q.clear();
	return out;
}

} // namespace

Array VoxelCore::loose_lumps(const PackedInt32Array &cell, int w, int h, int d, int axis, int edge) const {
	Array lumps;
	const int n = w * h * d;
	if (w <= 0 || h <= 0 || d <= 0 || cell.size() < n) {
		return lumps;
	}
	const int32_t *cl = cell.ptr();
	std::vector<int> mk(n, 0);
	std::vector<int32_t> q;
	q.reserve(256);
	int count = 0;
	for (int c = 0; c < n; c++) {
		count += cl[c] != 0;
	}
	if (count == 0) {
		return lumps;
	}
	int64_t held = 0;
	if (axis >= 0 && axis <= 2) {
		for (int c = 0; c < n; c++) {
			if (cl[c] == 0) {
				continue;
			}
			const int k = axis == 0 ? c / (h * d) : (axis == 1 ? (c % (h * d)) / d : c % d);
			if (k - edge <= 1 && edge - k <= 1) {
				mk[c] = 1;
				q.push_back(c);
			}
		}
		held = fill(cl, mk, q, 1, w, h, d).size();
	} else {
		int best = -1;
		int64_t best_size = 0;
		int tag = 2;
		for (int c = 0; c < n; c++) {
			if (cl[c] == 0 || mk[c] != 0) {
				continue;
			}
			mk[c] = tag;
			q.push_back(c);
			const int64_t sz = fill(cl, mk, q, tag, w, h, d).size();
			if (sz > best_size) {
				best_size = sz;
				best = tag;
			}
			tag++;
		}
		for (int c = 0; c < n; c++) {
			mk[c] = mk[c] == best ? 1 : 0;
		}
		held = best_size;
	}
	if (held == count) {
		return lumps;
	}
	for (int c = 0; c < n; c++) {
		if (cl[c] != 0 && mk[c] == 0) {
			mk[c] = 3;
			q.push_back(c);
			lumps.append(fill(cl, mk, q, 3, w, h, d));
		}
	}
	return lumps;
}
