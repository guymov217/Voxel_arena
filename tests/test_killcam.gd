extends Node
## The kill cam (killcam.js): kills are scored, and the best is cut into a clip with the seconds
## before the blow and the aftermath.

var t

func test_kills_are_scored_for_style() -> void:
	var plain := KillCam.score_kill({"victim": "Gaius", "killer": "Marcus"})
	var head := KillCam.score_kill({"victim": "Gaius", "killer": "Marcus", "decap": true, "weapon": "gladius"})
	var punch := KillCam.score_kill({"victim": "Gaius", "killer": "Marcus", "unarmed": true})
	t.check(head.score > punch.score and punch.score > plain.score, "a head off beats a punch beats a plain kill")
	t.eq(String(head.caption), "Marcus took Gaius's head off with a gladius", "the caption says what happened")
	t.eq(String(KillCam.score_kill({"victim": "Gaius", "self": true}).caption), "Gaius managed to kill themselves", "and the embarrassing ones")

func test_the_best_kill_becomes_a_clip() -> void:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "duel", "headless": true, "killcam": true, "seed": 4, "decrees": [], "hazards": []})
	t.check(m.killcam != null, "the match records")
	for i in 120 * 3:
		await get_tree().physics_frame
	t.check(m.killcam.frames.size() >= 80, "three seconds on tape")
	var foe = m.enemies()[0].f
	foe.last_attacker = m.me.f
	foe.head.severed = true
	foe.die("decap")
	t.check(m.killcam.best.is_empty(), "the aftermath is not on tape yet")
	for i in 120 * 2:
		await get_tree().physics_frame
	t.check(not m.killcam.best.is_empty(), "the kill is cut into a clip")
	t.check(String(m.killcam.best.caption).contains("head off"), "a beheading: " + String(m.killcam.best.get("caption", "")))
	var fr: Array = m.killcam.best.frames
	t.check(float(fr[fr.size() - 1].t) - float(fr[0].t) > 3.5, "from before the blow to after it")
	t.check(m.killcam.has_clip(), "worth showing")
	m.queue_free()

## A foe beaten senseless (out of the fight, not dead) is on tape as a kill from the blow that
## did it; a plain kill of the player's is worth showing; the kill cam can be switched off; a
## guest tapes the kills the host tells him of.
func test_a_knockout_is_taped_and_the_kill_cam_can_be_off() -> void:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "duel", "headless": true, "killcam": true, "seed": 4, "decrees": [], "hazards": []})
	for i in 120 * 3:
		await get_tree().physics_frame
	var foe = m.enemies()[0].f
	foe.last_attacker = m.me.f
	m.last_hit_of[foe] = {"J": 30.0, "at": m.time - 0.5}
	m._tape_kill(foe, "out")
	for i in 120 * 2:
		await get_tree().physics_frame
	t.check(not m.killcam.best.is_empty() and String(m.killcam.best.caption).contains("senseless"), "out cold is a kill on tape (%s)" % m.killcam.best.get("caption", ""))
	t.check(m.killcam.has_clip(), "and worth showing")
	t.check(KillCam.score_kill({"victim": "Gaius", "killer": "Marcus"}).score >= 10.0, "a plain kill is shown when it is the best there was")
	m.queue_free()
	var st: Dictionary = Save.get_value("settings", {}).duplicate()
	var off := st.duplicate()
	off["killcam"] = false
	Save.set_value("settings", off)
	var m2 := Match.new()
	add_child(m2)
	m2.setup({"mode": "duel", "seed": 4, "decrees": [], "hazards": [], "headless": false})
	t.check(m2.killcam == null, "switched off in Settings: no kill cam")
	m2.queue_free()
	Save.set_value("settings", st)
	var m3 := Match.new()
	add_child(m3)
	m3.setup({"mode": "duel", "headless": true, "killcam": true, "seed": 4, "decrees": [], "hazards": []})
	for i in 120 * 3:
		await get_tree().physics_frame
	var e3 = m3.enemies()[0]
	m3.guest_message("kc", {"v": e3.id, "k": m3.me.id, "cause": "decap", "J": 40.0, "w": "Gladius", "th": false, "ago": 0.0})
	for i in 120 * 2:
		await get_tree().physics_frame
	t.check(not m3.killcam.best.is_empty() and String(m3.killcam.best.caption).contains(m3.me.f.display_name), "a guest tapes the host's kill (%s)" % m3.killcam.best.get("caption", ""))
	m3.queue_free()

