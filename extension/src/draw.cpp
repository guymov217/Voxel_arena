// A man's drawing work that was done voxel by voxel in the script every frame he moved (user: the
// frame rate drops sharply in a fight): which fine voxels of a cuirass's shoulder guard lie under
// his arm's armour (Fighter._clip_shoulder_guards: _in_reach on each, then _cut_off), and where
// the cells of his wounds are drawn on a limb bent at a break (FineBody.lay). As the script does
// them; drawing only, nothing here is read back by the game.

#include "voxel_core.h"

#include <godot_cpp/variant/basis.hpp>
#include <godot_cpp/variant/transform3d.hpp>
#include <godot_cpp/variant/vector2.hpp>

#include <cmath>
#include <vector>

using namespace godot;

namespace {

const double DR_PI = 3.1415926535897932384626433833;
const double DR_TAU = 6.2831853071795864769252867666;

int64_t dr_posmod(int64_t a, int64_t b) {
	int64_t m = a % b;
	return m < 0 ? m + b : m;
}

// VoxelPart._arc_at (as bend.cpp has it).
Vector3 dr_arc_at(real_t s, real_t b, const Vector3 &n, real_t theta, const Vector3 &tip, const Vector3 &pv) {
	if (theta < 1e-4) {
		return pv + tip * s;
	}
	const real_t ph = theta * s / b;
	return pv + (tip * std::sin(ph) + n.cross(tip) * (1.0 - std::cos(ph)) + n * n.dot(tip) * (ph - std::sin(ph))) * (b / theta);
}

struct DrLayer {
	real_t s;
	Basis rs;    // the layer's turn
	Vector3 a;   // its place on the arc
};

} // namespace

// Fighter._clip_shoulder_guards' first mask for one guard: `pts` its fine voxels (the trunk's
// frame), `to_arm` into the arm's; `reach` the arm's armour (Fighter._arm_reach: `rows` rows of
// `na` ways round, from `y0`, `dy` a row); 1 where a voxel lies within the reach and `pad`
// (Fighter._in_reach).
PackedByteArray VoxelCore::guard_reach(const PackedVector3Array &pts, const Transform3D &to_arm, const PackedFloat32Array &reach, int rows, int na, double y0, double dy, double pad) const {
	const int64_t count = pts.size();
	PackedByteArray hide;
	hide.resize(count);
	uint8_t *h = hide.ptrw();
	const Vector3 *p = pts.ptr();
	const float *r = reach.ptr();
	const bool has_reach = rows > 0 && na > 0 && reach.size() >= (int64_t)rows * na;
	// (The furthest the armour reaches anywhere: a voxel further out than that and `pad` is in
	// no row's reach, whatever way round it lies.)
	double far_all = 0.0;
	if (has_reach) {
		for (int64_t i = 0; i < (int64_t)rows * na; i++) {
			far_all = r[i] > far_all ? r[i] : far_all;
		}
	}
	for (int64_t k = 0; k < count; k++) {
		h[k] = 0;
		if (!has_reach) {
			continue;
		}
		const Vector3 q = to_arm.xform(p[k]);
		const double fr = ((double)q.y - y0) / dy;
		if (fr < -0.5 || fr > (double)rows - 0.5) {
			continue;
		}
		const double len = (double)Vector2(q.x, q.z).length();
		if (!(len < far_all + pad)) {
			continue;
		}
		int64_t ri = (int64_t)std::floor(fr);
		ri = ri < 0 ? 0 : (ri > rows - 1 ? rows - 1 : ri);
		const int64_t ai = dr_posmod((int64_t)std::floor((std::atan2((double)q.z, (double)q.x) + DR_PI) / DR_TAU * (double)na), na);
		double far = 0.0;
		for (int64_t d_r = -1; d_r <= 1; d_r++) {
			const int64_t rr = ri + d_r;
			if (rr < 0 || rr >= rows) {
				continue;
			}
			for (int64_t d_a = -1; d_a <= 1; d_a++) {
				const double v = r[rr * na + dr_posmod(ai + d_a, na)];
				far = v > far ? v : far;
			}
		}
		if (far > 0.0 && len < far + pad) {
			h[k] = 1;
		}
	}
	return hide;
}

