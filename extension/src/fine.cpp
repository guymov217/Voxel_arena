// What a blow changes of a man's fine look (FineBody), done fine voxel by fine voxel in the script
// in the step the blow landed: the fine voxels over the voxels it knocked out put away and the
// wound's cells bared (shown, _write_wound), the blood soaked into the skin round it and into the
// wound (colored, _write_wound_glow), and the piece cut off drawn of his own cells (taken). A
// blow that took a few hundred voxels was tens of milliseconds of this (user: the frame rate
// drops in a fight). As the script does them, number for number; drawing only.

#include "voxel_core.h"

#include <godot_cpp/classes/multi_mesh.hpp>
#include <godot_cpp/variant/basis.hpp>
#include <godot_cpp/variant/color.hpp>
#include <godot_cpp/variant/packed_color_array.hpp>
#include <godot_cpp/variant/transform3d.hpp>
#include <godot_cpp/variant/variant.hpp>
#include <godot_cpp/variant/vector2.hpp>
#include <godot_cpp/variant/vector2i.hpp>

#include <cmath>
#include <cstring>
#include <vector>

using namespace godot;

namespace {

const int FN_CELL = 9;                 // FineBody.CELL
const int64_t FN_OWN_COLOUR = 1 << 30; // FineBody.OWN_COLOUR
const double FN_PI = 3.1415926535897932384626433833;
const double FN_TAU = 6.2831853071795864769252867666;

// FineBody's and VoxelPart's colours and numbers.
const Color FN_FAT(0.92, 0.72, 0.46);
const Color FN_MUSCLE(0.72, 0.08, 0.065);
const Color FN_FRESH(0.78, 0.04, 0.035);
const Color FN_CLOT(0.36, 0.015, 0.02);
const Color FN_BONE(0.93, 0.89, 0.8);
const Color FN_BLOOD(0.6, 0.04, 0.035);
const Color FN_SMEAR(0.306, 0.039, 0.039); // VoxelPart.SMEAR
const double FN_SKIN_K = 0.86;
const double FN_WET[4] = { 0.0, 0.55, 0.7, 0.9 };
const double FN_WET_BONE = 0.45;
const double FN_WET_SMEAR = 0.6;

// The faces in the order of VoxelPart.AO_FACES: +x -x +y -y +z -z.
const int FN_FACES[6][3] = { { 1, 0, 0 }, { -1, 0, 0 }, { 0, 1, 0 }, { 0, -1, 0 }, { 0, 0, 1 }, { 0, 0, -1 } };

int64_t fn_posmod(int64_t a, int64_t b) {
	int64_t m = a % b;
	return m < 0 ? m + b : m;
}

double fn_clamp(double v, double lo, double hi) {
	return v < lo ? lo : (v > hi ? hi : v);
}

// FineBody._toward: how far colour `b` has gone from `a` toward `t`.
double fn_toward(const Color &a, const Color &b, const Color &t) {
	const Vector3 d((real_t)((double)t.r - (double)a.r), (real_t)((double)t.g - (double)a.g), (real_t)((double)t.b - (double)a.b));
	const Vector3 m((real_t)((double)b.r - (double)a.r), (real_t)((double)b.g - (double)a.g), (real_t)((double)b.b - (double)a.b));
	const real_t l2 = d.length_squared();
	if (!((double)l2 > 0.0001)) {
		return 0.0;
	}
	return fn_clamp((double)m.dot(d) / (double)l2, 0.0, 1.0);
}

// FineBody._near.
bool fn_near(const Color &a, const Color &b) {
	return std::fabs((double)a.r - (double)b.r) + std::fabs((double)a.g - (double)b.g) + std::fabs((double)a.b - (double)b.b) < 0.03;
}

// VoxelPart.kind_data(k, ao, 0).
Color fn_kind_data(int64_t k, int64_t ao) {
	return Color((float)((double)k / 16.0), 0.0f, 0.0f, (float)(1.0 + (double)ao));
}

// A place as a MultiMesh holds it (FineBody.put_cell's first twelve).
void fn_put_xf(float *o, const Transform3D &t) {
	const Basis &b = t.basis;
	o[0] = b.rows[0][0];
	o[1] = b.rows[0][1];
	o[2] = b.rows[0][2];
	o[3] = t.origin.x;
	o[4] = b.rows[1][0];
	o[5] = b.rows[1][1];
	o[6] = b.rows[1][2];
	o[7] = t.origin.y;
	o[8] = b.rows[2][0];
	o[9] = b.rows[2][1];
	o[10] = b.rows[2][2];
	o[11] = t.origin.z;
}

void fn_put_col(float *o, const Color &c) {
	o[0] = c.r;
	o[1] = c.g;
	o[2] = c.b;
	o[3] = c.a;
}

// A part and its fine look, read once a call.
struct FinePart {
	bool ok = false;
	Dictionary fine;
	PackedColorArray colors;
	PackedByteArray kinds, alive, organ, hid;
	Dictionary glowing, scarred;
	PackedInt32Array fx, fy, fz, cellmap;
	Vector3i grid;
	double vox = 0.0; // p.vf * p.part_scale
	PackedInt32Array par, cells, code, jaw_cell, far_slot;
	PackedColorArray own;
	PackedFloat32Array shade, na, kt;
	Array xf, palette, cloth;
	Dictionary of, base, wound;
	double fsz = 0.0;
	Color sk;
	bool beast = false;
	bool has_k = false;
	int64_t k_rows = 0, k_na = 0;
	MultiMesh *mm = nullptr;
	MultiMesh *far_mm = nullptr;
	MultiMesh *jaw_mm = nullptr;
	MultiMesh *wmm = nullptr;
	Vector3 jaw_off;
	int res = 2, margin = 10;
	int64_t n = 0;

