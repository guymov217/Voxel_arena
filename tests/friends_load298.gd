extends Node
## The host's steps with a full room of friends (`-- --probe friends_load298 [--port N]`, headless; env FRIENDS (7), SECS (60), IDLE (1: the men
## who stand still sleep), ARM_LOD (1)): this game opens an Arena room, brings in FRIENDS friends' games (each a headless game of this project:
## FriendPilot walks the yard, goes into the stalls, picks a quarrel now and then), enters the yard and measures what its own steps cost
## for SECS seconds of the friends being friends. Prints the steps' wall time (mean, median, the worst hundredth, the worst), how many of the
## 120 a second were kept up, and how many of the men were asleep (Match._human_idle) on average.

const Kit := preload("res://tests/e2e_kit.gd")
const MenuScript := preload("res://scripts/ui/menu.gd")

var k: RefCounted
var menu: Node
var strip: FriendsStrip
var port := 17960
var last_us := 0
var times := PackedInt32Array()
var measuring := false

var span_us := 0       # what the nodes' steps took, from the first node's to the last's (the engine's own step and the waiting for the next are not in it)
var spans := PackedInt32Array()
class EndMark extends Node:
	var owner_: Node
	func _physics_process(_dt: float) -> void:
		var now := Time.get_ticks_usec()
		if owner_.measuring and owner_.last_us > 0:
			owner_.spans.append(now - owner_.last_us)

func _physics_process(_dt: float) -> void:
	var now := Time.get_ticks_usec()
	if measuring and last_us > 0:
		times.append(now - last_us)
	last_us = now

func _env(key: String, d: String) -> String:
	var v := OS.get_environment(key)
	return v if v != "" else d

func m() -> Match:
	return menu.match_

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	port = int(args[args.find("--port") + 1]) if args.has("--port") and args.size() > args.find("--port") + 1 else 17960
	process_physics_priority = -100000
	var em := EndMark.new()
	em.owner_ = self
	em.process_physics_priority = 100000
	add_child(em)
	Fighter.arm_lod_on = _env("ARM_LOD", "1") != "0"
	Match.human_idle_on = _env("IDLE", "1") != "0"
	k = Kit.new("friendsload", self)
	Save.data["name"] = "Aulus"
	menu = MenuScript.new()
	menu.backdrop_off = true
	add_child(menu)
	get_tree().create_timer(900.0).timeout.connect(func():
		if strip:
			strip.friends.kill_all()
		get_tree().quit(2))
	await k.pause(0.5)
	await _run()
	if strip:
		strip.friends.kill_all()
	await k.pause(0.5)
	get_tree().quit()

func _run() -> void:
	var n := int(_env("FRIENDS", "7"))
	var secs := float(_env("SECS", "60"))
	menu.show_screen("mp")
	await k.pause(0.3)
	menu._set_mp_kind(Net.KIND_ARENA)
	menu._host_room(func(): Net.host_enet(port))
	await k.pause(0.4)
	strip = FriendsStrip.new()
	get_tree().root.add_child(strip)
	strip.friends.port = port
	await k.pause(0.3)
	for i in n:
		strip.friends.add()
		await k.pause(1.5)
	var came: bool = await k.until(func(): return Net.peers.size() == n, 120.0, "friends in the room")
	print("FRIENDS joined %d of %d (%s)" % [Net.peers.size(), n, str(came)])
	Kit.press(Kit.button_named(menu, "LobbyEnter"))
	var yard: bool = await k.until(func(): return menu.in_yard() and m() != null and m().humans().size() == n + 1, 120.0, "the yard with all")
	print("FRIENDS in the yard: %s (%d humans)" % [str(yard), m().humans().size() if m() else 0])
	if not yard:
		return
	await k.pause(15.0)   # (they spread out)
	times.clear()
	spans.clear()
	measuring = true
	var t0 := Time.get_ticks_msec()
	var asleep_sum := 0.0
	var samples := 0
	while float(Time.get_ticks_msec() - t0) < secs * 1000.0:
		await k.pause(1.0)
		var asl := 0
		for e in m().humans():
			if e.get("hidle", false):
				asl += 1
		asleep_sum += asl
		samples += 1
	measuring = false
	var s := Array(times)
	s.sort()
	var mean := 0.0
	for v in s:
		mean += float(v)
	mean /= maxf(1.0, float(s.size()))
	var sp := Array(spans)
	sp.sort()
	var sp_mean := 0.0
	for v in sp:
		sp_mean += float(v)
	sp_mean /= maxf(1.0, float(sp.size()))
	print("FRIENDS SCRIPTS: the nodes' steps took %.2f ms on average (median %.2f, p99 %.2f, worst %.2f) of the 8.33 a step has" % [sp_mean / 1000.0, sp[sp.size() / 2] / 1000.0, sp[int(sp.size() * 0.99)] / 1000.0, sp[sp.size() - 1] / 1000.0])
	var arm_rest := 0
	for e in m().humans():
		if is_instance_valid(e.f):
			arm_rest += e.f.arm_skips
	print("FRIENDSLOAD n=%d men: a step (as the clock paces it, 8.33 at most) %.2f ms (median %.2f, p99 %.2f, worst %.2f) -> keeps up %.0f/120 steps; %.1f of %d men asleep on average; arm turns let rest %d" % [
		n + 1, mean / 1000.0, s[s.size() / 2] / 1000.0, s[int(s.size() * 0.99)] / 1000.0, s[s.size() - 1] / 1000.0, minf(120.0, 1000000.0 / maxf(1.0, mean)), asleep_sum / maxf(1.0, float(samples)), n + 1, arm_rest])
