// The fine look's smooth skin (scripts/fighter/fine_smooth.gd: solid, joined, blurred, ways,
// corners): the same results as the GDScript, bit for bit. In the script a part's skin was seconds
// of work the first time a build was drawn, and a head's every time a man was. As in drive.cpp,
// each line does what the script's line does, in the same types and order: what the script holds
// in a float is a double here, what it holds in a PackedFloat32Array or a vector is a float.

#include "voxel_core.h"

#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <godot_cpp/variant/variant.hpp>
#include <godot_cpp/variant/vector2.hpp>

#include <cmath>
#include <vector>

using namespace godot;

namespace {

// A field as FineSmooth.solid lays it: {f, sx, sy, sz, lo, pad}.
struct Field {
	PackedFloat32Array arr;
	const float *f = nullptr;
	int64_t sx = 0, sy = 0, sz = 0, pad = 0;
	Vector3i lo;
	bool ok = false;
};

Field read_field(const Dictionary &d) {
	static const StringName k_f("f"), k_sx("sx"), k_sy("sy"), k_sz("sz"), k_lo("lo"), k_pad("pad");
	Field o;
	if (d.is_empty() || !d.has(k_f)) {
		return o;
	}
	o.arr = d[k_f];
	o.f = o.arr.ptr();
	o.sx = d[k_sx];
	o.sy = d[k_sy];
	o.sz = d[k_sz];
	o.pad = d[k_pad];
	o.lo = d[k_lo];
	o.ok = o.f != nullptr && o.sx > 0 && o.sy > 0 && o.sz > 0 && o.arr.size() == o.sx * o.sy * o.sz;
	return o;
}

// FineSmooth._box
void box_pass(const float *f, float *out, int64_t sx, int64_t sy, int64_t sz, int axis, int64_t r) {
	const int64_t len = axis == 0 ? sx : (axis == 1 ? sy : sz);
	const int64_t stride = axis == 0 ? sy * sz : (axis == 1 ? sz : 1);
	const int64_t na = axis == 0 ? sy : sx;
	const int64_t nb = axis != 2 ? sz : sy;
	const double w = 1.0 / (double)(2 * r + 1);
	const int64_t first = r < len ? r : len;
	for (int64_t a = 0; a < na; a++) {
		for (int64_t b = 0; b < nb; b++) {
			int64_t base = 0;
			if (axis == 0) {
				base = a * sz + b;
			} else if (axis == 1) {
				base = a * sy * sz + b;
			} else {
				base = (a * sy + b) * sz;
			}
			double sum = 0.0;
			for (int64_t t = 0; t < first; t++) {
				sum += (double)f[base + t * stride];
			}
			for (int64_t t = 0; t < len; t++) {
				if (t + r < len) {
					sum += (double)f[base + (t + r) * stride];
				}
				if (t - r - 1 >= 0) {
					sum -= (double)f[base + (t - r - 1) * stride];
				}
				out[base + t * stride] = (float)(sum * w);
			}
		}
	}
}

// FineSmooth.blurred's passes: a box each way, twice over.
void blur(std::vector<float> &f, int64_t sx, int64_t sy, int64_t sz, int64_t r) {
	std::vector<float> tmp(f.size());
	for (int axis = 0; axis < 3; axis++) {
		for (int pass = 0; pass < 2; pass++) {
			box_pass(f.data(), tmp.data(), sx, sy, sz, axis, r);
			f.swap(tmp);
		}
	}
}

// Vector3.normalized() as the engine has it.
Vector3 sm_normalized(Vector3 v) {
	real_t l = v.x * v.x + v.y * v.y + v.z * v.z;
	if (l == 0) {
		return Vector3();
	}
	l = Math::sqrt(l);
	v.x /= l;
	v.y /= l;
	v.z /= l;
	return v;
}

// FineSmooth.encode
double encode(const Vector3 &n) {
	const double s = std::fabs((double)n.x) + std::fabs((double)n.y) + std::fabs((double)n.z);
	if (s < 1e-6) {
		return 1.0;
	}
	const real_t sf = (real_t)s;
	real_t ox = n.x / sf;
	real_t oy = n.y / sf;
	if ((double)n.z < 0.0) {
		const real_t tx = (real_t)((1.0 - std::fabs((double)oy)) * ((double)ox >= 0.0 ? 1.0 : -1.0));
		const real_t ty = (real_t)((1.0 - std::fabs((double)ox)) * ((double)oy >= 0.0 ? 1.0 : -1.0));
		ox = tx;
		oy = ty;
	}
	int64_t u = (int64_t)std::round(((double)ox * 0.5 + 0.5) * 31.0);
	int64_t v = (int64_t)std::round(((double)oy * 0.5 + 0.5) * 31.0);
	u = u < 0 ? 0 : (u > 31 ? 31 : u);
	v = v < 0 ? 0 : (v > 31 ? 31 : v);
	return 2.0 + (double)(u * 32 + v);
}

// FineSmooth._slope: the slope (x y z) and the fill (w) of a field at the corner cell `i` and the
// seven before it meet at.
struct Slope {
	float x, y, z, w;
};

inline Slope slope(const float *f, int64_t i, int64_t syz, int64_t sz) {
	const double a000 = f[i - syz - sz - 1];
	const double a001 = f[i - syz - sz];
	const double a010 = f[i - syz - 1];
	const double a011 = f[i - syz];
	const double a100 = f[i - sz - 1];
	const double a101 = f[i - sz];
	const double a110 = f[i - 1];
	const double a111 = f[i];
	Slope s;
	s.x = (float)(((a100 + a101 + a110 + a111) - (a000 + a001 + a010 + a011)) * 0.25);
	s.y = (float)(((a010 + a011 + a110 + a111) - (a000 + a001 + a100 + a101)) * 0.25);
	s.z = (float)(((a001 + a011 + a101 + a111) - (a000 + a010 + a100 + a110)) * 0.25);
	s.w = (float)((a000 + a001 + a010 + a011 + a100 + a101 + a110 + a111) * 0.125);
	return s;
}

const int FACES[6][4][3] = {
	{ { 1, 0, 0 }, { 1, 1, 0 }, { 1, 1, 1 }, { 1, 0, 1 } },
	{ { 0, 0, 0 }, { 0, 0, 1 }, { 0, 1, 1 }, { 0, 1, 0 } },
	{ { 0, 1, 0 }, { 0, 1, 1 }, { 1, 1, 1 }, { 1, 1, 0 } },
	{ { 0, 0, 0 }, { 1, 0, 0 }, { 1, 0, 1 }, { 0, 0, 1 } },
	{ { 0, 0, 1 }, { 1, 0, 1 }, { 1, 1, 1 }, { 0, 1, 1 } },
	{ { 0, 0, 0 }, { 0, 1, 0 }, { 1, 1, 0 }, { 1, 0, 0 } },
};

inline double clampd(double v, double lo, double hi) {
	return v < lo ? lo : (v > hi ? hi : v);
}

} // namespace

