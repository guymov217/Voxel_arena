extends Node
## The tutorial: every key of the fight a step of its own, each done the moment the player has
## done it (the longsword, the pot and the recruit arrive on their steps), the texts with the
## player's own keys; beating the recruit ends it. Then the forge's own lesson, step by step.

var t

func _steps(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func _next(tu, title: String, why: String) -> void:
	await _steps(130)
	t.eq(String(tu.view().title), title, why)

func test_the_tutorial_walks_through_every_key() -> void:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "headless": true, "tutorial": true, "training": {"enemy": "none", "respawn": false}, "seed": 2, "decrees": [], "hazards": [], "inventory": {}})
	var tu: Tutorial = m.tut
	var f: Fighter = m.me.f
	t.check(tu != null and tu.dummy != null, "a dummy to practise on")
	t.eq(String(tu.view().title), "Walk", "first, walking")
	t.check(String(tu.view().text).begins_with("W A S D"), "in the player's own keys: %s" % tu.view().text)
	await _steps(5)
	f.teleport(f.torso.global_position + Vector3(3, 0, 0))
	await _next(tu, "Look", "three metres: done")
	tu.s.turned = 3.0
	await _next(tu, "Jump and crouch", "looked all round")
	tu.s.jumps = 1
	tu.s.crouch_t = 1.0
	await _next(tu, "Look round you", "a jump and a crouch")
	tu.s.free_t = 1.0
	await _next(tu, "Swing", "the view round him")
	t.check(String(tu.view().text).contains(Loc.t("LEFT")), "the sword's button named: %s" % tu.view().text)
	tu.s.hits = 2
	await _next(tu, "Turn the blade", "two blows on the dummy")
	tu.s.twisted = 1.0
	await _next(tu, "Thrust", "the wheel rolled")
	t.check(String(tu.view().text).begins_with("Press C") and String(tu.view().text).contains("Hold C"), "the thrust's key, a stab and a hold: %s" % tu.view().text)
	tu.s.depth = 1.0
	await _next(tu, "Guard", "the blade driven out")
	tu.s.guard_t = 1.0
	await _next(tu, "Kick and shove", "the shield up")
	tu.s.kicks = 1
	await _next(tu, "Swap hands", "a kick")
	tu.s.swaps = 2
	await _next(tu, "Throw", "swapped and back: the sword in the right hand again")
	f.release("R")
	f.release("L")
	await _next(tu, "Fists", "both hands empty")
	tu.s.punches = 2
	await _next(tu, "Grab", "two punches")
	# By the dummy, a hand takes hold of him.
	var at: Vector3 = tu.dummy.torso.global_position
	f.teleport(Vector3(at.x, 0.0, at.z - 0.75))
	f.yaw = 0.0
	await _steps(20)
	var held = m.social.grab_person(m.me, {"grabHands": "R"})
	if held == null:
		held = m.social.grab_person(m.me, {"grabHands": "L"})
	t.check(f.holding != null, "a hand took hold of the dummy")
	await _next(tu, "Pick up", "he held him")
	m.social.let_go(f)
	var sword_name := str(Data.preset("longsword").get("name", ""))
	t.check(m.combat.loose_weapons.any(func(w): return is_instance_valid(w) and str(w.design.get("name", "")) == sword_name), "a longsword lies on the sand")
	f.equip("R", Data.preset("longsword"))
	await _next(tu, "Both hands", "picked up")
	f.toggle_grip()
	for i in 240:
		if f.two_handed:
			break
		await get_tree().physics_frame
	t.check(f.two_handed, "both hands on the hilt")
	await _next(tu, "Your kit", "both hands on it")
	t.eq(int(m.me.inventory.get(Tutorial.POT, 0)), 1, "a sand pot in the kit")
	m.throwables.use_item(m.me, 0)
	t.check(f.held_item != null, "1 takes the pot in hand")
	m.throwables.throw_held(m.me, {"look": {"yaw": f.yaw, "pitch": 0.0}})
	await _next(tu, "The crowd", "the pot thrown")
	tu.s.shows = 1
	for page in ["More keys", "Blood and breath", "The yard"]:
		await _next(tu, page, "a page to read: %s" % page)
		tu.s.read_t = 99.0
	await _next(tu, "A real fight", "the last step")
	t.check(tu.recruit != null and tu.recruit.alive, "a recruit steps in")
	var res := []
	m.finished.connect(func(r): res.append(r))
	tu.recruit.die("wounds")
	await _steps(140)
	t.check(tu.finished and not res.is_empty() and res[0].won, "beaten: the tutorial is over")
	t.check(String(tu.view().text).contains("forge"), "and the forge comes next")
	m.queue_free()
	await get_tree().physics_frame

