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
	var yaw := [0.0]
	host.drive = func(_e):
		yaw[0] += 0.01   # (his view turns: he is no man at rest)
		return {"look": {"yaw": yaw[0], "pitch": 0.0}}
	var friend: Dictionary = m.entities.filter(func(e): return e.kind == "remote")[0]
	friend.f.teleport(Vector3(6.0, 0.0, 6.0))
	host.f.teleport(Vector3(6.0, 0.0, 4.5))   # (a pace and a half off him)
	Net.inputs[77] = PlayerInput.unpack(PlayerInput.pack({"look": {"yaw": 0.0, "pitch": 0.0}}))
	await _steps(300)
	t.check(not friend.get("hidle", false), "a man at rest within reach of one who is not does not sleep")
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

## Men who stand together, nothing ordered of any, let one another sleep (a room of friends stood round the gate is no room of men awake); the step one is
## ordered anything the others are awake within a few steps, and a man walking up to them wakes them as he comes.
func test_men_standing_together_all_sleep_and_wake_when_one_moves() -> void:
	var m := _yard([{"id": 77, "name": "Friend", "loadout": {"main": "axe"}}, {"id": 78, "name": "Other", "loadout": {"main": "gladius"}}])
	var host: Dictionary = m.me
	host.drive = func(_e): return {}
	var friends: Array = m.entities.filter(func(e): return e.kind == "remote")
	host.f.teleport(Vector3(6.0, 0.0, 6.0))
	friends[0].f.teleport(Vector3(7.6, 0.0, 6.0))   # (a pace and a half from him)
	friends[1].f.teleport(Vector3(6.8, 0.0, 7.4))
	Net.inputs[77] = PlayerInput.unpack(PlayerInput.pack({"look": {"yaw": 0.0, "pitch": 0.0}}))
	Net.inputs[78] = PlayerInput.unpack(PlayerInput.pack({"look": {"yaw": 0.0, "pitch": 0.0}}))
	await _steps(360)
	t.check(_asleep(host) and _asleep(friends[0]) and _asleep(friends[1]), "three men standing a pace and a half from each other, nothing ordered, all sleep")
	# One of them is ordered a key: the other two are awake within five steps (a blow takes longer to come).
	Net.inputs[77] = PlayerInput.unpack(PlayerInput.pack({"mz": 1.0, "look": {"yaw": PI, "pitch": 0.0}}))
	await _steps(6)
	t.check(not friends[0].get("hidle", false) and not host.get("hidle", false) and not friends[1].get("hidle", false), "one moves, the others are awake within six steps")
	Net.inputs.erase(77)
	Net.inputs.erase(78)
	m.queue_free()

## The same blow on a man asleep and on one awake (the way of sparing the host off and on): the trunk goes where it goes and he stands as the
## other does. What is struck is woken by the physics in the step of the blow, and his balance is seen to from the next: the blow's own effect
## (the first half second) is the same to a few centimetres. A second on, a staggering man is not the same man twice from one run to the next
## (a hundredth more or less in the shove and he has stepped back or not: the awake man twice gives 17 cm and 30 cm a second on).
func test_a_blow_on_a_man_asleep_is_what_it_is_on_a_man_awake() -> void:
	var tracks := {}
	for asleep in [false, true]:
		for shove in [400.0, 1000.0]:
			Match.human_idle_on = asleep
			var m := _yard([{"id": 77, "name": "Friend", "loadout": {"main": "axe"}}])
			var host: Dictionary = m.me
			host.drive = func(_e): return {}
			var friend: Dictionary = m.entities.filter(func(e): return e.kind == "remote")[0]
			host.f.teleport(Vector3(-9.0, 0.0, -5.0))
			friend.f.teleport(Vector3(6.0, 0.0, 6.0))
			Net.inputs[77] = PlayerInput.unpack(PlayerInput.pack({"look": {"yaw": 0.0, "pitch": 0.0}}))
			await _steps(330)
			t.check(_asleep(friend) == asleep, "he sleeps when the sleeping is on, and not when it is off (%s)" % str(asleep))
			var at: Vector3 = friend.f.torso.global_position
			friend.f.torso.apply_central_impulse(Vector3(shove, 0.0, 0.0))
			var track := []
			for i in 5:
				await _steps(24)
				track.append([friend.f.torso.global_position - at, friend.f.state])
			tracks["%s %s" % [str(asleep), str(shove)]] = track
			Net.inputs.erase(77)
			m.queue_free()
	Match.human_idle_on = true
	for shove in [400.0, 1000.0]:
		var awake: Array = tracks["false %s" % str(shove)]
		var slept: Array = tracks["true %s" % str(shove)]
		t.check((awake[0][0] as Vector3).length() > 0.2, "the blow of %.0f moves the man awake (%.2f m a fifth of a second on)" % [shove, (awake[0][0] as Vector3).length()])
		for i in 5:
			t.check(String(awake[i][1]) == "stand" and String(slept[i][1]) == "stand", "after a shove of %.0f he stands, awake and asleep, %d tenths of a second on" % [shove, (i + 1) * 2])
		for i in 2:
			var moved: float = (awake[i][0] as Vector3).length()
			var gap: float = (awake[i][0] as Vector3).distance_to(slept[i][0] as Vector3)
			t.check(gap < 0.03 + 0.08 * moved, "a shove of %.0f, %d tenths on: the trunk is %.1f cm from where it is awake (moved %.2f m)" % [shove, (i + 1) * 2, gap * 100.0, moved])