	static MultiMesh *mesh_of(const Dictionary &f, const char *key) {
		const Variant v = f.get(key, Variant());
		if (v.get_type() != Variant::OBJECT) {
			return nullptr;
		}
		return Object::cast_to<MultiMesh>((Object *)v);
	}

	FinePart(Object *p, int p_res, int p_margin) {
		if (p == nullptr) {
			return;
		}
		const Variant fv = p->get("fine");
		if (fv.get_type() != Variant::DICTIONARY) {
			return;
		}
		fine = fv;
		if (!fine.has("of") || !fine.has("par") || !fine.has("code")) {
			return;
		}
		colors = p->get("colors");
		kinds = p->get("kinds");
		alive = p->get("alive");
		organ = p->get("organ");
		glowing = p->get("glowing");
		scarred = p->get("scarred");
		fx = p->get("fx");
		fy = p->get("fy");
		fz = p->get("fz");
		cellmap = p->get("cellmap");
		grid = p->get("grid");
		vox = (double)p->get("vf") * (double)p->get("part_scale");
		n = fx.size();
		par = fine["par"];
		cells = fine.get("cells", PackedInt32Array());
		code = fine["code"];
		hid = fine.get("hid", PackedByteArray());
		own = fine.get("own", PackedColorArray());
		shade = fine.get("shade", PackedFloat32Array());
		na = fine.get("na", PackedFloat32Array());
		xf = fine.get("xf", Array());
		of = fine["of"];
		base = fine.get("base", Dictionary());
		wound = fine.get("wound", Dictionary());
		fsz = fine.get("fsz", 0.0);
		sk = fine.get("sk", Color());
		beast = fine.get("beast", false);
		jaw_cell = fine.get("jaw_cell", PackedInt32Array());
		far_slot = fine.get("far_slot", PackedInt32Array());
		jaw_off = fine.get("jaw_off", Vector3());
		const Dictionary d = fine.get("d", Dictionary());
		palette = d.get("palette", Array());
		cloth = d.get("cloth", Array());
		has_k = d.has("k");
		if (has_k) {
			kt = d["k"];
			k_rows = d.get("rows", 0);
			k_na = d.get("na", 0);
			if (k_rows <= 0 || k_na <= 0 || kt.size() < k_rows * k_na) {
				return;
			}
		}
		mm = mesh_of(fine, "mm");
		far_mm = mesh_of(fine, "far_mm");
		jaw_mm = mesh_of(fine, "jaw_mm");
		wmm = mesh_of(fine, "wmm");
		res = p_res;
		margin = p_margin;
		ok = fy.size() >= n && fz.size() >= n && alive.size() >= n && kinds.size() >= n && colors.size() >= n && code.size() >= n && cellmap.size() >= (int64_t)grid.x * grid.y * grid.z && own.size() >= par.size() && shade.size() >= par.size() && cells.size() >= par.size() * FN_CELL && xf.size() >= par.size();
	}

	// VoxelPart._cell.
	int64_t cell(int64_t x, int64_t y, int64_t z) const {
		if (x < 0 || y < 0 || z < 0 || x >= grid.x || y >= grid.y || z >= grid.z) {
			return -1;
		}
		return (int64_t)cellmap[(x * grid.y + y) * grid.z + z] - 1;
	}

	// VoxelPart.local_of (as voxel_core.cpp's Frame has it).
	Vector3 local_of(int64_t i, double vf, real_t sc) const {
		const double cx = (grid.x - 1) * 0.5, cy = (grid.y - 1) * 0.5, cz = (grid.z - 1) * 0.5;
		return Vector3((real_t)((fx[i] - cx) * vf), (real_t)((fy[i] - cy) * vf), (real_t)((fz[i] - cz) * vf)) * sc;
	}