Dictionary VoxelCore::smooth_solid(const PackedInt32Array &at, const PackedInt32Array &inner, int res, bool seal_lo, bool seal_hi, int pad) const {
	Dictionary out;
	const int64_t n = at.size() / 3;
	if (n == 0) {
		return out;
	}
	const int32_t *a = at.ptr();
	int64_t lox = a[0], loy = a[1], loz = a[2], hix = a[0], hiy = a[1], hiz = a[2];
	for (int64_t s = 0; s < n; s++) {
		const int64_t x = a[s * 3], y = a[s * 3 + 1], z = a[s * 3 + 2];
		lox = x < lox ? x : lox;
		loy = y < loy ? y : loy;
		loz = z < loz ? z : loz;
		hix = x > hix ? x : hix;
		hiy = y > hiy ? y : hiy;
		hiz = z > hiz ? z : hiz;
	}
	const int64_t sx = hix - lox + 1 + 2 * pad;
	const int64_t sy = hiy - loy + 1 + 2 * pad;
	const int64_t sz = hiz - loz + 1 + 2 * pad;
	const int64_t syz = sy * sz;
	const int64_t total = sx * syz;
	PackedFloat32Array farr;
	farr.resize(total);
	float *f = farr.ptrw();
	for (int64_t i = 0; i < total; i++) {
		f[i] = 0.0f;
	}
	for (int64_t s = 0; s < n; s++) {
		f[((a[s * 3] - lox + pad) * sy + (a[s * 3 + 1] - loy + pad)) * sz + (a[s * 3 + 2] - loz + pad)] = 1.0f;
	}
	const int64_t ni = inner.size() / 3;
	const int32_t *in = inner.ptr();
	for (int64_t k = 0; k < ni; k++) {
		for (int64_t da = 0; da < res; da++) {
			const int64_t x = (int64_t)in[k * 3] * res + da - lox + pad;
			if (x < pad || x >= sx - pad) {
				continue;
			}
			for (int64_t db = 0; db < res; db++) {
				const int64_t y = (int64_t)in[k * 3 + 1] * res + db - loy + pad;
				if (y < pad || y >= sy - pad) {
					continue;
				}
				for (int64_t dc = 0; dc < res; dc++) {
					const int64_t z = (int64_t)in[k * 3 + 2] * res + dc - loz + pad;
					if (z >= pad && z < sz - pad) {
						f[(x * sy + y) * sz + z] = 1.0f;
					}
				}
			}
		}
	}
	// What is outside him: all that can be reached from a corner without going through him, and
	// not in by an end that is shut. The rest is him.
	const int64_t shut_a = seal_lo ? pad : -1;
	const int64_t shut_b = seal_hi ? sy - pad : -1;
	std::vector<uint8_t> outside(total, 0);
	std::vector<int64_t> stack;
	stack.reserve(total);
	stack.push_back((int64_t)pad * sz);
	outside[(int64_t)pad * sz] = 1;
	while (!stack.empty()) {
		const int64_t i = stack.back();
		stack.pop_back();
		const int64_t z = i % sz;
		const int64_t y = (i / sz) % sy;
		const int64_t x = i / syz;
		if (x > 0 && outside[i - syz] == 0 && f[i - syz] == 0.0f) {
			outside[i - syz] = 1;
			stack.push_back(i - syz);
		}
		if (x < sx - 1 && outside[i + syz] == 0 && f[i + syz] == 0.0f) {
			outside[i + syz] = 1;
			stack.push_back(i + syz);
		}
		if (y > 0 && y != shut_a && y != shut_b && outside[i - sz] == 0 && f[i - sz] == 0.0f) {
			outside[i - sz] = 1;
			stack.push_back(i - sz);
		}
		if (y < sy - 1 && y + 1 != shut_a && y + 1 != shut_b && outside[i + sz] == 0 && f[i + sz] == 0.0f) {
			outside[i + sz] = 1;
			stack.push_back(i + sz);
		}
		if (z > 0 && outside[i - 1] == 0 && f[i - 1] == 0.0f) {
			outside[i - 1] = 1;
			stack.push_back(i - 1);
		}
		if (z < sz - 1 && outside[i + 1] == 0 && f[i + 1] == 0.0f) {
			outside[i + 1] = 1;
			stack.push_back(i + 1);
		}
	}
	for (int64_t x = 0; x < sx; x++) {
		for (int64_t y = pad; y < sy - pad; y++) {
			const int64_t b = (x * sy + y) * sz;
			for (int64_t z = 0; z < sz; z++) {
				if (outside[b + z] == 0) {
					f[b + z] = 1.0f;
				}
			}
		}
	}
	out["f"] = farr;
	out["sx"] = sx;
	out["sy"] = sy;
	out["sz"] = sz;
	out["lo"] = Vector3i((int32_t)lox, (int32_t)loy, (int32_t)loz);
	out["pad"] = pad;
	return out;
}

