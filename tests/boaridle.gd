extends Node
## What a beast does while close to a man who just stands there (test_beast_reactions: a boar
## stood by him 9 s without a blow landing): every half second its mode, distance, facing and
## whether its head is ready to strike. `-- --probe boaridle`; SPECIES (boar).

func _ready() -> void:
	var sp := OS.get_environment("SPECIES") if OS.get_environment("SPECIES") != "" else "boar"
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": sp, "immortal": true}, "headless": true, "seed": 7, "decrees": [], "hazards": [], "loadout": {"main": "", "off": ""}})
	m.me.drive = func(_e): return {}
	var b: Beast = null
	for e in m.entities:
		if e.f is Beast:
			b = e.f
	var me: Fighter = m.me.f
	var hits := [0]
	var tries := [0]
	m.combat.hit.connect(func(h): if h.get("attacker") == b and h.get("char") == me: hits[0] += 1)
	var was_strikes := 0
	for i in 25 * 120:
		await get_tree().physics_frame
		if b.strikes.size() > was_strikes:
			tries[0] += 1
		was_strikes = b.strikes.size()
		if i % 60 == 0:
			var to: Vector3 = me.torso.global_position - b.torso.global_position
			to.y = 0.0
			var d := to.length()
			var cur: float = b.torso.global_rotation.y
			var fwd := Vector3(sin(cur), 0, cos(cur))
			var reach: float = b.torso.half_ext.z + b.head.half_ext.z * 2.0 + 0.5
			print("t %4.1f  mode %-8s t %5.2f  dist %.2f (reach x1.2 %.2f)  facing %+.2f  head ready %s  strikes on now %d  blows landed %d  tries %d" % [i / 120.0, String(b.ai.mode), float(b.ai.t), d, reach * 1.2, fwd.dot(to.normalized()), str(b._ready_to_strike(b.head)), b.strikes.size(), hits[0], tries[0]])
	get_tree().quit()
