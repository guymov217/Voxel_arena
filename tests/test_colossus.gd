extends Node
## Polyphemus, bare-handed: the one giant with no weapon (data: `colossus`) and the moves that suit
## it: the foot stamped on a man standing, a low kick through him, a fist brought down on his head, and
## a grab that takes him into the fist and throws him so that he is hurt where he lands. Every move is
## the physics' own: the contact, not a blow written in.

var t

## Polyphemus before one man, the man where he stands and the giant stood still till his move is
## begun (a bot left to itself walks round the man first, and begins from wherever it got to).
func _scene(gap: float) -> Dictionary:
	seed(5)
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none", "respawn": false, "immortal": true}, "headless": true, "seed": 3, "decrees": [], "hazards": [], "loadout": {"main": "", "off": ""}})
	var man: Fighter = m.me.f
	man.teleport(Vector3(0, 0, 0))
	m.me.drive = func(_e): return {"look": {"yaw": 0.0, "pitch": 0.0}}
	var spec: Dictionary = m.enemy_spec({"e": "giant", "boss": true}, 0, 1)
	spec.pos = Vector3(0, 0.1, gap)
	spec.yaw = PI
	var ge = m.spawn_fighter(spec)
	ge.drive = func(_e): return {}
	for i in 240:
		await get_tree().physics_frame
	ge.erase("drive")
	ge.bot.think = 99.0
	var out := {"m": m, "man": man, "g": ge.f, "bot": ge.bot, "hits": []}
	var g: Fighter = ge.f
	m.combat.hit.connect(func(h):
		if h.get("char") == man and h.get("attacker") == g:
			out.hits.append({"t": m.time, "J": float(h.get("J", 0.0)), "kick": bool(h.get("kick", false)), "punch": bool(h.get("punch", false)), "landing": bool(h.get("landing", false)), "part": String((h.part as VoxelPart).part_name) if h.get("part") is VoxelPart else "", "dir": h.get("dir", Vector3.ZERO)}))
	return out

func _move(sc: Dictionary, move: String) -> void:
	var bot = sc.bot
	bot.cmove = move
	bot.cmove_t = 0.0
	bot.cmove_fired = false
	bot.cmove_locked = false

func _run(seconds: float) -> void:
	for i in int(seconds * Engine.physics_ticks_per_second):
		await get_tree().physics_frame

func test_polyphemus_goes_bare_handed_and_he_alone() -> void:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none"}, "headless": true, "seed": 5})
	var poly: Fighter = m.spawn_fighter(m.enemy_spec({"e": "giant", "boss": true}, 0, 1)).f
	t.check(poly.weapons.get("R") == null and poly.weapons.get("L") == null, "Polyphemus has no weapon")
	t.check(bool(poly.mods.get("colossus", false)), "and fights as a colossus")
	for kind in ["cyclops", "minotaur", "troll", "titan"]:
		var f: Fighter = m.spawn_fighter(m.enemy_spec({"e": kind, "boss": true}, 0, 1)).f
		t.check(not bool(f.mods.get("colossus", false)), "%s is not a colossus" % kind)
		t.check(f.weapons.get("R") != null or f.weapons.get("L") != null, "%s still carries a weapon" % kind)
	m.queue_free()

## The foot comes down on a man on his feet, as on one lying: a kick that lands on him from above.
func test_the_colossus_stamps_on_a_man_standing() -> void:
	var sc := await _scene(2.1)
	_move(sc, "stamp")
	await _run(3.0)
	var kicks: Array = sc.hits.filter(func(h): return h.kick)
	t.check(not kicks.is_empty(), "the foot lands on the man (%d kick blows)" % kicks.size())
	if not kicks.is_empty():
		t.check(float(kicks[0].J) >= 10.0, "and it is a stamp, J %.0f" % float(kicks[0].J))
	sc.m.queue_free()

## A low kick swept through a man's middle: it lands, and it knocks him back from where he stood.
func test_the_colossus_punts_a_man_back_across_the_sand() -> void:
	var sc := await _scene(2.1)
	var man: Fighter = sc.man
	_move(sc, "punt")
	await _run(3.0)
	var kicks: Array = sc.hits.filter(func(h): return h.kick)
	t.check(not kicks.is_empty(), "the foot sweeps through the man (%d kick blows)" % kicks.size())
	var back := Vector2(man.torso.global_position.x, man.torso.global_position.z).length()
	t.check(back > 0.5, "and he is knocked back from where he stood (%.1f m)" % back)
	sc.m.queue_free()

## The fist drawn up over his head comes down on the man: a blow on the head from above.
func test_the_colossus_brings_a_fist_down_on_a_mans_head() -> void:
	var sc := await _scene(2.1)
	_move(sc, "crush")
	await _run(4.0)
	var fists: Array = sc.hits.filter(func(h): return h.punch)
	t.check(not fists.is_empty(), "the fist lands on the man (%d fist blows)" % fists.size())
	if not fists.is_empty():
		var h: Dictionary = fists[0]
		t.check(float(h.J) >= 15.0, "hard, J %.0f" % float(h.J))
		t.check((h.dir as Vector3).y < -0.2, "and from above (the blow's way down %.2f)" % (h.dir as Vector3).y)
	sc.m.queue_free()

## The grab: the man is taken into the fist (his head lies in its end, not a hand's breadth under
## it), the arm that holds him does not strike him, and the throw lets him go at speed to be hurt
## by what he lands on.
func test_the_colossus_takes_a_man_in_his_fist_and_throws_him() -> void:
	var sc := await _scene(2.13)
	var g: Fighter = sc.g
	var bot = sc.bot
	var man: Fighter = sc.man
	bot.grab_cool = 0.0
	bot.grab_reach = Bot.GRAB_REACH
	bot.hold_t = 0.0
	var held := false
	for i in int(4.0 * Engine.physics_ticks_per_second):
		await get_tree().physics_frame
		if g.holding != null:
			held = true
			break
	t.check(held, "the hand closes on the man")
	if held:
		bot.hold_move = "throw"
		await _run(0.4)
		var part: VoxelPart = g.holding.part if g.holding != null else null
		if part != null:
			t.check(Social.box_distance(part, g.hand_world("R")) < 0.02 * g.S, "he lies in the fist, not under it (%.2f m off)" % Social.box_distance(part, g.hand_world("R")))
		var struck := 0
		var released_at := -1.0
		for i in int(3.0 * Engine.physics_ticks_per_second):
			await get_tree().physics_frame
			if g.holding != null:
				bot.hold_move = "throw"
				struck = sc.hits.size()
			elif released_at < 0.0:
				released_at = sc.m.time
		t.eq(struck, 0, "no blow on a man while he is held")
		t.check(released_at > 0.0, "the throw lets him go")
		# On to where he lands.
		await _run(2.5)
		var landings: Array = sc.hits.filter(func(h): return h.landing)
		t.check(not landings.is_empty(), "and he is hurt where he comes down (%d landing blows)" % landings.size())
		if not landings.is_empty():
			t.check(float(landings[0].J) >= 8.0, "by the speed he was stopped from, J %.0f" % float(landings[0].J))
		t.check(man.torso.global_position.distance_to(g.torso.global_position) > 6.0, "a long way from the giant (%.1f m)" % man.torso.global_position.distance_to(g.torso.global_position))
	sc.m.queue_free()