## Online one kill is shown on every screen, the one the host names as the fight's best: a
## guest plays that one even if another scored higher on his own tape, and none if he has
## not got it.
func test_online_everyone_sees_the_hosts_pick() -> void:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "duel", "headless": true, "killcam": true, "seed": 4, "decrees": [], "hazards": []})
	for i in 120 * 3:
		await get_tree().physics_frame
	var foe = m.enemies()[0].f
	m.killcam.on_death(foe, "wounds", {"J": 10.0})
	m.killcam.on_death(m.me.f, "decap", {"J": 40.0}, foe)
	for i in 120 * 2:
		await get_tree().physics_frame
	t.eq(m.killcam.clips.size(), 2, "both kills on tape")
	t.check(m.killcam.best.victim == m.me.f, "on his own the beheading is the best")
	t.check(m.killcam.choose(foe) and m.killcam.best.victim == foe, "the host's pick is the one shown")
	t.check(not m.killcam.choose(null) and m.killcam.best.is_empty(), "and one not on tape: nothing")
	t.check(KillCam.score_kill({"victim": "A", "killer": "B", "player": true}).score == KillCam.score_kill({"victim": "C", "killer": "D"}).score, "the game picks by the kill, not by whose it is: a foe's kill counts the same")
	m.queue_free()

## After every round its own best kill is shown, then the tape starts afresh: the next round's
## replay is that round's best, not a better one from before.
func test_every_round_has_its_own_replay() -> void:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "duel", "headless": true, "killcam": true, "seed": 4, "decrees": [], "hazards": []})
	for i in 120 * 3:
		await get_tree().physics_frame
	var foe = m.enemies()[0].f
	m.killcam.on_death(foe, "decap", {"J": 40.0}, m.me.f)
	for i in 120 * 2:
		await get_tree().physics_frame
	t.check(m.killcam.has_clip(), "round one: the beheading on tape")
	await m._round_replay()
	t.check(m.killcam.clips.is_empty() and m.killcam.best.is_empty(), "shown, and the tape is fresh for round two")
	m.killcam.on_death(m.me.f, "wounds", {"J": 5.0}, foe)
	for i in 120 * 2:
		await get_tree().physics_frame
	t.check(m.killcam.has_clip() and m.killcam.best.victim == m.me.f, "round two's replay is round two's kill")
	m.queue_free()

## The wounds are on tape too: what a blow cut away is logged with its time, so the replay shows
## the man whole until the blow (it showed him as he ended, every wound already open).
func test_the_wounds_are_on_tape() -> void:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "duel", "headless": true, "killcam": true, "seed": 4, "decrees": [], "hazards": []})
	for i in 60:
		await get_tree().physics_frame
	var foe: Fighter = m.enemies()[0].f
	var th: VoxelPart = foe.by_name.thighL
	var n0 := th.alive_count
	foe.apply_hit(th, {"impulse": 40.0, "type": "edge", "hardness": 0.9, "sharpness": 0.9, "point": th.global_position + Vector3(th.half_ext.x, 0, 0), "dir": Vector3(-1, 0, 0), "axis": Vector3(0, 0, 1), "edge": Vector3(-1, 0, 0)})
	await get_tree().physics_frame
	t.check(th.alive_count < n0, "the blow cut voxels away")
	var logged: Array = m.killcam.vox_log.filter(func(ev): return ev.part == th)
	t.check(not logged.is_empty(), "and they are on the kill cam's tape with their time")
	# Put back for the replay, they are there again; taken again, gone.
	for ev in logged:
		th.restore_voxels(ev.idx)
	t.eq(th.alive_count, n0, "the thigh whole again for the replay")
	for ev in logged:
		th.remove_voxels(ev.idx, false, false)
	t.check(th.alive_count < n0, "and cut again at the blow")
	m.queue_free()