	// FineBody._slot: the drawing fine voxel `s` is on (0 his own, 1 the far piece of a limb bent
	// at a break, 2 his jaw) and its slot there.
	MultiMesh *slot_of(int64_t s, int64_t &slot, int &which) const {
		if (jaw_cell.size() > s && jaw_cell[s] >= 0) {
			slot = jaw_cell[s];
			which = 2;
			return jaw_mm;
		}
		if (far_slot.size() > s && far_slot[s] >= 0) {
			slot = far_slot[s];
			which = 1;
			return far_mm;
		}
		slot = s;
		which = 0;
		return mm;
	}

	// FineBody.k_at.
	double k_at(const Vector3 &q) const {
		if (!has_k) {
			return 1.0;
		}
		const double f = vox / (double)res;
		const double ylo = -(double)grid.y * vox * 0.5 - (double)margin * f;
		const double fr = fn_clamp(((double)q.y - ylo) / f - 0.5, 0.0, (double)(k_rows - 1));
		const int64_t r0 = (int64_t)std::floor(fr);
		const int64_t r1 = r0 + 1 < k_rows - 1 ? r0 + 1 : k_rows - 1;
		const double wr = fr - (double)r0;
		const double fa = (std::atan2((double)q.z, (double)q.x) + FN_PI) / FN_TAU * (double)k_na - 0.5;
		const double a0f = std::floor(fa);
		const double wa = fa - a0f;
		const int64_t a0 = fn_posmod((int64_t)a0f, k_na);
		const int64_t a1 = (a0 + 1) % k_na;
		const float *k = kt.ptr();
		const double k0 = (double)k[r0 * k_na + a0] * (1.0 - wa) + (double)k[r0 * k_na + a1] * wa;
		const double k1 = (double)k[r1 * k_na + a0] * (1.0 - wa) + (double)k[r1 * k_na + a1] * wa;
		return k0 * (1.0 - wr) + k1 * wr;
	}

	// FineBody.mapped.
	Transform3D mapped(const Vector3 &q, double size) const {
		const double k = k_at(q);
		const Vector3 sc = Vector3((real_t)k, (real_t)1.0, (real_t)k) * (real_t)size;
		return Transform3D(Basis::from_scale(sc), Vector3((real_t)((double)q.x * k), q.y, (real_t)((double)q.z * k)));
	}

	// FineBody._color of fine voxel `s` over voxel `j` (j >= 0).
	Color skin_color(int64_t s, int64_t j) const {
		const Variant bv = base.get(j, Variant());
		if (bv.get_type() == Variant::COLOR) {
			const Color b0 = bv;
			const Color cj = colors[j];
			if (cj != b0) {
				const double k = (double)shade[s];
				const double t = fn_toward(b0, cj, FN_SMEAR);
				if (t > 0.0 && fn_near(b0.lerp(FN_SMEAR, (float)t), cj)) {
					const Color bl = FN_BLOOD.srgb_to_linear();
					return own[s].lerp(Color((float)((double)bl.r * k), (float)((double)bl.g * k), (float)((double)bl.b * k)).linear_to_srgb(), (float)t);
				}
				const Color c = cj.srgb_to_linear();
				return Color((float)((double)c.r * k), (float)((double)c.g * k), (float)((double)c.b * k)).linear_to_srgb();
			}
		}
		return own[s];
	}

	// FineBody._custom of fine voxel `s` over voxel `j` (j >= 0), glowing `g`.
	Color skin_custom(int64_t s, int64_t j, const Vector2 &g) const {
		int64_t k = kinds[j];
		const int64_t paint = cells[s * FN_CELL + 8];
		if (paint & FN_OWN_COLOUR) {
			k = (paint >> 24) & 63;
		} else if (paint > 0 && paint <= palette.size()) {
			const Array e = palette[paint - 1];
			k = (int64_t)e[3];
		} else if (k == 1 && cloth.size() >= 4) {
			k = (int64_t)cloth[3];
		} else if (!beast && k >= 6) {
			k = 0;
		}
		Color c = fn_kind_data(k == 1 ? 0 : k, cells[s * FN_CELL + 7]);
		c.g = g.x;
		c.b = g.y;
		if ((double)g.x <= 0.0) {
			const Variant bv = base.get(j, Variant());
			if (bv.get_type() == Variant::COLOR) {
				const Color b0 = bv;
				const Color cj = colors[j];
				if (cj != b0) {
					const double t = fn_toward(b0, cj, FN_SMEAR);
					if (t > 0.12 && fn_near(b0.lerp(FN_SMEAR, (float)t), cj)) {
						c.g = (float)(-FN_WET_SMEAR * t);
					}
				}
			}
		}
		return c;
	}

