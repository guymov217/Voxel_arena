// VoxelPart._lay_bend's voxels in C++: a limb bent at a break, the voxels over the break laid
// round the bend, each turned its share and stretched along the bone on the outside of the bend
// (VoxelPart._bent_layer), each set on the MultiMesh in turn. Drawing only: nothing here is read
// back by the game.

#include "voxel_core.h"

#include <godot_cpp/variant/basis.hpp>
#include <godot_cpp/variant/transform3d.hpp>

#include <cmath>
#include <vector>

using namespace godot;

namespace {

// VoxelPart._arc_at: the bone's line turned round in an arc, `s` of `b` along it.
Vector3 arc_at(real_t s, real_t b, const Vector3 &n, real_t theta, const Vector3 &tip, const Vector3 &pv) {
	if (theta < 1e-4) {
		return pv + tip * s;
	}
	const real_t ph = theta * s / b;
	return pv + (tip * std::sin(ph) + n.cross(tip) * (1.0 - std::cos(ph)) + n * n.dot(tip) * (ph - std::sin(ph))) * (b / theta);
}

struct Layer {
	real_t s;
	Basis m;     // inv.basis * the layer's turn
	Vector3 a;   // inv * the layer's place on the arc
	Basis rs;    // the layer's turn
};

} // namespace

void VoxelCore::lay_band(Object *multimesh, const PackedFloat32Array &rows, const PackedInt32Array &ix, const PackedByteArray &alive, const PackedByteArray &veil, const Quaternion &q, const Vector3 &n, double theta, double b, double b_was, double k, int axis, const Vector3 &pv, const Vector3 &tip, const Transform3D &inv) const {
	const int64_t count = ix.size() / 2;
	if (multimesh == nullptr || rows.size() < count * 19 || axis < 0 || axis > 2) {
		return;
	}
	static const StringName set_xf("set_instance_transform");
	const float *r = rows.ptr();
	const int32_t *x = ix.ptr();
	const uint8_t *al = alive.ptr();
	const int64_t n_alive = alive.size();
	const uint8_t *vl = veil.ptr();
	const int64_t n_veil = veil.size();
	std::vector<Layer> layers;
	for (int64_t row = 0; row < count; row++) {
		const int32_t slot = x[row * 2];
		const int32_t i = x[row * 2 + 1];
		if (i < 0 || i >= n_alive || al[i] == 0 || (i < n_veil && vl[i] == 1)) {
			continue;
		}
		const float *f = r + row * 19;
		// The voxel's place unbent: the basis by rows, then the origin.
		const Basis base_b(f[0], f[1], f[2], f[4], f[5], f[6], f[8], f[9], f[10]);
		const Vector3 base_o(f[3], f[7], f[11]);
		const real_t s = f[12];
		const Vector3 off(f[13], f[14], f[15]);
		const Vector3 cr(f[16], f[17], f[18]);
		Basis xb;
		Vector3 xo;
		if (s >= b) {
			// Past the bend: its own place in the far piece's mesh (set already, unless the bend
			// reached it the last time it was laid out).
			if (s >= b_was) {
				continue;
			}
			xb = base_b;
			xo = base_o;
		} else {
			const Layer *lay = nullptr;
			for (const Layer &l : layers) {
				if (l.s == s) {
					lay = &l;
					break;
				}
			}
			if (lay == nullptr) {
				Layer l;
				l.s = s;
				l.rs = Basis(Quaternion().slerp(q, s / b));
				l.m = inv.basis * l.rs;
				l.a = inv.xform(arc_at(s, b, n, theta, tip, pv));
				layers.push_back(l);
				lay = &layers.back();
			}
			real_t sc = 1.0 + k * n.dot(cr);
			sc = sc < 0.35 ? 0.35 : (sc > 2.6 ? 2.6 : sc);
			Basis m = lay->m;
			// (m * scale(sc on `axis`)): the column of that axis stretched.
			m.set_column(axis, m.get_column(axis) * sc);
			xb = m * base_b;
			xo = lay->a + lay->m.xform(off);
		}
		multimesh->call(set_xf, slot, Transform3D(xb, xo));
	}
}
