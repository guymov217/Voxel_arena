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
	t.check(KillCam.score_kill({"victim": "Gaius", "killer": "Marcus", "player": true}).score >= 15.0, "a plain kill of the player's is shown")
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