## The pieces knocked off go on tape with the bodies (a lump cut loose flies in the replay as it
## flew), and while the clip plays the HUD is off: the replay is seen whole, not through the eyes
## of a man with a blow to the head.
func test_flying_pieces_are_taped_and_the_replay_is_seen_whole() -> void:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "duel", "headless": true, "killcam": true, "seed": 4, "decrees": [], "hazards": []})
	for i in 30:
		await get_tree().physics_frame
	var foe = m.enemies()[0].f
	var arm: VoxelPart = foe.arm.R.upper
	var idx := []
	for i in mini(6, arm.fx.size()):
		idx.append(i)
	var ch := Chunk.spawn(arm, arm.remove_voxels(idx, false, false), Vector3.UP)
	t.check(ch != null, "a lump knocked off")
	for i in 30:
		await get_tree().physics_frame
	var last: Dictionary = m.killcam.frames[m.killcam.frames.size() - 1].xf
	t.check(last.has(ch.get_instance_id()), "and it is on the tape")
	var hud := Hud.new(m)
	add_child(hud)
	await get_tree().process_frame
	m.killcam.playing = true
	for i in 2:
		await get_tree().process_frame
	t.check(not hud.visible, "the HUD (blinded eye, swimming sight) is off while the clip plays")
	m.killcam.playing = false
	for i in 2:
		await get_tree().process_frame
	t.check(hud.visible, "and back after it")
	hud.queue_free()
	m.queue_free()

## While the kill cam plays, Esc and R are its own (Esc skips it): Esc opened the pause menu over
## it, and closing that unpaused the arena in the middle of the replay; R restarted the bout.
func test_the_kill_cam_keeps_esc_and_r_to_itself() -> void:
	var menu = load("res://scripts/ui/menu.gd").new()
	add_child(menu)
	await get_tree().process_frame
	menu.start({"mode": "duel", "decrees": [], "hazards": [], "headless": true, "killcam": true})
	await get_tree().process_frame
	var m0 = menu.match_
	t.check(m0.killcam != null, "the bout has its kill cam")
	menu.visible = false
	m0.killcam.playing = true
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	menu._unhandled_input(esc)
	t.check(menu.pause_layer == null, "no pause menu over the kill cam")
	var r := InputEventAction.new()
	r.action = "va_restart"
	r.pressed = true
	menu._unhandled_input(r)
	t.check(menu.match_ == m0, "and no new bout under it")
	m0.killcam.playing = false
	menu._unhandled_input(esc)
	t.check(menu.pause_layer != null, "after it, Esc pauses as ever")
	menu._toggle_pause()
	menu._end_match()
	menu.queue_free()
	get_tree().paused = false
	await get_tree().process_frame

## The skip key is shown on the kill cam, as bound ("E" by default).
func test_the_kill_cam_says_how_to_skip_it() -> void:
	var kc := KillCam.new(self)
	add_child(kc)
	t.eq(kc.skip_key(), "E", "E skips it")
	kc._overlay("Marcus took Gaius's head off")
	var said := kc.overlay.find_children("*", "Label", true, false).map(func(l): return String(l.text))
	t.check(said.any(func(x): return x.contains("E") and x.to_lower().contains("skip")), "and the kill cam says so (%s)" % [said])
	kc.queue_free()