	// FineBody._layer.
	Color layer(int64_t i, int64_t k, int64_t cc, double h) const {
		if (cc == 1) {
			Color c;
			if (kinds[i] == 0 && !beast) {
				c = sk * (float)FN_SKIN_K * (float)(0.94 + 0.06 * h);
			} else {
				const Variant bv = base.get(i, Variant());
				const Color b0 = bv.get_type() == Variant::COLOR ? (Color)bv : colors[i];
				c = b0.srgb_to_linear();
			}
			return c.linear_to_srgb();
		}
		if (cc == 2) {
			return FN_FAT.darkened((float)(0.12 * h));
		}
		const int64_t kind = kinds[i];
		const bool even = ((k & 1) + ((k >> 2) & 1)) % 2 == 0;
		if (kind == 0 || kind == 1 || kind == 2 || kind == 8 || kind == 10 || kind == 11) {
			const double stripe = even ? 0.86 : 1.05;
			return Color((float)((double)FN_MUSCLE.r * stripe * (0.92 + 0.16 * h)), (float)((double)FN_MUSCLE.g * stripe * (0.9 + 0.2 * h)), (float)((double)FN_MUSCLE.b * stripe * (0.9 + 0.2 * h)));
		}
		const Color o = colors[i];
		if (kind == 6) {
			return FN_BONE.darkened((float)(0.08 * h));
		}
		if (organ.size() > i && organ[i] != 0) {
			return h > 0.5 ? o.lightened((float)(0.05 * h)) : o.darkened((float)(0.08 * h));
		}
		const double st = even ? 0.88 : 1.04;
		return Color((float)((double)o.r * st * (0.92 + 0.12 * h)), (float)((double)o.g * st * (0.92 + 0.12 * h)), (float)((double)o.b * st * (0.92 + 0.12 * h)), 1.0f);
	}

	// FineBody.wound_color.
	Color wound_color(int64_t i, int64_t k, int64_t cc, bool healed) const {
		const double h = (double)((int64_t)Variant(Vector2i((int32_t)i, (int32_t)k)).hash() % 1000) / 1000.0;
		if (healed) {
			return colors[i].lightened(0.12f).darkened((float)(0.05 * h));
		}
		double blood = 0.0;
		const Variant bv = base.get(i, Variant());
		if (bv.get_type() == Variant::COLOR) {
			const Color b0 = bv;
			if (colors[i] != b0) {
				blood = fn_toward(b0, colors[i], FN_SMEAR);
			}
		}
		Color c = layer(i, k, cc, h);
		c = c.lerp(FN_BLOOD, (float)(blood * (cc == 1 ? 1.0 : (kinds[i] == 6 ? 0.2 : 0.5))));
		if (cc == 1) {
			c = c.lerp(h > 0.3 ? FN_FRESH : FN_CLOT, (float)(0.7 + 0.2 * h));
		}
		return c;
	}

	// What a bared voxel's cell is for the shader (_write_wound, _write_wound_glow, taken).
	Color wound_custom(int64_t i, int64_t cc, const Vector2 &g, bool healed) const {
		const int64_t kd = cc == 1 ? 0 : ((cc == 2 || kinds[i] <= 2) ? 9 : (int64_t)kinds[i]);
		Color cu = fn_kind_data(kd, 0);
		cu.g = ((double)g.x > 0.0 || healed) ? g.x : (float)(-(kd == 6 ? FN_WET_BONE : FN_WET[cc]));
		cu.b = g.y;
		return cu;
	}

	Vector2 glow_of(int64_t i) const {
		const Variant v = glowing.get(i, Variant());
		return v.get_type() == Variant::VECTOR2 ? (Vector2)v : Vector2();
	}
};

} // namespace

// Whether the part's fine look is one these read (its arrays as long as they are taken to be):
// asked once, when the look is made (FineBody.build).
bool VoxelCore::fine_ready(Object *part) const {
	const FinePart f(part, 2, 10);
	return f.ok;
}

// FineBody.colored's skin: the fine voxels over voxels `indices` coloured as they are now (the
// blood on them, a burn, wet where the blood is fresh), set on their drawings with `apply`.
// Returns them, ten numbers each: the drawing (0 his own, 1 the far piece of a bent limb, 2 his
// jaw), the slot, the colour, the shader's data. Without `colors` only the shader's data is set
// (FineBody.status: the fire or the poison on a voxel, or its shading, changed).
PackedFloat32Array VoxelCore::fine_colored(Object *part, const PackedInt32Array &indices, bool apply, int res, int margin, bool colors) const {
	PackedFloat32Array out;
	const FinePart f(part, res, margin);
	if (!f.ok) {
		return out;
	}
	const int64_t cells_n = f.par.size();
	const int64_t na_n = f.na.size();
	std::vector<float> rows;
	for (int64_t q = 0; q < indices.size(); q++) {
		const int64_t i = indices[q];
		if (i < 0 || i >= f.n) {
			continue;
		}
		const Variant ov = f.of.get(i, Variant());
		if (ov.get_type() != Variant::ARRAY) {
			continue;
		}
		const Array over = ov;
		const Vector2 g = f.glow_of(i);
		for (int64_t e = 0; e < over.size(); e++) {
			const int64_t s = over[e];
			if (s < 0 || s >= cells_n) {
				continue;
			}
			int64_t slot = 0;
			int which = 0;
			MultiMesh *m = f.slot_of(s, slot, which);
			Color col = f.skin_color(s, i);
			if (s < na_n) {
				col.a = f.na[s];
			}
			const Color cu = f.skin_custom(s, i, g);
			if (apply && m != nullptr) {
				if (colors) {
					m->set_instance_color((int32_t)slot, col);
				}
				m->set_instance_custom_data((int32_t)slot, cu);
			}
			const size_t at = rows.size();
			rows.resize(at + 10);
			rows[at] = (float)which;
			rows[at + 1] = (float)slot;
			fn_put_col(&rows[at + 2], col);
			fn_put_col(&rows[at + 6], cu);
		}
	}
	out.resize((int64_t)rows.size());
	if (!rows.empty()) {
		memcpy(out.ptrw(), rows.data(), rows.size() * sizeof(float));
	}
	return out;
}

