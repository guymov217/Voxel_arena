extends Node
## The yard with many men in it (#298: eight men cost the host more than a step has): the men who stand where they are, nothing ordered of
## them, sleep as the keepers do and are the men they were the step anything orders them, comes near them or touches them; and the arms of a
## man at rest, a guard held, are seen to every other step with the time of both, and every step the moment anything orders or strikes them.

var t

func _steps(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func _yard(peers := []) -> Match:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "yard", "role": "host", "headless": true, "seed": 1, "decrees": [], "hazards": [], "loadout": {"main": "gladius", "off": "scutum"}, "peers": peers})
	return m

func _entity_of(m: Match, f):
	return m.entities.filter(func(e): return e.f == f)[0]

func _asleep(e) -> bool:
	return e.get("hidle", false) and e.f.parts.all(func(p): return p.severed or p.sleeping)

func test_a_man_who_stands_with_nothing_ordered_sleeps_and_wakes_at_a_word() -> void:
	var was := Net.ping_ms
	var m := _yard([{"id": 77, "name": "Friend", "loadout": {"main": "axe"}}])
	var host: Dictionary = m.me
	host.drive = func(_e): return {}
	var friend: Dictionary = m.entities.filter(func(e): return e.kind == "remote")[0]
	host.f.teleport(Vector3(-9.0, 0.0, -5.0))
	friend.f.teleport(Vector3(6.0, 0.0, 6.0))
	Net.inputs[77] = PlayerInput.unpack(PlayerInput.pack({"look": {"yaw": 0.0, "pitch": 0.0}}))
	await _steps(360)
	t.check(_asleep(friend), "a friend who stands there, no key held, his view where it was, sleeps: every part of him asleep")
	t.check(_asleep(host), "and so does the host's own man, who is not driven")
	var y0: float = friend.f.torso.global_position.y
	await _steps(120)
	t.check(_asleep(friend) and friend.f.state == "stand" and absf(friend.f.torso.global_position.y - y0) < 0.003, "he stands as he stood, a second on")
	# One key: he is awake that very step and walks.
	var p0: Vector3 = friend.f.torso.global_position
	Net.inputs[77] = PlayerInput.unpack(PlayerInput.pack({"mz": 1.0, "look": {"yaw": 0.0, "pitch": 0.0}}))
	await _steps(2)
	t.check(not friend.get("hidle", false) and friend.f.parts.all(func(p): return p.severed or not p.sleeping), "a key held, he is awake in the step it comes (%s)" % str(friend.get("hidle", false)))
	await _steps(60)
	t.check(friend.f.torso.global_position.distance_to(p0) > 0.15, "and walking (%.2f m in half a second)" % friend.f.torso.global_position.distance_to(p0))
	# The view turned alone wakes him too: he turns with it.
	Net.inputs[77] = PlayerInput.unpack(PlayerInput.pack({"look": {"yaw": 0.0, "pitch": 0.0}}))
	await _steps(300)
	t.check(_asleep(friend), "let go of the key he is let sleep again")
	Net.inputs[77] = PlayerInput.unpack(PlayerInput.pack({"look": {"yaw": 1.0, "pitch": 0.0}}))
	await _steps(2)
	t.check(not friend.get("hidle", false), "his view turned, he is awake")
	Net.inputs.erase(77)
	m.queue_free()
	Net.ping_ms = was

func test_a_man_near_another_does_not_sleep_and_a_blow_wakes_him() -> void:
	var m := _yard([{"id": 77, "name": "Friend", "loadout": {"main": "axe"}}])
	var host: Dictionary = m.me
	host.drive = func(_e): return {}
	var friend: Dictionary = m.entities.filter(func(e): return e.kind == "remote")[0]
	friend.f.teleport(Vector3(6.0, 0.0, 6.0))
	host.f.teleport(Vector3(6.0, 0.0, 4.5))   # (a pace and a half off him)
	Net.inputs[77] = PlayerInput.unpack(PlayerInput.pack({"look": {"yaw": 0.0, "pitch": 0.0}}))
	await _steps(300)
	t.check(not friend.get("hidle", false) and not host.get("hidle", false), "two men within reach of each other do not sleep")
	host.f.teleport(Vector3(-9.0, 0.0, -5.0))
	await _steps(300)
	t.check(_asleep(friend), "the other gone, he sleeps")
	# A blow on his trunk (a thrown blade, a man walked into): the physics wakes what is touched and he is the man he was.
	friend.f.torso.apply_central_impulse(Vector3(30.0, 0.0, 0.0))
	await _steps(4)
	t.check(not friend.get("hidle", false), "touched, he is awake")
	await _steps(120)
	t.check(friend.f.alive and friend.f.state == "stand", "and he stands")
	Net.inputs.erase(77)
	m.queue_free()