// Fighter._cut_off: `hide` and every voxel the hidden ones cut off from the rest of the shell
// (`adj` every voxel's neighbours on end, `adj_at` where each one's begin, `anc` those the rest
// of the shell holds).
PackedByteArray VoxelCore::guard_cut(const PackedByteArray &hide_in, const PackedInt32Array &adj, const PackedInt32Array &adj_at, const PackedByteArray &anc) const {
	PackedByteArray hide = hide_in;
	const int64_t count = hide.size();
	if (adj_at.size() < count + 1 || anc.size() < count) {
		return hide;
	}
	uint8_t *h = hide.ptrw();
	const int32_t *at = adj_at.ptr();
	const int32_t *nb = adj.ptr();
	const uint8_t *an = anc.ptr();
	const int64_t n_adj = adj.size();
	std::vector<uint8_t> seen(count, 0);
	std::vector<int32_t> todo;
	todo.reserve(count);
	for (int64_t k = 0; k < count; k++) {
		if (h[k] == 0 && an[k] == 1) {
			seen[k] = 1;
			todo.push_back((int32_t)k);
		}
	}
	for (size_t i = 0; i < todo.size(); i++) {
		const int32_t k = todo[i];
		for (int64_t e = at[k]; e < at[k + 1] && e < n_adj; e++) {
			const int32_t j = nb[e];
			if (j >= 0 && j < count && h[j] == 0 && seen[j] == 0) {
				seen[j] = 1;
				todo.push_back(j);
			}
		}
	}
	for (int64_t k = 0; k < count; k++) {
		if (h[k] == 0 && seen[k] == 0) {
			h[k] = 1;
		}
	}
	return hide;
}

// Where two masks of a length differ (the places, in order): what a new mask changes of the old.
PackedInt32Array VoxelCore::bytes_changed(const PackedByteArray &was, const PackedByteArray &now) const {
	PackedInt32Array out;
	const int64_t count = now.size();
	if (was.size() != count) {
		out.resize(count);
		int32_t *o = out.ptrw();
		for (int64_t k = 0; k < count; k++) {
			o[k] = (int32_t)k;
		}
		return out;
	}
	const uint8_t *a = was.ptr();
	const uint8_t *b = now.ptr();
	for (int64_t k = 0; k < count; k++) {
		if (a[k] != b[k]) {
			out.push_back((int32_t)k);
		}
	}
	return out;
}

// What is drawn on the voxels of a limb bent at a break, each set on `multimesh` where the bend
// has its voxel (VoxelPart._bent of the voxel's middle, then its own place on it). `rows`: 15
// floats each, its place unbent as a MultiMesh holds it (the basis by rows, each with its origin
// after it) and the middle of its voxel; `slots`: where each is in the mesh. `q`, `n`, `theta`,
// `b`, `k`, `axis`, `pv`, `tip`: the bend (VoxelPart._bend_geom); `far_x`: the piece past the
// bend as it is drawn (VoxelPart._bend_x). One before the break is left as it is.
void VoxelCore::lay_cells(Object *multimesh, const PackedFloat32Array &rows, const PackedInt32Array &slots, const Quaternion &q, const Vector3 &n, double theta, double b, double k, int axis, const Vector3 &pv, const Vector3 &tip, const Transform3D &far_x) const {
	const int64_t count = slots.size();
	if (multimesh == nullptr || rows.size() < count * 15 || axis < 0 || axis > 2) {
		return;
	}
	static const StringName set_xf("set_instance_transform");
	const float *r = rows.ptr();
	const int32_t *sl = slots.ptr();
	std::vector<DrLayer> layers;
	for (int64_t row = 0; row < count; row++) {
		const float *f = r + row * 15;
		const Basis tb(f[0], f[1], f[2], f[4], f[5], f[6], f[8], f[9], f[10]);
		const Vector3 to(f[3], f[7], f[11]);
		const Vector3 lp(f[12], f[13], f[14]);
		const real_t s = (lp - pv).dot(tip);
		if (s <= 0.0) {
			continue;
		}
		Basis xb;
		Vector3 xo;
		if (s >= b) {
			// Past the bend: turned whole with the far piece.
			xb = far_x.basis * tb;
			xo = far_x.xform(to);
		} else {
			const DrLayer *lay = nullptr;
			for (const DrLayer &l : layers) {
				if (l.s == s) {
					lay = &l;
					break;
				}
			}
			if (lay == nullptr) {
				DrLayer l;
				l.s = s;
				l.rs = Basis(Quaternion().slerp(q, s / b));
				l.a = dr_arc_at(s, b, n, theta, tip, pv);
				layers.push_back(l);
				lay = &layers.back();
			}
			const Vector3 off = lp - pv - tip * s;
			real_t sc = 1.0 + k * n.dot(off.cross(tip));
			sc = sc < 0.35 ? 0.35 : (sc > 2.6 ? 2.6 : sc);
			Basis m = lay->rs;
			m.set_column(axis, m.get_column(axis) * sc);
			// The voxel's bend: its middle set on the arc, turned and stretched with its layer.
			const Vector3 bo = m.xform(-lp) + (lay->a + lay->rs.xform(off));
			xb = m * tb;
			xo = m.xform(to) + bo;
		}
		multimesh->call(set_xf, sl[row], Transform3D(xb, xo));
	}
}