Dictionary VoxelCore::smooth_joined(const Dictionary &sol, const Array &beside) const {
	const Field me = read_field(sol);
	if (!me.ok || beside.is_empty()) {
		return sol;
	}
	Dictionary out = sol.duplicate();
	PackedFloat32Array farr = me.arr;   // (its own on the first write)
	float *f = farr.ptrw();
	PackedInt32Array added;
	const int64_t sx = me.sx, sy = me.sy, sz = me.sz, pad = me.pad;
	for (int64_t bi = 0; bi < beside.size(); bi++) {
		const Array b = beside[bi];
		const Field o = read_field(b[0]);
		if (!o.ok) {
			continue;
		}
		const Vector3i shift = b[1];
		const Vector3 joint = b[2];
		const double r = b[3];
		const double r2 = r * r;
		// (This part's whole grid, each cell looked up in the other's.)
		for (int64_t x = 0; x < sx; x++) {
			const int64_t qx = x - pad + me.lo.x;
			const int64_t ox = qx - shift.x - o.lo.x + o.pad;
			if (ox < 0 || ox >= o.sx) {
				continue;
			}
			const double dx = (double)qx + 0.5 - (double)joint.x;
			for (int64_t y = 0; y < sy; y++) {
				const int64_t qy = y - pad + me.lo.y;
				const int64_t oy = qy - shift.y - o.lo.y + o.pad;
				if (oy < 0 || oy >= o.sy) {
					continue;
				}
				const double dy = (double)qy + 0.5 - (double)joint.y;
				if (dx * dx + dy * dy > r2) {
					continue;
				}
				const int64_t row = (x * sy + y) * sz;
				const int64_t orow = (ox * o.sy + oy) * o.sz;
				for (int64_t z = 0; z < sz; z++) {
					const int64_t qz = z - pad + me.lo.z;
					const int64_t oz = qz - shift.z - o.lo.z + o.pad;
					if (oz < 0 || oz >= o.sz) {
						continue;
					}
					const double dz = (double)qz + 0.5 - (double)joint.z;
					if (dx * dx + dy * dy + dz * dz <= r2 && o.f[orow + oz] > 0.5f && f[row + z] <= 0.5f) {
						f[row + z] = 1.0f;
						added.push_back((int32_t)(row + z));
					}
				}
			}
		}
	}
	out["f"] = farr;
	out["added"] = added;
	return out;
}

