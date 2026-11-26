// What the game asks of every body in one go, a call for the lot: a snapshot's rows of the parts' places (Match.pack_parts) and the velocities the combat
// keeps of every body before a step (Combat.record_velocities). To the byte and the bit what the scripts' own lines write (tests/test_native.gd).
#include "voxel_core.h"
#include "engine_math.h"

#include <cmath>
#include <godot_cpp/classes/node3d.hpp>

using namespace godot;

static inline void bulk_s16(uint8_t *w, int64_t v) {
	uint16_t u = (uint16_t)(int16_t)v;
	w[0] = (uint8_t)(u & 0xff);
	w[1] = (uint8_t)(u >> 8);
}

static inline int64_t bulk_place(real_t x) {
	// clampi(roundi(x * POS_Q), -32767, 32767), POS_Q 512: the float widened, the product and the rounding in doubles, as the script's
	int64_t v = (int64_t)::round((double)x * 512.0);
	return v < -32767 ? -32767 : (v > 32767 ? 32767 : v);
}

// Match.pack_parts: fourteen bytes a part (Match.pack_xf: its place in three int16 of 1/512 m, its turn in four of 1/32767).
PackedByteArray VoxelCore::pack_parts(const Array &parts) const {
	PackedByteArray b;
	const int n = (int)parts.size();
	b.resize(n * 14);
	uint8_t *w = b.ptrw();
	for (int i = 0; i < n; i++) {
		Node3D *nd = Object::cast_to<Node3D>(parts[i]);
		uint8_t *o = w + i * 14;
		if (nd == nullptr) {
			for (int k = 0; k < 14; k++) {
				o[k] = 0;
			}
			continue;
		}
		const Transform3D t = nd->get_global_transform();
		const Quaternion q = vc::eng_rotation_quaternion(t.basis);
		bulk_s16(o, bulk_place(t.origin.x));
		bulk_s16(o + 2, bulk_place(t.origin.y));
		bulk_s16(o + 4, bulk_place(t.origin.z));
		bulk_s16(o + 6, (int64_t)::round((double)q.x * 32767.0));
		bulk_s16(o + 8, (int64_t)::round((double)q.y * 32767.0));
		bulk_s16(o + 10, (int64_t)::round((double)q.z * 32767.0));
		bulk_s16(o + 12, (int64_t)::round((double)q.w * 32767.0));
	}
	return b;
}

// Combat.record_velocities: vel[its id] = [how fast it goes, how fast it turns] for each body of the list, in the list's order.
void VoxelCore::record_vel(const Array &bodies, Dictionary vel) const {
	const int n = (int)bodies.size();
	for (int i = 0; i < n; i++) {
		RigidBody3D *b = Object::cast_to<RigidBody3D>(bodies[i]);
		if (b == nullptr) {
			continue;
		}
		Array a;
		a.push_back(b->get_linear_velocity());
		a.push_back(b->get_angular_velocity());
		vel[(int64_t)b->get_instance_id()] = a;
	}
}