// FineBody._write_wound (`mode` 0), _write_wound_glow (1) and that with the colours (2) for the
// bared voxels `voxels`: each one's eight cells, twenty numbers a cell as a MultiMesh holds them
// (its place unbent, a cell that is not his at no size; its colour; the shader's data). With
// `apply` they are set on the wound's drawing at the voxel's slot (fine.wound): the places too
// with `apply_xf` (a limb straight; one bent at a break has them set by the script).
PackedFloat32Array VoxelCore::fine_wound(Object *part, const PackedInt32Array &voxels, int mode, bool apply, bool apply_xf, int res, int margin) const {
	PackedFloat32Array out;
	const FinePart f(part, res, margin);
	if (!f.ok) {
		return out;
	}
	const double vf = part->get("vf");
	const real_t sc = (real_t)(double)part->get("part_scale");
	const int64_t count = voxels.size();
	out.resize(count * 160);
	float *o = out.ptrw();
	const int64_t wm_n = (apply && f.wmm != nullptr) ? f.wmm->get_instance_count() : 0;
	for (int64_t q = 0; q < count; q++) {
		const int64_t i = voxels[q];
		float *row = o + q * 160;
		for (int z = 0; z < 160; z++) {
			row[z] = 0.0f;
		}
		if (i < 0 || i >= f.n) {
			continue;
		}
		int64_t slot = -1;
		const Variant sv = f.wound.get(i, Variant());
		if (sv.get_type() == Variant::INT) {
			slot = sv;
		}
		const bool write = slot >= 0 && slot * 8 + 8 <= wm_n;
		const int64_t code = f.code[i];
		const Vector3 c = f.local_of(i, vf, sc);
		const Vector2 g = f.glow_of(i);
		const bool healed = f.scarred.has(i);
		for (int64_t k = 0; k < 8; k++) {
			const int64_t cc = (code >> (2 * k)) & 3;
			float *cell = row + k * 20;
			if (mode == 0) {
				const Vector3 at = c + (Vector3((real_t)(k & 1), (real_t)((k >> 1) & 1), (real_t)((k >> 2) & 1)) - Vector3(0.5, 0.5, 0.5)) * (real_t)f.fsz;
				Transform3D t = f.mapped(at, cc == 1 ? 0.97 : 1.0);
				if (cc == 0) {
					t = Transform3D(Basis::from_scale(Vector3()), t.origin);
				}
				fn_put_xf(cell, t);
				if (write && apply_xf) {
					f.wmm->set_instance_transform((int32_t)(slot * 8 + k), t);
				}
			}
			if (mode != 1) {
				const Color col = f.wound_color(i, k, cc, healed);
				fn_put_col(cell + 12, col);
				if (write) {
					f.wmm->set_instance_color((int32_t)(slot * 8 + k), col);
				}
			}
			const Color cu = f.wound_custom(i, cc, g, healed);
			fn_put_col(cell + 16, cu);
			if (write) {
				f.wmm->set_instance_custom_data((int32_t)(slot * 8 + k), cu);
			}
		}
	}
	return out;
}

