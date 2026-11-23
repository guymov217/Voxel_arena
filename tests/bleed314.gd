extends Node
## #314: does a man bleed to death in every mode, alone and in a party? (`-- --probe bleed314`, one worker thread, --fixed-fps 120)
## For each mode a match is built with one human, and with two (a host and a friend), everyone but the humans is made to stand still
## (nobody else can kill him), and the first human is opened at the thighs, the upper arms and the trunk. What is printed: when he
## fell to death's door (if he did), when he died and of what.

const MODES := {
	"campaign": {"stage": 1},
	"coop": {"stage": 1},
	"duel": {}, "bo3": {}, "ffa": {}, "pvp": {}, "hunt": {}, "teams": {}, "king": {}, "emperor": {}, "hill": {}, "lastLimb": {},
	"endless": {"endless": {"seed": 11}},
	"training": {"training": {"enemy": "none", "respawn": false, "immortal": false}},
}

func _steps(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func _match(mode: String, opts: Dictionary, humans: int) -> Match:
	var m := Match.new()
	add_child(m)
	var o := {"mode": mode, "headless": true, "seed": 3, "decrees": [], "hazards": [], "loadout": {"main": "gladius", "off": ""}}
	o.merge(opts, true)
	if humans > 1:
		o["role"] = "host"
		o["peers"] = [{"id": 2, "name": "Friend", "loadout": {"main": "gladius"}}]
	m.setup(o)
	return m

func _try(mode: String, humans: int) -> String:
	var m := _match(mode, MODES[mode], humans)
	await _steps(40)
	var hs := m.entities.filter(func(e): return e.kind == "local" or e.kind == "remote")
	for e in m.entities:
		if e.kind != "local" and e.kind != "remote":
			e.erase("bot")
			e.drive = func(_e): return {}
	var me = m.me
	if me == null or not is_instance_valid(me.f):
		m.queue_free()
		await _steps(4)
		return "%-9s humans %d: no fighter for the host in this mode (he is not on the sand)" % [mode, humans]
	var f: Fighter = me.f
	var causes := []
	f.died.connect(func(_f, cause): causes.append(cause))
	var n_open := 0
	for p in f.parts:
		var pn := String(p.part_name)
		if pn.begins_with("thigh") or pn.begins_with("upperArm") or pn == "torso":
			p.artery = 5.0
			n_open += 1
	var dying_at := -1.0
	var died_at := -1.0
	var blood0 := f.blood
	for i in 120 * 50:
		await get_tree().physics_frame
		if f.dying > 0.0 and dying_at < 0.0:
			dying_at = float(i) / 120.0
		if not f.alive:
			died_at = float(i) / 120.0
			break
	var line := "%-9s humans %d (%d now): wounds %d, blood %.0f -> %.0f; " % [mode, humans, hs.size(), n_open, blood0, f.blood]
	if died_at >= 0.0:
		line += "DIED of '%s' at %.1f s" % [causes[0] if not causes.is_empty() else "?", died_at]
	else:
		line += "ALIVE after 50 s (state %s, dying %.1f)" % [f.state, f.dying]
	if dying_at >= 0.0:
		line += ", at death's door from %.1f s" % dying_at
	m.queue_free()
	await _steps(4)
	return line

func _ready() -> void:
	await _steps(2)
	var lines := []
	for mode in MODES:
		for humans in [1, 2]:
			var l: String = await _try(mode, humans)
			print("BLEED314 ", l)
			lines.append(l)
	get_tree().quit()
