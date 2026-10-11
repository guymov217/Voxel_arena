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