## The forge's lesson: a card with one thing to do at a time, each done the moment it is done,
## a page to read turned with Next, to the end.
func test_the_forge_lesson_goes_step_by_step() -> void:
	var f = load("res://scripts/ui/forge.gd").new()
	add_child(f)
	f.free_build = true
	f.workshop = true
	f.open(Data.preset("gladius"), 0, func(_d, _c): pass)
	f.start_lesson()
	var ls: ForgeLesson = f.lesson
	t.check(ls != null and f.lesson_card != null, "a lesson, its card over the view")
	t.eq(String(ls.view().title), "Quick start", "first, the cards")
	f._pick_base(String(ForgeLib.BASES.keys()[0]))
	await _next(ls, "Twists", "a base picked")
	f._toggle_pick(String(f.dealt[0]))
	await _next(ls, "Shape by hand", "a twist taken")
	f._show_mode("voxels")
	await _next(ls, "Turn it round", "block by block")
	f.dragging = true
	for i in 10:
		f.orbit.x += 0.15
		await get_tree().process_frame
	f.dragging = false
	await _next(ls, "Closer", "the view turned round it")
	f.dist *= 0.5
	await _next(ls, "Fly", "drawn in")
	t.check(String(ls.view().text).begins_with("W A S D"), "flown on his own keys: %s" % ls.view().text)
	f.flown += 1.0
	await _next(ls, "Build", "flown")
	for k in 3:
		f.cells[Vector3i(9, 40 + k, 0)] = ["steel", "edge", -1]
	await _next(ls, "Take a block off", "three blocks laid")
	f.cells.erase(Vector3i(9, 42, 0))
	await _next(ls, "What a block does", "one taken off")
	f.cells[Vector3i(9, 42, 0)] = ["steel", "point", -1]
	await _next(ls, "Material", "a point built")
	f.cells[Vector3i(9, 43, 0)] = ["wood" if f.mat != "wood" else "iron", "blunt", -1]
	await _next(ls, "Mirror", "another stuff")
	f.mirror = not f.mirror
	await _next(ls, "Where it is held", "the mirror turned")
	f.design.grips = {"main": [0, 3, 0], "off": [0, 1, 0]}
	await _next(ls, "Undo", "the hand moved")
	f.redo_stack.append([f.cells.duplicate(true), f.design.duplicate(true)])
	await _next(ls, "The bars", "a change taken back")
	t.check(bool(ls.view().read) and f.lesson_bits.next.visible, "a page to read, with Next")
	ls.next()
	await _next(ls, "Gems", "Next turned it")
	ls.next()
	await _next(ls, "Swing it", "and the next")
	f.swing_t = 0.0
	await _next(ls, "Keep the design", "swung")
	f.saves += 1
	await _steps(130)
	t.check(ls.finished and bool(ls.view().done), "saved: the lesson is over")
	t.check(f.lesson_bits.next.visible and not f.lesson_bits.skip.visible, "a Close and nothing to skip")
	f._end_lesson()
	t.check(f.lesson == null, "and the card closes")
	f.queue_free()
	await get_tree().process_frame

## The menu's forge with the lesson (where the tutorial leads): on a plain gladius, the card up.
func test_the_menu_opens_the_forge_with_its_lesson() -> void:
	var menu = load("res://scripts/ui/menu.gd").new()
	add_child(menu)
	await get_tree().process_frame
	menu._workshop_forge(true)
	await get_tree().process_frame
	var forge = null
	for c in menu.get_children():
		if c.get("lesson") != null:
			forge = c
	t.check(forge != null, "the forge is open, with its lesson")
	if forge:
		t.eq(str(forge.design.get("name", "")), str(Data.preset("gladius").get("name", "")), "on a plain gladius")
		forge.queue_free()
	menu.queue_free()
	await get_tree().process_frame