## After the replay every body is where it lay before it, the fight over or going on, the clip
## played through or skipped (user: a hyena killed before the kill cam stood on its feet after
## it, left as the clip's last moment had it): beasts, a man beheaded, a giant, the player
## himself, a weapon on the sand; the game runs on after it and the dead stay down.
func test_the_dead_lie_where_they_fell_after_the_replay() -> void:
	var cases := [
		{"foe": "hyena", "cause": "wounds"},
		{"foe": "wolf", "cause": "wounds", "skip": true},
		{"foe": "boar", "cause": "wounds", "loose": true},
		{"foe": "foe:cyclops", "cause": "wounds"},
		{"foe": "foe:recruit", "cause": "decap"},
		{"foe": "lion", "cause": "wounds", "me": true},
	]
	for c in cases:
		var m := Match.new()
		add_child(m)
		m.setup({"mode": "training", "training": {"enemy": c.foe, "respawn": false, "difficulty": 0.3}, "headless": true, "killcam": true, "seed": 4, "decrees": [], "hazards": [], "loadout": {"main": "gladius", "off": ""}})
		for i in 120 * 2:
			await get_tree().physics_frame
		var foe: Fighter = m.enemies()[0].f
		var victim: Fighter = m.me.f if c.get("me", false) else foe
		var killer: Fighter = foe if victim == m.me.f else m.me.f
		var name_ := String(c.foe) + (" (the player killed)" if victim == m.me.f else "")
		var up_y := victim.torso.global_position.y
		var loose = null
		if c.get("loose", false):
			loose = m.spawn_loose_weapon(Data.preset("spear"), victim.torso.global_position + Vector3(0.8, 1.5, 0))
		victim.last_attacker = killer
		if c.cause == "decap":
			victim.head.severed = true
		victim.die(String(c.cause))
		for i in 120 * 4:
			await get_tree().physics_frame
		t.check(m.killcam.has_clip(), "%s: the kill is on tape" % name_)
		var before := {}
		for b in m.killcam._bodies():
			before[b] = (b as Node3D).global_transform
		var down_y := victim.torso.global_position.y
		var done := [false]
		m.killcam.play(func(): done[0] = true, true)
		var n := 0
		while not done[0] and n < 120 * 40:
			await get_tree().process_frame
			n += 1
			if c.get("skip", false) and n == 20:
				Input.action_press("va_kick")
			if c.get("skip", false) and n == 26:
				Input.action_release("va_kick")
		t.check(done[0], "%s: the replay ends (%d frames)" % [name_, n])
		t.check(not get_tree().paused and not m.killcam.playing, "%s: and the game goes on after it" % name_)
		var worst := 0.0
		var worst_of := ""
		for b in before:
			if is_instance_valid(b):
				var off: float = (b as Node3D).global_position.distance_to((before[b] as Transform3D).origin)
				if off > worst:
					worst = off
					worst_of = String(b.name)
		t.check(worst < 0.02, "%s: every body back where it lay before the replay (%.3f m off: %s)" % [name_, worst, worst_of])
		if loose != null and is_instance_valid(loose):
			t.check(before.has(loose), "%s: the weapon on the sand was in the replay too" % name_)
		for i in 120:
			await get_tree().physics_frame
		t.check(victim.torso.global_position.y < up_y * 0.75, "%s: down a second after it (trunk at %.2f m, %.2f standing, %.2f before the replay)" % [name_, victim.torso.global_position.y, up_y, down_y])
		m.queue_free()
		await get_tree().process_frame

## A fight left in the middle of its replay (Esc to the menu, or the next fight begun): the
## replay holds the game still and let go only at its end, so the game stayed frozen after it.
func test_a_match_left_mid_replay_leaves_the_game_running() -> void:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "foe:recruit", "respawn": false, "difficulty": 0.3}, "headless": true, "killcam": true, "seed": 4, "decrees": [], "hazards": [], "loadout": {"main": "gladius", "off": ""}})
	for i in 120 * 2:
		await get_tree().physics_frame
	var foe: Fighter = m.enemies()[0].f
	foe.last_attacker = m.me.f
	foe.die("wounds")
	for i in 120 * 4:
		await get_tree().physics_frame
	t.check(m.killcam.has_clip(), "the kill is on tape")
	m.killcam.play(func(): pass, true)
	for i in 10:
		await get_tree().process_frame
	t.check(get_tree().paused and m.killcam.playing, "the replay holds the game still")
	m.queue_free()
	for i in 3:
		await get_tree().process_frame
	t.check(not get_tree().paused, "left in the middle of it, the game goes on")
	get_tree().paused = false

## A pot thrown is on the tape, and kept after it shatters, hidden, for the replay to show it in
## flight (freed at once, it never was in the kill cam: user).
func test_a_thrown_pot_is_on_the_tape() -> void:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "duel", "headless": true, "killcam": true, "seed": 4, "decrees": [], "hazards": []})
	m.items.headless = false   # (its look made, as on a screen)
	var it: Dictionary = m.items.spawn("pot_fire", Vector3(0, 2, 0), Vector3(3, 2, 0), m.me.f)
	var n: Node3D = it.node
	t.check(n != null, "the pot has its look")
	for i in 30:
		await get_tree().physics_frame
	var id := n.get_instance_id()
	t.check(m.killcam.frames.any(func(fr): return fr.xf.has(id)), "it is on the tape in flight")
	m.items.remove(it)
	await get_tree().process_frame
	t.check(is_instance_valid(n) and not n.visible, "shattered, its look is kept hidden for the replay")
	t.check(m.items.ghosts.any(func(g): return g[0] == n), "among the things gone the replay still shows")
	m.queue_free()