## What a man asleep costs the first answer of his hand: the steps from the mark of his hand going across to his weapon being 3 cm on, asleep and awake (the
## sparing off), each after a swing let go and left standing. The same, the median: the sleep is let come once the arms are at rest (Fighter.arms_settled; a
## man put to sleep with an arm still going back to its place is held where no man awake ever is, and answered a step later: 5 steps against 4, and the weapon
## 1.2 cm behind at the fourth). Woken, his bodies begin from rest, as those of a man awake who stood still do, and the same in every man in the yard, whoever hosts.
func test_a_man_woken_by_his_hand_answers_as_a_man_awake_does() -> void:
	var medians := {}
	var at4 := {}
	for asleep in [false, true]:
		Match.human_idle_on = asleep
		var m := Match.new()
		add_child(m)
		m.setup({"mode": "yard", "headless": true, "seed": 1, "decrees": [], "hazards": [], "loadout": {"main": "gladius", "off": ""}, "role": "host", "peers": []})
		var rest := {"mx": 0.0, "mz": 0.0, "look": {"yaw": 0.0, "pitch": 0.0}, "main": {"x": 0.1, "y": 0.15}}
		var swing := {"mx": 0.0, "mz": 0.0, "look": {"yaw": 0.0, "pitch": 0.0}, "main": {"x": 0.7, "y": 0.5}}
		m.probe_input = rest
		await _steps(300)
		var counts := []
		var fourths := []
		for rep in 5:
			m.probe_input = rest
			await _steps(200)
			var n_wait := 0
			while asleep and not bool(m.me.get("hidle", false)) and n_wait < 400:
				await get_tree().physics_frame
				n_wait += 1
			var w = m.me.f.weapons.get("R")
			t.check(bool(m.me.get("hidle", false)) == asleep, "he lies asleep when the sparing is on (%s)" % str(asleep))
			var p0: Vector3 = w.global_position
			m.probe_input = swing
			var n := 0
			var four := 0.0
			while n < 240:
				await get_tree().physics_frame
				n += 1
				if n == 4:
					four = (w.global_position - p0).length()
				if n >= 4 and (w.global_position - p0).length() > 0.03:
					break
			counts.append(n)
			fourths.append(four)
			m.probe_input = rest
			await _steps(120)
		counts.sort()
		fourths.sort()
		medians[asleep] = counts[counts.size() / 2]
		at4[asleep] = fourths[fourths.size() / 2]
		m.queue_free()
	Match.human_idle_on = true
	t.check(int(medians[true]) <= int(medians[false]), "woken by his hand, the weapon is 3 cm on in %d steps, a man awake's in %d" % [medians[true], medians[false]])
	t.check(absf(float(at4[true]) - float(at4[false])) < 0.008, "and at the fourth step it is %.1f cm on against %.1f for a man awake (under 0.8 cm between them)" % [float(at4[true]) * 100.0, float(at4[false]) * 100.0])

## A man whose arm is still going back to its place is not put to sleep (he would be woken where no man awake ever is, Fighter.arms_settled): he waits for
## it, with the time he has stood kept, and sleeps the step it is at rest.
func test_a_man_with_an_arm_still_going_is_let_sleep_only_when_it_is_at_rest() -> void:
	var m := _yard()
	var host: Dictionary = m.me
	var f: Fighter = host.f
	host.drive = func(_e): return {}
	f.teleport(Vector3(-9.0, 0.0, -5.0))
	await _steps(360)
	t.check(_asleep(host), "left standing, he sleeps")
	m._wake_sleeper(host, f)
	t.check(f.arms_settled(), "his arms are at rest")
	var fo := f.arm["R"].fore as VoxelPart
	var slept := false
	for i in 150:   # (a forearm kept going at 0.6 m/s on his trunk for a second and a quarter: more than half a second of standing still)
		fo.linear_velocity = f.torso.linear_velocity + Vector3(0.0, 0.0, 0.6)
		if i == 0:
			t.check(not f.arms_settled(), "an arm going at 0.6 m/s on his trunk is not at rest")
		await get_tree().physics_frame
		slept = slept or bool(host.get("hidle", false))
	t.check(not slept, "with an arm still going he is not let sleep, though he has stood still (%s)" % str(slept))
	await _steps(240)
	t.check(_asleep(host), "and he sleeps once it is at rest")
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
func test_a_man_winded_or_in_pain_is_let_sleep_only_when_it_has_passed() -> void:
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
	await _steps(10)   # (what the physics does not tell is looked at every eighth step)
	t.check(not friend.get("hidle", false), "his breath gone, he is awake")
	await _steps(120)
	t.check(not friend.get("hidle", false) and f.stamina > 20.0, "and awake while it comes back (%.0f of %.0f)" % [f.stamina, f.breath_cap()])
	var n := 0
	while not friend.get("hidle", false) and n < 1200:
		await _steps(12)
		n += 12
	t.check(friend.get("hidle", false) and float(friend.get("hstam", 0.0)) >= f.breath_cap() - 0.3, "he sleeps once it is full (%.1f s on; %.1f of %.1f)" % [n / 120.0, float(friend.get("hstam", 0.0)), f.breath_cap()])
	# A sting of pain (the yard staunches every wound each step, so the bleeding is not seen here; what runs down with the time is):
	# awake while it runs down, asleep when it has.
	f.pain = 0.5
	await _steps(10)
	t.check(not friend.get("hidle", false), "pain in him, he is awake")
	n = 0
	while (f.pain > 0.001 or not friend.get("hidle", false)) and n < 2400:
		await _steps(12)
		n += 12
	t.check(f.pain <= 0.001 and friend.get("hidle", false), "he sleeps when it has run down (%.1f s on)" % (n / 120.0))
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

