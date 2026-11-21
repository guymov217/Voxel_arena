extends Node
## A room between windows of this one computer (Net.local_room, MenuScript.room_scale/room_fps): they share one graphics card and
## the window in front takes nearly all of it, so the picture of both is lowered, and given back when the room is closed.
## A room between computers is never touched.

const MenuScript := preload("res://scripts/ui/menu.gd")

var t

func test_which_addresses_are_this_computer() -> void:
	for a in ["127.0.0.1", "127.1.2.3", "localhost", "LOCALHOST", "::1", "::ffff:127.0.0.1", " 127.0.0.1 "]:
		t.check(Net.is_this_computer(a), "'%s' is this computer" % a)
	for a in ["", "8.8.8.8", "192.0.2.77", "1.127.0.0", "10.1.2.3x", "steam", "::2"]:
		t.check(not Net.is_this_computer(a), "'%s' is another" % a)
	for a in IP.get_local_addresses():
		t.check(Net.is_this_computer(a), "its own address %s is this computer" % a)
		if a.contains("."):
			t.check(Net.is_this_computer("::ffff:" + a), "%s in its IPv6 dress too" % a)

func test_a_room_of_windows_lowers_the_picture_and_gives_it_back() -> void:
	var was_local: bool = Net.local_room
	var seen := [0]
	var count := func(): seen[0] += 1
	Net.local_room_changed.connect(count)
	Net.local_room = false
	Net._peer_local.clear()
	Net._set_local(true)
	t.check(Net.local_room and seen[0] == 1, "a room of this computer's windows is told once")
	Net._set_local(true)
	t.eq(seen[0], 1, "and not again for the same")
	# Two guests, one of them on this computer: the host's picture stays low until that one goes.
	Net._peer_local = {11: true, 12: false}
	Net._on_peer_disconnected(12)
	t.check(Net.local_room, "a guest of another computer leaves: the one on this computer is still there")
	Net._on_peer_disconnected(11)
	t.check(not Net.local_room and seen[0] == 2, "the last window of this computer goes: the picture is given back")
	Net._set_local(true)
	Net.leave()
	t.check(not Net.local_room, "leaving the room gives it back too")
	Net.local_room_changed.disconnect(count)
	Net.local_room = was_local

func test_the_lowered_picture_and_frame_rate() -> void:
	t.eq(MenuScript.room_scale(1.0, true), MenuScript.LOCAL_ROOM_SCALE, "a full picture, lowered")
	t.eq(MenuScript.room_scale(0.6, true), 0.6, "one already lower than that stays")
	t.eq(MenuScript.room_scale(1.0, false), 1.0, "a room between computers: untouched")
	t.eq(MenuScript.room_fps(0, true), MenuScript.LOCAL_ROOM_FPS, "no cap: capped")
	t.eq(MenuScript.room_fps(144, true), MenuScript.LOCAL_ROOM_FPS, "a high cap: lowered")
	t.eq(MenuScript.room_fps(30, true), 30, "a lower cap of his own stays")
	t.eq(MenuScript.room_fps(0, false), 0, "a room between computers: untouched")
	t.eq(MenuScript.room_fps(144, false), 144, "(his own cap)")

func test_the_picture_follows_the_room() -> void:
	var was_local: bool = Net.local_room
	var cap := Engine.max_fps
	var scale: float = get_tree().root.scaling_3d_scale
	var mode: int = get_tree().root.scaling_3d_mode
	var windowed := DisplayServer.get_name() != "headless"   # (headless: no frame rate cap to set)
	var st := {"renderScale": "1.0", "fpsCap": 144}
	Net.local_room = false
	MenuScript.apply_render_scale(st)
	MenuScript.apply_frame(st)
	t.check(absf(get_tree().root.scaling_3d_scale - 1.0) < 0.001, "alone: the whole picture")
	if windowed:
		t.eq(Engine.max_fps, 144, "alone: his own cap")
	Net.local_room = true
	MenuScript.apply_render_scale(st)
	MenuScript.apply_frame(st)
	t.check(absf(get_tree().root.scaling_3d_scale - MenuScript.LOCAL_ROOM_SCALE) < 0.001, "in a room of windows: the lowered picture")
	if windowed:
		t.eq(Engine.max_fps, MenuScript.LOCAL_ROOM_FPS, "in a room of windows: lowered")
	Net.local_room = false
	MenuScript.apply_render_scale(st)
	t.check(absf(get_tree().root.scaling_3d_scale - 1.0) < 0.001, "the room closed: given back")
	Net.local_room = was_local
	get_tree().root.scaling_3d_scale = scale
	get_tree().root.scaling_3d_mode = mode as Viewport.Scaling3DMode
	Engine.max_fps = cap