// FineBody.shown's first half: the fine voxels over voxels `indices` shown (`on`, where the
// voxel lives) or put away, each on the drawing it is on (with `apply`); and the voxels a wound
// is to be looked at for, in the script's order: each of `indices` and the voxels beside it face
// to face, once each, with whether it lives and has a face open on the wound (_open). Two
// numbers each: the voxel, 1 or 0.
PackedInt32Array VoxelCore::fine_show(Object *part, const PackedInt32Array &indices, bool on, bool apply) const {
	PackedInt32Array out;
	const FinePart f(part, 2, 10);
	if (!f.ok) {
		return out;
	}
	const Transform3D none(Basis::from_scale(Vector3()), Vector3());
	const int64_t cells_n = f.par.size();
	std::vector<uint8_t> seen((size_t)f.n, 0);
	std::vector<int32_t> near;
	near.reserve((size_t)indices.size() * 4);
	for (int64_t q = 0; q < indices.size(); q++) {
		const int64_t i = indices[q];
		if (i < 0 || i >= f.n) {
			continue;
		}
		if (seen[i] == 0) {
			seen[i] = 1;
			near.push_back((int32_t)i);
		}
		for (int w = 0; w < 6; w++) {
			const int64_t k = f.cell(f.fx[i] + FN_FACES[w][0], f.fy[i] + FN_FACES[w][1], f.fz[i] + FN_FACES[w][2]);
			if (k >= 0 && k < f.n && seen[k] == 0) {
				seen[k] = 1;
				near.push_back((int32_t)k);
			}
		}
		if (!apply || f.mm == nullptr) {
			continue;
		}
		const Variant ov = f.of.get(i, Variant());
		if (ov.get_type() != Variant::ARRAY) {
			continue;
		}
		const Array over = ov;
		const bool up = on && f.alive[i] == 1;
		for (int64_t e = 0; e < over.size(); e++) {
			const int64_t s = over[e];
			if (s < 0 || s >= cells_n) {
				continue;
			}
			int64_t slot = 0;
			int which = 0;
			MultiMesh *m = f.slot_of(s, slot, which);
			if (m == nullptr) {
				continue;
			}
			if (!up) {
				m->set_instance_transform((int32_t)slot, none);
				continue;
			}
			Transform3D t = f.xf[s];
			if (which == 2) {
				t.origin -= f.jaw_off;
			}
			m->set_instance_transform((int32_t)slot, t);
		}
	}
	out.resize((int64_t)near.size() * 2);
	int32_t *o = out.ptrw();
	for (size_t q = 0; q < near.size(); q++) {
		const int64_t i = near[q];
		int32_t open = 0;
		if (f.alive[i] == 1 && f.code[i] != 0) {
			for (int w = 0; w < 6 && open == 0; w++) {
				const int64_t k = f.cell(f.fx[i] + FN_FACES[w][0], f.fy[i] + FN_FACES[w][1], f.fz[i] + FN_FACES[w][2]);
				if (k >= 0 && k < f.n && f.alive[k] == 0) {
					open = 1;
				}
			}
		}
		o[q * 2] = (int32_t)i;
		o[q * 2 + 1] = open;
	}
	return out;
}

// FineBody.taken: what the fine look drew of voxels `idx` of the part, cut off it as one piece:
// the skin's fine voxels over each as they are drawn (read off the drawing where there is one),
// and where the cut bares a voxel its cells as deep in him as they lie. Twenty numbers a cell.
PackedFloat32Array VoxelCore::fine_taken(Object *part, const PackedInt32Array &idx, int res, int margin) const {
	PackedFloat32Array out;
	const FinePart f(part, res, margin);
	if (!f.ok) {
		return out;
	}
	const double vf = part->get("vf");
	const real_t sc = (real_t)(double)part->get("part_scale");
	const int64_t cells_n = f.par.size();
	const bool drawn = f.mm != nullptr;
	const bool faced = f.na.size() == f.xf.size();
	std::vector<uint8_t> mine((size_t)f.n, 0);
	for (int64_t q = 0; q < idx.size(); q++) {
		const int64_t i = idx[q];
		if (i >= 0 && i < f.n) {
			mine[i] = 1;
		}
	}
	std::vector<float> buf;
	buf.reserve((size_t)idx.size() * 80);
	for (int64_t q = 0; q < idx.size(); q++) {
		const int64_t i = idx[q];
		if (i < 0 || i >= f.n) {
			continue;
		}
		int64_t skin = 0;
		const Variant ov = f.of.get(i, Variant());
		if (ov.get_type() == Variant::ARRAY) {
			const Array over = ov;
			const Vector2 g = f.glow_of(i);
			for (int64_t e = 0; e < over.size(); e++) {
				const int64_t s = over[e];
				if (s < 0 || s >= cells_n) {
					continue;
				}
				Color col;
				Color cu;
				int64_t slot = 0;
				int which = 0;
				MultiMesh *m = drawn ? f.slot_of(s, slot, which) : nullptr;
				if (m != nullptr) {
					col = m->get_instance_color((int32_t)slot);
					cu = m->get_instance_custom_data((int32_t)slot);
				} else {
					const int64_t j = f.par[s];
					col = j >= 0 ? f.skin_color(s, j) : f.own[s];
					col.a = faced ? f.na[s] : 1.0f;
					cu = f.skin_custom(s, j >= 0 ? j : 0, g);
				}
				const size_t at = buf.size();
				buf.resize(at + 20);
				fn_put_xf(&buf[at], (Transform3D)f.xf[s]);
				fn_put_col(&buf[at + 12], col);
				fn_put_col(&buf[at + 16], cu);
				skin += 1;
			}
		}
		// Bared by the cut: a voxel of the part beside it that is not of the piece.
		bool bared = skin == 0;
		for (int w = 0; w < 6 && !bared; w++) {
			const int64_t k = f.cell(f.fx[i] + FN_FACES[w][0], f.fy[i] + FN_FACES[w][1], f.fz[i] + FN_FACES[w][2]);
			if (k >= 0 && k < f.n && mine[k] == 0) {
				bared = true;
			}
		}
		if (!bared) {
			continue;
		}
		const int64_t cd = f.code[i];
		if (cd == 0) {
			continue;
		}
		const Vector3 lp = f.local_of(i, vf, sc);
		const double kk = f.k_at(lp);
		const Vector2 g = f.glow_of(i);
		const bool healed = f.scarred.has(i);
		for (int64_t k = 0; k < 8; k++) {
			const int64_t cc = (cd >> (2 * k)) & 3;
			if (cc == 0 || (cc == 1 && skin > 0)) {
				continue;
			}
			const Vector3 at = lp + (Vector3((real_t)(k & 1), (real_t)((k >> 1) & 1), (real_t)((k >> 2) & 1)) - Vector3(0.5, 0.5, 0.5)) * (real_t)f.fsz;
			const Transform3D t(Basis::from_scale(Vector3((real_t)kk, (real_t)1.0, (real_t)kk)), Vector3((real_t)((double)at.x * kk), at.y, (real_t)((double)at.z * kk)));
			const size_t o = buf.size();
			buf.resize(o + 20);
			fn_put_xf(&buf[o], t);
			fn_put_col(&buf[o + 12], f.wound_color(i, k, cc, healed));
			fn_put_col(&buf[o + 16], f.wound_custom(i, cc, g, healed));
		}
	}
	out.resize((int64_t)buf.size());
	if (!buf.empty()) {
		memcpy(out.ptrw(), buf.data(), buf.size() * sizeof(float));
	}
	return out;
}

