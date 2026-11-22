// A man's arms kept out of his trunk as it is drawn (Fighter._out_of_trunk, _elbow_off_trunk,
// _hand_off_trunk): the same results as the GDScript, bit for bit. Asked a dozen times an arm
// every step of a fight, in the script they were a tenth of the step. As in drive.cpp, each line
// does what the script's line does, in the same types and order: scalars in double, vectors in
// float, a vector times a scalar taking the scalar as a float.

#include "voxel_core.h"
#include "sculpt_common.h"

#include <godot_cpp/variant/basis.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/transform3d.hpp>
#include <godot_cpp/variant/variant.hpp>

#include <cmath>

using namespace godot;
using namespace vc;


Vector3 VoxelCore::sculpt_out(const Dictionary &o, const Vector3 &l, double limb_r, double band_lo, double band_hi, double band_pad) const {
	const Sculpt s = read_sculpt(o);
	if (!s.ok) {
		return Vector3();
	}
	return out_of_trunk(s, l, limb_r + plate_pad((double)l.y, band_lo, band_hi, band_pad));
}

Vector3 VoxelCore::sculpt_elbow(const Dictionary &o, const Transform3D &bt, const Transform3D &bi, const Vector3 &shoulder_w, const Vector3 &e_dir, double lu, double r_half, double r_three, double r_whole, double band_lo, double band_hi, double band_pad) const {
	const Sculpt s = read_sculpt(o);
	if (!s.ok) {
		return e_dir;
	}
	return elbow_loop(s, bt, bi, shoulder_w, e_dir, lu, r_half, r_three, r_whole, band_lo, band_hi, band_pad);
}

Vector3 VoxelCore::sculpt_hand(const Dictionary &o, const Transform3D &bt, const Transform3D &bi, const Vector3 &from, const Vector3 &goal, double size, const PackedFloat64Array &marks, double band_lo, double band_hi, double band_pad) const {
	const Sculpt s = read_sculpt(o);
	if (!s.ok) {
		return goal;
	}
	return hand_loop(s, bt, bi, from, goal, size, marks.ptr(), marks.size() / 2, band_lo, band_hi, band_pad);
}