func test_arms_at_rest_are_seen_to_every_other_step_and_every_step_when_ordered() -> void:
	Match.human_idle_on = false   # (the whole man awake: it is his arms that are looked at)
	var m := _yard()
	var host: Dictionary = m.me
	var f: Fighter = host.f
	var orders := [{"mz": 1.0, "look": {"yaw": 0.0, "pitch": 0.0}}]
	host.drive = func(_e): return orders[0]
	await _steps(240)
	var s0 := f.arm_skips
	await _steps(120)
	var share := float(f.arm_skips - s0) / 120.0
	t.check(share > 0.3 and share < 0.55, "walking about with the hands unordered, the arms are seen to every other step (%.0f%% of the steps not)" % (share * 100.0))
	# The marks of a hand move: seen to every step from the very step (and for a fifth of a second after).
	var s1 := f.arm_skips
	orders[0] = {"mz": 1.0, "look": {"yaw": 0.0, "pitch": 0.0}, "main": {"x": 0.4, "y": 0.3}, "off": {"x": -0.35, "y": 0.1}}
	await _steps(20)
	t.check(f.arm_skips - s1 == 0, "the marks of a hand moved, they are seen to every step from that step (%d skipped)" % (f.arm_skips - s1))
	# The button of a hand held: every step as long as it is.
	orders[0] = {"mz": 1.0, "look": {"yaw": 0.0, "pitch": 0.0}, "main": {"x": 0.4, "y": 0.3}, "off": {"x": -0.35, "y": 0.1}, "power": true, "thrust": 0.0}
	var s2 := f.arm_skips
	await _steps(120)
	t.check(f.arm_skips - s2 == 0, "the button of a hand held, they are seen to every step (%d skipped)" % (f.arm_skips - s2))
	# Let go and still, they are let rest again after a fifth of a second.
	orders[0] = {"mz": 0.0, "look": {"yaw": 0.0, "pitch": 0.0}, "main": {"x": 0.4, "y": 0.3}, "off": {"x": -0.35, "y": 0.1}}
	await _steps(30)
	var s3 := f.arm_skips
	await _steps(120)
	t.check(f.arm_skips - s3 > 30, "let go and still, they rest again (%d of 120 steps)" % (f.arm_skips - s3))
	# Struck: seen to every step at once, and for a while after.
	f.arm["R"].fore.apply_central_impulse(Vector3(0.0, 0.0, 40.0))
	f.jolt_t = f.time
	var s4 := f.arm_skips
	await _steps(60)
	t.check(f.arm_skips - s4 == 0, "struck, they are seen to every step for the half second after (%d skipped)" % (f.arm_skips - s4))
	Match.human_idle_on = true
	m.queue_free()

## A guard held is held as well at half the rate: where the hand and the elbow lie on the trunk after a few seconds of standing.
func test_a_guard_held_is_held_as_well() -> void:
	Match.human_idle_on = false
	var at := {}
	for lod in [false, true]:
		Fighter.arm_lod_on = lod
		var m := _yard()
		var host: Dictionary = m.me
		host.drive = func(_e): return {"mz": 0.0, "look": {"yaw": 0.0, "pitch": 0.0}}
		await _steps(360)
		var f: Fighter = host.f
		var yq := Quaternion(Vector3.UP, f.yaw).inverse()
		var hand: Vector3 = yq * (f.hand_world("R") - f.torso.global_position)
		var hand_l: Vector3 = yq * (f.hand_world("L") - f.torso.global_position)
		var tip: Vector3 = yq * (f.weapons.R.global_position - f.torso.global_position)
		at[lod] = [hand, hand_l, tip, f.arm_skips]
		m.queue_free()
		await _steps(2)
	Fighter.arm_lod_on = true
	Match.human_idle_on = true
	var d_r: float = (at[true][0] - at[false][0]).length()
	var d_l: float = (at[true][1] - at[false][1]).length()
	var d_t: float = (at[true][2] - at[false][2]).length()
	t.check(int(at[true][3]) > 100 and int(at[false][3]) == 0, "the arms were let rest in one and not in the other (%d, %d steps)" % [int(at[true][3]), int(at[false][3])])
	t.check(d_r < 0.01 and d_l < 0.01, "the hands lie where they lay, to a centimetre (%.1f, %.1f mm)" % [d_r * 1000.0, d_l * 1000.0])
	t.check(d_t < 0.02, "and the blade's tip within two (%.1f mm)" % (d_t * 1000.0))

