// The scripts' cost counted in instructions (tools/ir_profile/ir_profile.py puts this file into a SCRATCH copy of the extension and binds its methods; it is
// never part of the game's library). Run under valgrind's callgrind, which counts the same instructions whatever else the machine does:
//   secN(callable)   calls it inside a native function of its own name: callgrind's inclusive count of VoxelCore::secN is what the script function cost.
//   reg(k)           ends the region before it and begins region k if k is the one chosen (callgrind run with --collect-atstart=no).
//   ir_select(k)     writes out what the chosen region cost (a dump named "r<k> n<times it began>") and chooses the next; ir_zero() forgets the counts so far.
#include "voxel_core.h"

#include <cstdio>
#include <godot_cpp/variant/callable.hpp>
#include <valgrind/callgrind.h>

using namespace godot;

#define SEC(n) \
	__attribute__((noinline)) Variant VoxelCore::sec##n(const Callable &c) { \
		Variant r = c.call(); \
		__asm__ volatile(""); \
		return r; \
	}
IR_SECTIONS(SEC)

void VoxelCore::ir_zero() {
	CALLGRIND_ZERO_STATS;
}

static int ir_active = -1;
static bool ir_col = false;
static long long ir_n = 0;

void VoxelCore::reg(int k) {
	if (ir_col) {
		CALLGRIND_TOGGLE_COLLECT;
		ir_col = false;
	}
	if (k >= 0 && k == ir_active) {
		ir_n++;
		ir_col = true;
		CALLGRIND_TOGGLE_COLLECT;
	}
}

void VoxelCore::ir_select(int k) {
	if (ir_col) {
		CALLGRIND_TOGGLE_COLLECT;
		ir_col = false;
	}
	if (ir_active >= 0) {
		char b[64];
		snprintf(b, sizeof b, "r%d n%lld", ir_active, ir_n);
		CALLGRIND_DUMP_STATS_AT(b);
	}
	ir_active = k;
	ir_n = 0;
}