// VoxelPart._reshade's search and shade_bits: the living voxels within one cell of any of
// `changed` (the 27 cells round each), each once, in the script's order, each with its shading
// (shade_bits: the corner bits of its six faces, and with `bevel` its open faces above them).
// Two numbers each: the voxel, its bits.
PackedInt32Array VoxelCore::reshade(const PackedInt32Array &changed, const PackedInt32Array &fx, const PackedInt32Array &fy, const PackedInt32Array &fz, const PackedInt32Array &cellmap, const PackedByteArray &alive, const PackedByteArray &veil, const Vector3i &grid, bool bevel) const {
	PackedInt32Array out;
	const int64_t n = fx.size();
	const int64_t gx = grid.x, gy = grid.y, gz = grid.z;
	if (fy.size() < n || fz.size() < n || alive.size() < n || cellmap.size() < gx * gy * gz) {
		return out;
	}
	// VoxelPart._face_ao_table.
	static int32_t face[512];
	static bool face_made = false;
	if (!face_made) {
		for (int p = 0; p < 512; p++) {
			int bits = 0;
			if ((p & 16) == 0) {
				for (int c = 0; c < 4; c++) {
					const int u = (c & 1) ? 2 : 0;
					const int v = (c & 2) ? 2 : 0;
					if ((p & (1 << (u * 3 + 1))) || (p & (1 << (3 + v))) || (p & (1 << (u * 3 + v)))) {
						bits |= 1 << c;
					}
				}
			}
			face[p] = bits;
		}
		face_made = true;
	}
	const int32_t *cm = cellmap.ptr();
	const int32_t *px = fx.ptr();
	const int32_t *py = fy.ptr();
	const int32_t *pz_ = fz.ptr();
	const uint8_t *al = alive.ptr();
	const uint8_t *vl = veil.ptr();
	const int64_t vs = veil.size();
	std::vector<uint8_t> seen((size_t)n, 0);
	std::vector<int32_t> todo;
	for (int64_t q = 0; q < changed.size(); q++) {
		const int64_t i = changed[q];
		if (i < 0 || i >= n) {
			continue;
		}
		const int64_t x = px[i], y = py[i], z = pz_[i];
		const int64_t x0 = x - 1 > 0 ? x - 1 : 0, x1 = x + 2 < gx ? x + 2 : gx;
		const int64_t y0 = y - 1 > 0 ? y - 1 : 0, y1 = y + 2 < gy ? y + 2 : gy;
		const int64_t z0 = z - 1 > 0 ? z - 1 : 0, z1 = z + 2 < gz ? z + 2 : gz;
		for (int64_t ax = x0; ax < x1; ax++) {
			for (int64_t ay = y0; ay < y1; ay++) {
				const int64_t row = (ax * gy + ay) * gz;
				for (int64_t az = z0; az < z1; az++) {
					const int64_t j = (int64_t)cm[row + az] - 1;
					if (j >= 0 && j < n && seen[j] == 0 && al[j] == 1) {
						seen[j] = 1;
						todo.push_back((int32_t)j);
					}
				}
			}
		}
	}
	out.resize((int64_t)todo.size() * 2);
	int32_t *o = out.ptrw();
	for (size_t q = 0; q < todo.size(); q++) {
		const int64_t i = todo[q];
		const int64_t x = px[i], y = py[i], z = pz_[i];
		int64_t occ = 0; // bit a*9 + b*3 + c: the cell (x+a-1, y+b-1, z+c-1) is solid
		for (int64_t a = (1 - x > 0 ? 1 - x : 0); a < (gx + 1 - x < 3 ? gx + 1 - x : 3); a++) {
			for (int64_t b = (1 - y > 0 ? 1 - y : 0); b < (gy + 1 - y < 3 ? gy + 1 - y : 3); b++) {
				const int64_t row = ((x + a - 1) * gy + y + b - 1) * gz + z - 1;
				const int64_t bit = a * 9 + b * 3;
				for (int64_t c = (1 - z > 0 ? 1 - z : 0); c < (gz + 1 - z < 3 ? gz + 1 - z : 3); c++) {
					const int64_t k = (int64_t)cm[row + c] - 1;
					if (k >= 0 && k < n && al[k] == 1 && (k >= vs || vl[k] == 0)) {
						occ |= (int64_t)1 << (bit + c);
					}
				}
			}
		}
		int64_t pz = (occ >> 2) & 0x1249249;
		pz = (pz ^ (pz >> 2)) & 0x30c30c3;
		pz = (pz ^ (pz >> 4)) & 0x300f00f;
		pz = (pz ^ (pz >> 8)) & 0xff0000ff;
		pz = (pz ^ (pz >> 16)) & 0x3ff;
		int64_t mz = occ & 0x1249249;
		mz = (mz ^ (mz >> 2)) & 0x30c30c3;
		mz = (mz ^ (mz >> 4)) & 0x300f00f;
		mz = (mz ^ (mz >> 8)) & 0xff0000ff;
		mz = (mz ^ (mz >> 16)) & 0x3ff;
		int64_t bits = face[(occ >> 18) & 511] | ((int64_t)face[occ & 511] << 4) | ((int64_t)face[((occ >> 6) & 7) | ((occ >> 12) & 56) | ((occ >> 18) & 448)] << 8) | ((int64_t)face[(occ & 7) | ((occ >> 6) & 56) | ((occ >> 12) & 448)] << 12) | ((int64_t)face[pz] << 16) | ((int64_t)face[mz] << 20);
		if (bevel) {
			const int64_t shut = ((occ >> 22) & 1) | ((occ >> 3) & 2) | ((occ >> 14) & 4) | ((occ >> 7) & 8) | ((occ >> 10) & 16) | ((occ >> 7) & 32);
			bits |= (63 ^ shut) << 24;
		}
		o[q * 2] = (int32_t)i;
		o[q * 2 + 1] = (int32_t)bits;
	}
	return out;
}

