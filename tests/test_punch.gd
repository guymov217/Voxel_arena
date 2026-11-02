extends Node
## Fists and breath: a punch that lands is felt (the man rocked back, reeling, slow for a moment;
## a giant's fist more); empty hands come up into a boxer's guard; a few hard strokes no longer
## leave a man without breath.

var t

func _steps(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

## A fist landing on a man's head, driven by the combat as a contact would be: what it does to him.
func _punch(m: Match, att: Fighter, vic: Fighter, speed: float) -> Dictionary:
	var fist: VoxelPart = att.arm.R.fore
	var dir: Vector3 = (vic.head.global_position - fist.global_position).normalized()
	fist.linear_velocity = att.torso.linear_velocity + dir * speed
	# (The combat reads the bodies' speeds as they were at the start of the step.)
	m.combat.vel[fist.get_instance_id()] = [fist.linear_velocity, Vector3.ZERO]
	m.combat.vel[vic.head.get_instance_id()] = [vic.head.linear_velocity, Vector3.ZERO]
	att.jab_t["R"] = Fighter.JAB_TIME * 0.5
	var v0: Vector3 = vic.torso.linear_velocity
	var h: Dictionary = m.combat._blow({"att": fist, "vic": vic.head, "J": 0.0, "rank": 0, "type": "blunt", "mat": "", "box": {}, "p": vic.head.global_position - dir * 0.08})
	var out := {"hit": h, "stagger": vic.stagger, "daze": vic.daze_t}
	# (The push is the physics' to carry out, on its next step.)
	await get_tree().physics_frame
	out.push = (vic.torso.linear_velocity - v0).dot(Vector3(dir.x, 0, dir.z).normalized())
	return out

## User: every punch an enemy or the player takes must really be felt, in harm and in what it does
## to him (knockback, stun, stagger).
func test_a_punch_is_felt() -> void:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none", "respawn": false}, "headless": true, "seed": 3, "decrees": [], "hazards": [], "loadout": {"main": "", "off": ""}})
	var me: Fighter = m.me.f
	me.teleport(Vector3(0, 0, 0))
	var man = m.spawn_fighter({"kind": "npc", "name": "Bag", "loadout": {"main": "", "off": ""}, "team": Match.ENEMY_TEAM, "pos": Vector3(0, 0.02, 0.9), "yaw": PI})
	man.drive = func(_e): return {}
	await _steps(120)
	var r: Dictionary = await _punch(m, me, man.f, 7.0)
	t.check(not (r.hit as Dictionary).is_empty(), "the fist lands")
	t.check(float(r.hit.get("J", 0.0)) >= 20.0, "and lands hard (J %.1f)" % float(r.hit.get("J", 0.0)))
	t.check(float(r.push) > 0.3, "he is rocked back by it (%.2f m/s)" % float(r.push))
	t.check(float(r.stagger) > 0.25, "he reels (stagger %.2f)" % float(r.stagger))
	t.check(float(r.daze) > 0.15, "and for a moment his hands and feet are slow (%.2f s)" % float(r.daze))
	m.queue_free()
	await get_tree().physics_frame
	# A giant's fist on a man: harder, and it throws him further.
	var m2 := Match.new()
	add_child(m2)
	m2.setup({"mode": "training", "training": {"enemy": "none", "respawn": false}, "headless": true, "seed": 3, "decrees": [], "hazards": [], "loadout": {"main": "", "off": ""}})
	var me2: Fighter = m2.me.f
	me2.teleport(Vector3(0, 0, 0))
	var giant = m2.spawn_fighter({"kind": "npc", "name": "Big", "loadout": {"main": "", "off": ""}, "team": Match.ENEMY_TEAM, "pos": Vector3(0, 0.05, 2.4), "yaw": PI, "mods": {"bodyScale": 2.4}})
	giant.drive = func(_e): return {}
	await _steps(120)
	var rg: Dictionary = await _punch(m2, giant.f, me2, 7.0)
	t.check(float(rg.hit.get("J", 0.0)) > float(r.hit.get("J", 0.0)), "a giant's fist lands harder than a man's (J %.1f against %.1f)" % [float(rg.hit.get("J", 0.0)), float(r.hit.get("J", 0.0))])
	t.check(float(rg.push) > float(r.push), "and rocks him further")
	m2.queue_free()
	await get_tree().physics_frame

## With no weapon the fists come up into a boxer's guard whenever they are not being thrown; a
## weapon stays where it was last aimed (user: no weapon, he boxes, hands up in a guard).
func test_empty_hands_come_up_into_a_guard() -> void:
	var pi := PlayerInput.new()
	add_child(pi)
	pi.set_unarmed(true, true)
	pi.main = {"x": 1.2, "y": -0.8}
	pi.off = {"x": -1.0, "y": -0.6}
	for i in 60:
		pi.sample(1.0 / 60.0)
	t.check(absf(float(pi.main.y) - float(PlayerInput.GUARD_MAIN.y)) < 0.05 and absf(float(pi.off.y) - float(PlayerInput.GUARD_OFF.y)) < 0.05, "both fists up in the guard (%s, %s)" % [str(pi.main), str(pi.off)])
	pi.set_unarmed(false, false)
	pi.main = {"x": 1.2, "y": -0.8}
	for i in 60:
		pi.sample(1.0 / 60.0)
	t.check(absf(float(pi.main.x) - 1.2) < 1e-6, "a weapon hand stays where it was aimed")
	pi.queue_free()

## A man swinging hard has breath for a fight's exchanges: a dozen hard strokes of a sword and he
## is still standing well (user: three swings and his breath was gone, and he waited to be killed).
func test_hard_strokes_leave_him_his_breath() -> void:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none", "respawn": false}, "headless": true, "seed": 1, "decrees": [], "hazards": [], "loadout": {"main": "longsword", "off": "", "armor": ["helmet", "lorica"]}})
	var f: Fighter = m.me.f
	var st := {"t": 0.0}
	m.me.drive = func(_e):
		var ph := fmod(float(st.t), 1.0)
		var u := clampf(ph / 0.25, 0.0, 1.0) if ph < 0.25 else clampf(1.0 - (ph - 0.25) / 0.25, 0.0, 1.0)
		return {"main": {"x": -1.8 + 3.6 * u, "y": 0.3 + 0.5 * sin(u * PI)}, "off": {"x": -0.35, "y": 0.1}, "power": ph < 0.5, "look": {"yaw": f.yaw, "pitch": 0.0}}
	await _steps(120)
	for i in 120 * 12:
		await get_tree().physics_frame
		st.t = float(st.t) + 1.0 / 120.0
	t.check(f.stamina > 45.0, "a dozen hard strokes of a longsword in armour leave him %.0f breath" % f.stamina)
	m.queue_free()
	await get_tree().physics_frame
