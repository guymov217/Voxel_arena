#include "voxel_core.h"

#include <gdextension_interface.h>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/defs.hpp>
#include <godot_cpp/godot.hpp>

#ifdef _WIN32
#include <windows.h>
#include <wchar.h>
#endif

using namespace godot;

#ifdef _WIN32
// Windows takes a process for idle, puts it on the efficiency cores at a low clock (EcoQoS) and may let its timers run coarse, when its window is not in front: a game
// run beside other windows (a host with the friends' windows on the same computer, a test with the browser busy beside it). The diagnostic's own measure of a core
// ran at two fifths of its speed so (0.51 against 1.15, the sixth report). The game asks not to be throttled: the process's own opt-out (SetProcessInformation, Windows
// 10 1709 and later: looked up where it is, nothing happens where it is not). A friend window (`--friend`, the playtest's other players run beside the host) is left
// as Windows has it: throttled, it takes less of the host's cores. Nothing the game computes depends on it.
static void keep_the_game_fast() {
	const wchar_t *line = GetCommandLineW();
	if (line != nullptr && wcsstr(line, L"--friend") != nullptr) {
		return;
	}
	typedef BOOL(WINAPI * SetProcessInformationFn)(HANDLE, int, LPVOID, DWORD);
	HMODULE kernel = GetModuleHandleA("kernel32.dll");
	if (kernel == nullptr) {
		return;
	}
	SetProcessInformationFn set_info = (SetProcessInformationFn)GetProcAddress(kernel, "SetProcessInformation");
	if (set_info == nullptr) {
		return;
	}
	struct PowerThrottling {
		ULONG version;
		ULONG control_mask;
		ULONG state_mask;
	} state;
	state.version = 1; // PROCESS_POWER_THROTTLING_CURRENT_VERSION
	state.control_mask = 0x1 | 0x4; // EXECUTION_SPEED | IGNORE_TIMER_RESOLUTION
	state.state_mask = 0; // neither is to be done to this process
	set_info(GetCurrentProcess(), 4 /* ProcessPowerThrottling */, &state, sizeof(state));
}
#endif

static void initialize_voxel_core(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
	GDREGISTER_CLASS(VoxelCore);
#ifdef _WIN32
	keep_the_game_fast();
#endif
}

static void uninitialize_voxel_core(ModuleInitializationLevel p_level) {
}

extern "C" {
GDExtensionBool GDE_EXPORT voxel_core_init(GDExtensionInterfaceGetProcAddress p_get_proc_address, const GDExtensionClassLibraryPtr p_library, GDExtensionInitialization *r_initialization) {
	GDExtensionBinding::InitObject init_obj(p_get_proc_address, p_library, r_initialization);
	init_obj.register_initializer(initialize_voxel_core);
	init_obj.register_terminator(uninitialize_voxel_core);
	init_obj.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);
	return init_obj.init();
}
}