PackedFloat32Array VoxelCore::smooth_blur(const PackedFloat32Array &f, int sx, int sy, int sz, int r) const {
	const int64_t total = (int64_t)sx * sy * sz;
	if (total <= 0 || f.size() != total) {
		return f;
	}
	std::vector<float> a(f.ptr(), f.ptr() + total);
	blur(a, sx, sy, sz, r);
	PackedFloat32Array out;
	out.resize(total);
	float *w = out.ptrw();
	for (int64_t i = 0; i < total; i++) {
		w[i] = a[i];
	}
	return out;
}

PackedFloat32Array VoxelCore::smooth_ways(const PackedInt32Array &at, const Dictionary &fld, const Dictionary &sol, const Dictionary &own_fld) const {
	const int64_t n = at.size() / 3;
	PackedFloat32Array out;
	out.resize(n);
	float *w = out.ptrw();
	for (int64_t s = 0; s < n; s++) {
		w[s] = 1.0f;
	}
	const Field fl = read_field(fld);
	if (!fl.ok) {
		return out;
	}
	const Field so = read_field(sol);
	const Field ow = read_field(own_fld);
	const bool ends = so.ok && ow.ok;
	const float *f = fl.f;
	const int64_t sy = fl.sy, sz = fl.sz, syz = sy * sz, pad = fl.pad;
	const int32_t *a = at.ptr();
	for (int64_t s = 0; s < n; s++) {
		const int64_t i = ((a[s * 3] - fl.lo.x + pad) * sy + (a[s * 3 + 1] - fl.lo.y + pad)) * sz + (a[s * 3 + 2] - fl.lo.z + pad);
		Vector3 g((real_t)((double)f[i + syz] - (double)f[i - syz]), (real_t)((double)f[i + sz] - (double)f[i - sz]), (real_t)((double)f[i + 1] - (double)f[i - 1]));
		if (ends && so.f[i + syz] > 0.5f && so.f[i - syz] > 0.5f && so.f[i + sz] > 0.5f && so.f[i - sz] > 0.5f && so.f[i + 1] > 0.5f && so.f[i - 1] > 0.5f) {
			g = Vector3((real_t)((double)ow.f[i + syz] - (double)ow.f[i - syz]), (real_t)((double)ow.f[i + sz] - (double)ow.f[i - sz]), (real_t)((double)ow.f[i + 1] - (double)ow.f[i - 1]));
		}
		const real_t l2 = g.x * g.x + g.y * g.y + g.z * g.z;
		if ((double)l2 > 1e-8) {
			w[s] = (float)encode(-sm_normalized(g));
		}
	}
	return out;
}

