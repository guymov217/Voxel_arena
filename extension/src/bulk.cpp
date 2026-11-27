// What the game asks of every body in one go, a call for the lot: a snapshot's rows of the parts' places (Match.pack_parts) and the velocities the combat
// keeps of every body before a step (Combat.record_velocities). To the byte and the bit what the scripts' own lines write (tests/test_native.gd).
#include "voxel_core.h"
#include "engine_math.h"

#include <cmath>
#include <godot_cpp/classes/node3d.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

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

namespace {
// The names of what Combat.record_velocities reads of a fighter and a weapon, kept for good (a name made at the start and let go at the end of the library's life is an engine call too late).
struct VelKeys {
	StringName parts, weapons, chain_head;
	VelKeys() :
			parts("parts"), weapons("weapons"), chain_head("chain_head") {}
};
const VelKeys &vel_keys() {
	static const VelKeys *k = new VelKeys();
	return *k;
}

// Whether the variant holds an object that is still there (the script's is_instance_valid).
bool vel_valid(const Variant &v) {
	if (v.get_type() != Variant::OBJECT) {
		return false;
	}
	const ObjectID oid = v;
	const uint64_t id = oid;
	return id != 0 && UtilityFunctions::is_instance_id_valid((int64_t)id);
}

void vel_record(Dictionary &vel, const Variant &v) {
	if (!vel_valid(v)) {
		return;
	}
	RigidBody3D *b = Object::cast_to<RigidBody3D>(v);
	if (b == nullptr) {
		return;
	}
	Array a;
	a.push_back(b->get_linear_velocity());
	a.push_back(b->get_angular_velocity());
	vel[(int64_t)b->get_instance_id()] = a;
}

// A weapon and, if it has one, its chain head: the bodies Combat.record_velocities takes of it.
void vel_weapon(Dictionary &vel, const Variant &w) {
	if (!vel_valid(w)) {
		return;
	}
	Object *o = w;
	if (o == nullptr) {
		return;
	}
	vel_record(vel, w);
	const Variant ch = o->get(vel_keys().chain_head);
	if (vel_valid(ch)) {
		vel_record(vel, ch);
	}
}
} // namespace

void VoxelCore::record_vel_all(const Array &fighters, const Array &loose, Dictionary vel) const {
	const VelKeys &k = vel_keys();
	const int64_t nf = fighters.size();
	for (int64_t i = 0; i < nf; i++) {
		const Variant fv = fighters[i];
		if (!vel_valid(fv)) {
			continue;
		}
		Object *f = fv;
		const Array parts = f->get(k.parts);
		const int64_t np = parts.size();
		for (int64_t j = 0; j < np; j++) {
			vel_record(vel, parts[j]);
		}
		const Dictionary weapons = f->get(k.weapons);
		const Array ws = weapons.values();
		const int64_t nw = ws.size();
		for (int64_t j = 0; j < nw; j++) {
			vel_weapon(vel, ws[j]);
		}
	}
	const int64_t nl = loose.size();
	for (int64_t i = 0; i < nl; i++) {
		vel_weapon(vel, loose[i]);
	}
}