## One killed as he sleeps (a rule of the yard, a blade): his parts are awake to fall, not left asleep where he stood.
func test_a_man_killed_asleep_is_not_left_standing() -> void:
	var m := _yard([{"id": 77, "name": "Friend", "loadout": {"main": "axe"}}])
	var host: Dictionary = m.me
	host.drive = func(_e): return {}
	var friend: Dictionary = m.entities.filter(func(e): return e.kind == "remote")[0]
	friend.f.teleport(Vector3(6.0, 0.0, 6.0))
	host.f.teleport(Vector3(-9.0, 0.0, -5.0))
	Net.inputs[77] = PlayerInput.unpack(PlayerInput.pack({"look": {"yaw": 0.0, "pitch": 0.0}}))
	await _steps(300)
	t.check(_asleep(friend), "he sleeps")
	friend.f.die("decap")
	await _steps(30)
	t.check(not friend.get("hidle", false) and not friend.f.alive, "killed, he is not asleep")
	# (A ragdoll takes its time to go down: looked at every tenth of a second for up to six, a man left standing would stay up.)
	var y: float = friend.f.torso.global_position.y
	var n := 0
	while y >= 0.6 and n < 720:
		await _steps(12)
		n += 12
		y = friend.f.torso.global_position.y
	t.check(y < 0.6, "and he has fallen (his trunk %.2f m off the sand, %.1f s on)" % [y, 0.25 + n / 120.0])
	Net.inputs.erase(77)
	m.queue_free()

## What `control` brings on a step at a time (the blood leaving a cut, the breath coming back) would stop with a man let sleep: he is let sleep once it has passed.
func test_a_man_bleeding_or_winded_is_let_sleep_only_when_it_has_passed() -> void:
	var m := _yard([{"id": 77, "name": "Friend", "loadout": {"main": "axe"}}])
	var host: Dictionary = m.me
	host.drive = func(_e): return {}
	var friend: Dictionary = m.entities.filter(func(e): return e.kind == "remote")[0]
	var f: Fighter = friend.f
	friend.f.teleport(Vector3(6.0, 0.0, 6.0))
	host.f.teleport(Vector3(-9.0, 0.0, -5.0))
	Net.inputs[77] = PlayerInput.unpack(PlayerInput.pack({"look": {"yaw": 0.0, "pitch": 0.0}}))
	await _steps(300)
	t.check(_asleep(friend), "he sleeps")
	# Winded: wakes at once (his breath is not what it was) and does not sleep until it is back.
	f.stamina = 20.0
	await _steps(4)
	t.check(not friend.get("hidle", false), "his breath gone, he is awake")
	await _steps(120)
	t.check(not friend.get("hidle", false) and f.stamina > 20.0, "and awake while it comes back (%.0f of %.0f)" % [f.stamina, f.breath_cap()])
	var n := 0
	while not friend.get("hidle", false) and n < 1200:
		await _steps(12)
		n += 12
	t.check(friend.get("hidle", false) and float(friend.get("hstam", 0.0)) >= f.breath_cap() - 0.3, "he sleeps once it is full (%.1f s on; %.1f of %.1f)" % [n / 120.0, float(friend.get("hstam", 0.0)), f.breath_cap()])
	# A cut: blood goes while it bleeds, and he sleeps when it has stopped.
	var blood0 := f.blood
	f.torso.bleed = 0.4
	await _steps(4)
	t.check(not friend.get("hidle", false), "a wound bleeding, he is awake")
	n = 0
	while (f.torso.bleed > 0.0 or not friend.get("hidle", false)) and n < 2400:
		await _steps(12)
		n += 12
	t.check(f.torso.bleed <= 0.0 and friend.get("hidle", false), "he sleeps when it has stopped (%.1f s on)" % (n / 120.0))
	t.check(f.blood < blood0, "and the blood it took went from him, he was not seen asleep with it (%.4f to %.4f)" % [blood0, f.blood])
	# At ease: the call itself.
	t.check(f.at_ease(), "nothing left in him to run down")
	f.pain = 0.5
	t.check(not f.at_ease(), "pain left in him is something running down")
	f.pain = 0.0
	f.wine_timer = 5.0
	t.check(not f.at_ease(), "so is a wine's drunkenness")
	f.wine_timer = 0.0
	Net.inputs.erase(77)
	m.queue_free()