## The rows a host sends of the men in the yard (the match makes them itself, every few steps: `snap_tick` is the tick of a man's last): a man
## asleep has not moved a hair, and his row is made 8 a second, not every time; a full snapshot (a late joiner's) has him always; a man awake
## has his every time.
func _row_ticks(m: Match, e: Dictionary, steps: int) -> int:
	var seen := {}
	for i in steps:
		await _steps(1)
		seen[int(e.get("snap_tick", -1))] = true
	return seen.size()

func test_a_man_asleep_has_his_row_8_a_second_and_one_awake_every_time() -> void:
	var m := _yard([{"id": 77, "name": "Friend", "loadout": {"main": "axe"}}])
	var host: Dictionary = m.me
	host.drive = func(_e): return {}
	var friend: Dictionary = m.entities.filter(func(e): return e.kind == "remote")[0]
	friend.f.teleport(Vector3(6.0, 0.0, 6.0))
	host.f.teleport(Vector3(-9.0, 0.0, -5.0))
	Net.inputs[77] = PlayerInput.unpack(PlayerInput.pack({"look": {"yaw": 0.0, "pitch": 0.0}}))
	await _steps(300)
	t.check(_asleep(friend), "he sleeps")
	var rows: int = await _row_ticks(m, friend, 120)
	t.check(rows >= 7 and rows <= 10, "asleep, his row was made %d times in a second (8 a second)" % rows)
	var full := 0
	for row in m.snapshot(true, 0):
		if int(row[0]) == int(friend.id):
			full += 1
	t.check(full == 1, "and a full snapshot has him")
	# Awake (a key held): his row is made every time the match makes the others'.
	Net.inputs[77] = PlayerInput.unpack(PlayerInput.pack({"mz": 1.0, "look": {"yaw": 0.0, "pitch": 0.0}}))
	await _steps(4)
	var awake: int = await _row_ticks(m, friend, 120)
	t.check(awake >= 30, "awake, his row was made %d times in a second (every few steps)" % awake)
	Net.inputs.erase(77)
	m.queue_free()

## His drawing rests when he sleeps (three frames after, so that it has caught up with where he lies) and is at once drawn again when he wakes.
func test_the_drawing_of_a_man_asleep_rests_and_wakes_with_him() -> void:
	Fighter.process_in_headless = true
	var m := _yard([{"id": 77, "name": "Friend", "loadout": {"main": "axe"}}])
	var host: Dictionary = m.me
	host.drive = func(_e): return {}
	var friend: Dictionary = m.entities.filter(func(e): return e.kind == "remote")[0]
	friend.f.teleport(Vector3(6.0, 0.0, 6.0))
	host.f.teleport(Vector3(-9.0, 0.0, -5.0))
	Net.inputs[77] = PlayerInput.unpack(PlayerInput.pack({"look": {"yaw": 0.0, "pitch": 0.0}}))
	await _steps(300)
	t.check(_asleep(friend) and friend.f.draw_rest, "asleep: his drawing is let rest")
	for i in 6:
		await get_tree().process_frame
	t.check(friend.f.draw_rest_ready, "and three frames on nothing of him is drawn")
	Net.inputs[77] = PlayerInput.unpack(PlayerInput.pack({"mz": 1.0, "look": {"yaw": 0.0, "pitch": 0.0}}))
	await _steps(3)
	await get_tree().process_frame
	t.check(not friend.f.draw_rest and not friend.f.draw_rest_ready, "a key held, he is drawn again at once")
	Net.inputs.erase(77)
	Fighter.process_in_headless = false
	m.queue_free()