PackedFloat32Array VoxelCore::smooth_corners(const PackedInt32Array &at, const Dictionary &sol, const Dictionary &shape, const Dictionary &light, const Dictionary &own, const Dictionary &own_shape, const Dictionary &own_light, double held_in, double held_out, int even_r) const {
	const int64_t n = at.size() / 3;
	PackedFloat32Array out;
	out.resize(n * 32);
	float *ow = out.ptrw();
	for (int64_t i = 0; i < n * 32; i++) {
		ow[i] = 0.0f;
	}
	const Field so = read_field(sol);
	const Field sh = read_field(shape);
	const Field li_f = read_field(light);
	if (!so.ok || !sh.ok || !li_f.ok) {
		return out;
	}
	const Field o0 = read_field(own);
	const Field o1 = read_field(own_shape);
	const Field o2 = read_field(own_light);
	const bool ends = o0.ok && o1.ok && o2.ok;
	const float *f = so.f;
	const int64_t sx = so.sx, sy = so.sy, sz = so.sz, syz = sy * sz, pad = so.pad;
	const int64_t total = sx * syz;
	const int64_t step[6] = { syz, -syz, sz, -sz, 1, -1 };
	const float *gf = sh.f;
	const float *lf = li_f.f;
	const float *fo = ends ? o0.f : f;
	const float *gfo = ends ? o1.f : gf;
	const float *lfo = ends ? o2.f : lf;
	std::vector<uint8_t> on(total, 0);
	std::vector<float> out_by(total, 0.0f);
	std::vector<float> wsum(total, 0.0f);
	std::vector<Vector3> way(total);
	std::vector<int64_t> list;
	const int32_t *a = at.ptr();
	// (His skin first, then the part's own ends: a corner of both is his skin's.)
	for (int round_i = 0; round_i < (ends ? 2 : 1); round_i++) {
		for (int64_t s = 0; s < n; s++) {
			const int64_t ci = ((a[s * 3] - so.lo.x + pad) * sy + (a[s * 3 + 1] - so.lo.y + pad)) * sz + (a[s * 3 + 2] - so.lo.z + pad);
			for (int d = 0; d < 6; d++) {
				if (round_i == 0) {
					if (f[ci + step[d]] > 0.5f) {
						continue;
					}
				} else if (fo[ci + step[d]] > 0.5f || f[ci + step[d]] <= 0.5f) {
					continue;
				}
				for (int c4 = 0; c4 < 4; c4++) {
					const int64_t li = ci + FACES[d][c4][0] * syz + FACES[d][c4][1] * sz + FACES[d][c4][2];
					if (on[li] != 0) {
						continue;
					}
					on[li] = (uint8_t)(round_i + 1);
					list.push_back(li);
					const Slope g = slope(round_i == 0 ? gf : gfo, li, syz, sz);
					const Vector3 gv(g.x, g.y, g.z);
					const real_t gl = Math::sqrt(gv.x * gv.x + gv.y * gv.y + gv.z * gv.z);
					if ((double)gl > 0.02) {
						// (Out is down the slope; inside, over half full, the skin is further out.)
						way[li] = Vector3(-gv.x / gl, -gv.y / gl, -gv.z / gl);
						out_by[li] = (float)clampd(((double)g.w - 0.5) / (double)gl, -2.5, 2.5);
						wsum[li] = 1.0f;
					}
				}
			}
		}
	}
	// By a joint the skin of the part beside it is in the mean too (joined: its cells).
	if (sol.has("added")) {
		const PackedInt32Array beside = sol["added"];
		const int32_t *bp = beside.ptr();
		for (int64_t k = 0; k < beside.size(); k++) {
			const int64_t ci = bp[k];
			const int64_t bz = ci % sz;
			const int64_t by = (ci / sz) % sy;
			const int64_t bx = ci / syz;
			if (bx < 1 || by < 1 || bz < 1 || bx > sx - 3 || by > sy - 3 || bz > sz - 3) {
				continue;
			}
			for (int d = 0; d < 6; d++) {
				if (f[ci + step[d]] > 0.5f) {
					continue;
				}
				for (int c4 = 0; c4 < 4; c4++) {
					const int64_t li = ci + FACES[d][c4][0] * syz + FACES[d][c4][1] * sz + FACES[d][c4][2];
					if (on[li] != 0 || wsum[li] != 0.0f) {
						continue;
					}
					const Slope g = slope(gf, li, syz, sz);
					const real_t gl = Math::sqrt(g.x * g.x + g.y * g.y + g.z * g.z);
					if ((double)gl > 0.02) {
						out_by[li] = (float)clampd(((double)g.w - 0.5) / (double)gl, -2.5, 2.5);
						wsum[li] = 1.0f;
					}
				}
			}
		}
	}
	// What the corners round each place are moved alike (the mean of them, even_r round it).
	std::vector<float> even(out_by);
	std::vector<float> cover(wsum);
	const int64_t er = even_r < pad - 1 ? even_r : pad - 1;
	blur(even, sx, sy, sz, er);
	blur(cover, sx, sy, sz, er);
	std::vector<Vector3> move(total);
	for (const int64_t li : list) {
		if (wsum[li] == 0.0f || (double)cover[li] < 1e-6) {
			continue;
		}
		const double av = (double)out_by[li] - (double)even[li] / (double)cover[li];
		move[li] = way[li] * (real_t)clampd(av, -held_in, held_out);
	}
	for (int64_t s = 0; s < n; s++) {
		const int64_t ci = ((a[s * 3] - so.lo.x + pad) * sy + (a[s * 3 + 1] - so.lo.y + pad)) * sz + (a[s * 3 + 2] - so.lo.z + pad);
		for (int c = 0; c < 8; c++) {
			const int64_t li = ci + (c & 1) * syz + ((c >> 1) & 1) * sz + ((c >> 2) & 1);
			const int64_t o = (s * 8 + c) * 4;
			if (on[li] != 0) {
				ow[o] = move[li].x;
				ow[o + 1] = move[li].y;
				ow[o + 2] = move[li].z;
			}
			const Slope lg = slope(on[li] == 2 ? lfo : lf, li, syz, sz);
			const Vector3 lw(lg.x, lg.y, lg.z);
			const real_t l2 = lw.x * lw.x + lw.y * lw.y + lw.z * lw.z;
			ow[o + 3] = (double)l2 > 1e-8 ? (float)encode(-sm_normalized(lw)) : 1.0f;
		}
	}
	return out;
}