// Of the points `pts`, those no further than `r` from `q` (in order), `alive` and not `skip`
// (Weapon.bloody: the voxels of a weapon round where blood struck it).
PackedInt32Array VoxelCore::points_near(const PackedVector3Array &pts, const PackedByteArray &alive, const PackedByteArray &skip, const Vector3 &q, double r) const {
	PackedInt32Array out;
	const int64_t n = pts.size();
	if (alive.size() < n) {
		return out;
	}
	const Vector3 *p = pts.ptr();
	const uint8_t *al = alive.ptr();
	const uint8_t *sk = skip.ptr();
	const int64_t sn = skip.size();
	for (int64_t i = 0; i < n; i++) {
		if (al[i] == 0 || (i < sn && sk[i] != 0)) {
			continue;
		}
		if ((double)p[i].distance_to(q) > r) {
			continue;
		}
		out.push_back((int32_t)i);
	}
	return out;
}

// Of the living points `pts`, the one nearest `q` (the first of the nearest), or -1
// (Match._spray_on: where a shield is nearest the blood thrown).
int VoxelCore::point_nearest(const PackedVector3Array &pts, const PackedByteArray &alive, const Vector3 &q) const {
	const int64_t n = pts.size();
	if (alive.size() < n) {
		return -1;
	}
	const Vector3 *p = pts.ptr();
	const uint8_t *al = alive.ptr();
	int best = -1;
	real_t bd = 0.0;
	for (int64_t i = 0; i < n; i++) {
		if (al[i] == 0) {
			continue;
		}
		const real_t d = p[i].distance_squared_to(q);
		if (best < 0 || d < bd) {
			bd = d;
			best = (int)i;
		}
	}
	return best;
}
