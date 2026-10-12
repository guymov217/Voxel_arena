class_name Combat
extends Node
## Turns contacts into blows (combat.js): a weapon on a body part, a fist, a kick or a bite on
## someone, weapon on weapon (a clang that chips edges). Bodies report their contacts during the
## physics step; they are judged on the next one against the velocities going into the step
## that made them, since by then the solver has already stopped the blade.

signal hit(info: Dictionary)
signal clang(info: Dictionary)
signal chip(info: Dictionary)

const TYPE_RANK := {"point": 3, "edge": 2, "blunt": 1, "grip": 0}
const STRIKING := ["forearmR", "forearmL", "shinR", "shinL", "head"]

static var current: Combat = null

var fighters: Array = []      # Fighter and Beast nodes in the match
var loose_weapons: Array = [] # weapons nobody holds (thrown, dropped)
var pending: Array = []
var vel := {}
var cool := {}
var time := 0.0
var enabled := true
var chip_mult := 1.0             # Glass Weapons: every hit breaks something

func _enter_tree() -> void:
	current = self
	process_physics_priority = -100

func _exit_tree() -> void:
	if current == self:
		current = null

## Called from a body's _integrate_forces with its contacts.
func report(body: RigidBody3D, state: PhysicsDirectBodyState3D) -> void:
	if not enabled:
		return
	for i in state.get_contact_count():
		var other = state.get_contact_collider_object(i)
		if other == null:
			continue
		var bw := body is Weapon
		var ow := other is Weapon
		var bp := body is VoxelPart
		var op := other is VoxelPart
		if bp and ow:
			# A trap does not move under physics, so the part it meets reports the contact.
			if other.is_hazard:
				pending.append({"a": other, "b": body, "sa": state.get_contact_collider_shape(i), "sb": state.get_contact_local_shape(i), "p": state.get_contact_local_position(i), "J": state.get_contact_impulse(i).length()})
			continue # the weapon reports it
		if (bp and op) or (bw and ow):
			if body.get_instance_id() > other.get_instance_id():
				continue
		if not (bw or (bp and op)):
			continue
		pending.append({"a": body, "b": other, "sa": state.get_contact_local_shape(i), "sb": state.get_contact_collider_shape(i), "p": state.get_contact_local_position(i), "J": state.get_contact_impulse(i).length()})

func _physics_process(dt: float) -> void:
	time += dt
	var hits := process_contacts(dt)
	for h in hits:
		if h.kind == "hit":
			hit.emit(h)
		else:
			chip.emit(h)
	record_velocities()

func record_velocities() -> void:
	vel.clear()
	for f in fighters:
		if not is_instance_valid(f):
			continue
		for p in f.parts:
			vel[p.get_instance_id()] = [p.linear_velocity, p.angular_velocity]
		for w in f.weapons.values():
			if w:
				_record(w)
	loose_weapons = loose_weapons.filter(func(w): return is_instance_valid(w))
	for w in loose_weapons:
		_record(w)

func _record(w: Weapon) -> void:
	vel[w.get_instance_id()] = [w.linear_velocity, w.angular_velocity]
	if w.chain_head:
		vel[w.chain_head.get_instance_id()] = [w.chain_head.linear_velocity, w.chain_head.angular_velocity]

func _vel_at(body: RigidBody3D, p: Vector3) -> Vector3:
	if body is Weapon and body.is_hazard:
		return body.hazard_vel + body.hazard_spin.cross(p - body.global_position)
	var v = vel.get(body.get_instance_id())
	var com := body.global_transform * body.center_of_mass
	if v == null:
		return body.linear_velocity + body.angular_velocity.cross(p - com)
	return v[0] + v[1].cross(p - com)

func _lin(body: RigidBody3D) -> Vector3:
	var v = vel.get(body.get_instance_id())
	return v[0] if v != null else body.linear_velocity

func _cooldown(key: String, J: float, t: float) -> bool:
	var c = cool.get(key)
	if c != null and time - c[0] < t and J < c[1] * 1.6:
		return false
	cool[key] = [time, J]
	return true

func process_contacts(dt: float) -> Array:
	var groups := {}
	for c in pending:
		var a = c.a
		var b = c.b
		if not is_instance_valid(a) or not is_instance_valid(b):
			continue
		if a is Weapon and b is Weapon:
			if c.J <= 1.2:
				continue
			var k := "clang:%d:%d" % [a.get_instance_id(), b.get_instance_id()]
			var g = groups.get(k)
			if g == null or c.J > g.J:
				groups[k] = {"clang": true, "a": a, "b": b, "sa": c.sa, "sb": c.sb, "p": c.p, "J": c.J}
			continue
		var att = null
		var vic = null
		var att_shape := -1
		if a is Weapon and b is VoxelPart:
			att = a; vic = b; att_shape = c.sa
		elif a is VoxelPart and b is VoxelPart and (_is_club(a) or _is_club(b)):
			# A severed limb swung or thrown like a club.
			if _is_club(a) and not _is_club(b):
				att = a; vic = b
			elif _is_club(b) and not _is_club(a):
				att = b; vic = a
			else:
				continue
			if vic.fighter == att.wielder or vic.fighter == att.thrown_by:
				continue
		elif a is VoxelPart and b is VoxelPart:
			if a.fighter == b.fighter:
				continue
			var sa := _lin(a).length()
			var sb := _lin(b).length()
			if sa >= sb:
				att = a; vic = b
			else:
				att = b; vic = a
			if not (STRIKING.has(att.part_name) or att.def.get("bite", false) or att.def.get("point", false)):
				continue
			if att.fighter.state != "stand" or not att.fighter.alive or att.severed:
				continue
			if att.fighter.kind != "beast" and not att.def.get("bite", false):
				var n: String = att.part_name
				if n.begins_with("shin") and not att.fighter.kick_timer > 0.0:
					continue
				var own: float = (_lin(att) - _lin(att.fighter.torso)).length()
				if n.begins_with("forearm") and own < (1.5 if att.fighter.jab_t[n.right(1)] > 0.0 else 2.5):
					continue
				if n == "head" and own < 3.0:
					continue
		else:
			continue
		if vic.severed and not vic.fighter.alive and att is VoxelPart:
			continue
		var key := "%d:%d" % [att.get_instance_id(), vic.get_instance_id()]
		var rank := 0
		var typ := "blunt"
		var mat := ""
		var box := {}
		if att is Weapon:
			box = att.box_for_shape(att_shape)
			typ = box.get("type", "blunt")
			mat = box.get("mat", "wood")
			rank = TYPE_RANK.get(typ, 0)
		var g2 = groups.get(key)
		if g2 == null:
			groups[key] = {"att": att, "vic": vic, "J": c.J, "rank": rank, "type": typ, "mat": mat, "box": box, "p": c.p}
		else:
			g2.J += c.J
			if rank > g2.rank:
				g2.rank = rank; g2.type = typ; g2.mat = mat; g2.box = box; g2.p = c.p
	pending.clear()
	var out := []
	for g in groups.values():
		if g.get("clang", false):
			_clang(g, out)
			continue
		var h := _blow(g)
		if not h.is_empty():
			out.append(h)
	return out

func _clang(g: Dictionary, out: Array) -> void:
	var a: Weapon = g.a
	var b: Weapon = g.b
	var ba := a.box_for_shape(g.sa)
	var bb := b.box_for_shape(g.sb)
	var ha: float = Data.material(ba.get("mat", "wood")).get("hardness", 0.5)
	var hb: float = Data.material(bb.get("mat", "wood")).get("hardness", 0.5)
	clang.emit({"p": g.p, "J": g.J, "metal": ha + hb})
	if not _cooldown("clang:%d" % a.get_instance_id(), g.J, 0.12):
		return
	for pair in [[a, ba, ha, hb], [b, bb, hb, ha]]:
		var w: Weapon = pair[0]
		if pair[1].is_empty():
			continue
		var idx := w.voxel_near(pair[1], g.p)
		# Steel on steel takes the edge off both blades, the harder the other the more.
		w.wear_edge(minf(0.05, g.J * pair[3] * 0.0007))
		var k := w.knock(idx, Weapon.chip_score(g.J * chip_mult, pair[2], pair[3]))
		if not k.is_empty():
			out.append({"kind": "chip", "weapon": w, "indices": k.indices, "voxels": k.voxels, "p": g.p, "broke": k.broke})

func _blow(g: Dictionary) -> Dictionary:
	var vic: VoxelPart = g.vic
	var vic_char = vic.fighter
	var p: Vector3 = g.p
	var att = g.att
	var is_weapon: bool = att is Weapon
	var rel := _vel_at(att, p) - _vel_at(vic, p)
	var speed := rel.length()
	if is_weapon and att.holder == null and not att.thrown_t > 0.0 and not att.is_hazard:
		return {}
	var club: bool = not is_weapon and _is_club(att)
	var kick: bool = not is_weapon and not club and att.part_name.begins_with("shin") and att.fighter.kick_timer > 0.0
	var bite: bool = not is_weapon and not club and (att.def.get("bite", false) or att.def.get("point", false))
	var punch: bool = not is_weapon and not club and not bite and not kick
	if speed < (2.2 if is_weapon else (1.5 if kick else 2.0)):
		return {}
	var jabbing: bool = punch and att.fighter.jab_t.get(att.part_name.right(1), 0.0) > 0.0
	var m_eff: float
	if is_weapon or club:
		m_eff = 1.0 + 0.874 * pow(maxf(0.05, att.mass), 0.6)
	else:
		m_eff = 5.0 if bite else (4.5 if kick else (3.2 if jabbing else 2.4))
	var cap: float
	if is_weapon:
		cap = 70.0
	elif club:
		cap = 40.0
	elif bite:
		cap = float(att.fighter.get("bite_power")) if att.fighter.get("bite_power") != null else 45.0
		if att.def.get("claw", false):
			cap *= 1.4   # a swipe has the whole foreleg and shoulder behind it
	else:
		cap = 30.0 if kick else (22.0 if jabbing else 17.0)
	var J := minf(cap, maxf(g.J, m_eff * speed))
	var heavy := 0.0
	if is_weapon and att.is_hazard:
		J = minf(40.0, maxf(J, 6.0 * speed))
	if is_weapon and att.holder:
		var hv: Vector3 = _lin(att.holder.torso)
		var sv := _vel_at(att, p) - hv
		var swing := sv.length()
		var vt: Vector3 = _lin(vic_char.torso) if vic_char.get("torso") else hv
		var closing := rel.normalized()
		var vic_into := maxf(0.0, -(_vel_at(vic, p) - vt).dot(closing))
		var w_into := maxf(0.0, sv.dot(closing))
		if vic_into > w_into:
			J *= maxf(0.25, w_into / vic_into)
		if att.holder.state != "stand":
			swing = 0.0
		if swing < 1.5:
			J = minf(J, m_eff * speed * 0.5)
		J = minf(J, m_eff * speed * 1.4)
		J *= 0.15 + 0.85 * minf(1.0, swing / 3.5)
		J *= 0.75 + 0.25 * minf(2.4, swing / 4.0)
		heavy = clampf((swing - 4.0) / 6.0, 0.0, 1.0)
		# A thrust is the whole body behind the point, not a hand's speed: driven home along the
		# blade it lands far harder than its speed says (the web game's lunge).
		var t_side: String = "R" if att.holder.weapons.R == att else "L"
		var th: float = float(att.holder.thrust_amt.get(t_side, 0.0)) if "thrust_amt" in att.holder else 0.0
		if th > 0.3 and g.type == "point":
			var along := absf(closing.dot(PD.quat_of(att) * Vector3.UP))
			if along > 0.5:
				J = maxf(J, minf(55.0, (12.0 + 10.0 * th) * along * minf(1.0, swing / 2.0 + 0.4))) * (1.0 + 0.6 * th * along)
				heavy = maxf(heavy, 0.4 * th)
	elif is_weapon and att.thrown_t > 0.0 and not att.is_hazard:
		# Thrown: the blow is its momentum, in proportion to how hard it was thrown (the speed
		# it lands at) and to how heavy it is; a dagger stings, a hammer flattens.
		J = minf(90.0, (0.5 + att.mass) * speed * 0.95)
		heavy = clampf((att.mass * speed - 20.0) / 40.0, 0.0, 1.0)
	if is_weapon:
		var key_name := _preset_key(att.design)
		J *= float(att.design.get("dmgScale", Data.damage_tuning.get(key_name, 1.0)))
	if J < (4.0 if is_weapon else 3.0):
		return {}
	var key := "%d:%d" % [att.get_instance_id(), vic.get_instance_id()]
	if not _cooldown(key, J, 0.14):
		return {}
	if not bite and not _cooldown("blow:%d:%d" % [att.get_instance_id(), vic_char.get_instance_id()], J, 0.32):
		return {}
	if bite and not _cooldown("bite:%d" % att.get_instance_id(), J, 0.45):
		return {}
	var dir := rel.normalized()
	var typ := "blunt"
	var hardness := 0.3
	var sharpness := 0.0
	var axis := dir
	var edge := Vector3.ZERO
	var attacker = null
	var thrown := false
	if is_weapon:
		attacker = att.holder if att.holder else att.thrower
		thrown = att.holder == null and att.thrown_t > 0.0
		typ = "blunt" if g.type == "grip" else g.type
		hardness = Data.material(g.mat).get("hardness", 0.5)
		sharpness = float(att.design.get("sharpness", 0.0)) * att.keenness()
		var q := PD.quat_of(att)
		axis = q * Vector3.UP
		edge = q * Vector3.RIGHT
		if typ == "point" and dir.dot(axis) < 0.0:
			axis = -axis
	elif club:
		hardness = 0.4
		attacker = att.wielder if att.wielder else att.thrown_by
		thrown = att.wielder == null
	elif bite and att.def.get("claw", false):
		# A paw's claws rake like knives: a cut along the swing, as deep as the blow drives it.
		typ = "edge"
		hardness = 0.9
		sharpness = 0.95
		edge = dir
		axis = PD.quat_of(att) * Vector3(0, -1, 0)
		attacker = att.fighter
	elif bite:
		typ = "point"
		hardness = 0.9
		sharpness = 1.0
		attacker = att.fighter
	else:
		attacker = att.fighter
	if attacker == vic_char:
		return {}
	var was_alive: bool = vic_char.alive
	# A bite takes a mouthful: the teeth close on a lump the size of the jaws, and tear it out.
	var crush := minf(0.11, (0.035 + J * 0.0012) * sqrt(float(att.fighter.S))) if bite and J > 6.0 and not att.def.get("claw", false) else 0.0
	var res: Dictionary = vic_char.apply_hit(vic, {"impulse": J, "type": typ, "hardness": hardness, "sharpness": sharpness, "point": p, "dir": dir, "axis": axis, "edge": edge, "heavy": heavy, "thrown": thrown, "serrated": is_weapon and att.design.get("serrated", false), "crush": crush})
	if bite and att.fighter.has_method("bit"):
		att.fighter.bit(att, vic, res, dir)
	if attacker:
		vic_char.last_attacker = attacker
	# A thrown blade that lands edge-on, or a point that lands point first, and bites deep
	# enough stays in the wound (combat.js).
	if thrown and is_weapon and not vic.severed and J > 9.0:
		var keen: float = hardness * sharpness
		if keen > 0.4 and (g.type == "point" or (g.type == "edge" and not res.get("slid", false))) and att.has_method("impale") and att.impale(vic_char, vic, p):
			res.impaled = true
	if punch and not vic.severed:
		vic.bleed += J * (0.05 if vic == vic_char.head else 0.015)
		if vic == vic_char.head:
			vic_char.concussion = minf(1.0, vic_char.concussion + J * 0.012)
		vic.apply_central_impulse(Vector3(dir.x, dir.y * 0.5, dir.z) * J * 0.7 * vic_char.MS)
	if kick and not vic.severed and vic_char.get("torso"):
		var m := 260.0 if att.fighter.mods.get("superKick", false) else minf(120.0, J * 6.0)
		vic_char.torso.apply_central_impulse(Vector3(dir.x * m, 10.0, dir.z * m))
		vic_char.stagger = minf(1.0, vic_char.stagger + 0.25)
		var lv: Vector3 = vic_char.torso.linear_velocity
		var sweep: float = (0.35 if Vector2(lv.x, lv.z).length() > 0.8 else 0.0) + (0.35 if vic_char.stamina < 30.0 else 0.0) + 0.3 * vic_char.stagger
		if vic.def.get("leg", false) and vic_char.state == "stand" and randf() < sweep:
			vic_char.fall(1.2)
			res.tripped = true
	var chip := {}
	if is_weapon and not g.box.is_empty():
		var vh := 0.5
		var idx: int = att.voxel_near(g.box, p)
		var mat_h: float = Data.material(g.mat).get("hardness", 0.5)
		# Every cut and stab blunts the edge a little (bone, armour, the sand of a fall).
		if typ != "blunt":
			att.wear_edge(minf(0.03, J * 0.00028 * (2.0 if res.get("armor", false) else 1.0)))
		var brittle: float = float(Data.material(g.mat).get("brittle", 0.0))
		# A blow tires the metal where it lands even when nothing gives (a brittle blade more).
		var k: Dictionary = att.knock(idx, Weapon.chip_score(J * maxf(0.25, brittle) * chip_mult, mat_h, vh))
		if not k.is_empty():
			chip = {"indices": k.indices, "voxels": k.voxels, "broke": k.broke}
	return {"kind": "hit", "att_part": att if not is_weapon else null, "p": p, "dir": dir, "J": J, "type": typ, "mat": g.mat, "punch": punch, "kick": kick, "bite": bite, "weapon": att if is_weapon else null, "char": vic_char, "part": vic, "attacker": attacker, "res": res, "killed": was_alive and not vic_char.alive, "chip": chip, "thrown": thrown}

static func _is_club(p) -> bool:
	return p is VoxelPart and p.severed and (p.wielder != null or p.thrown_t > 0.0)

static func _preset_key(design: Dictionary) -> String:
	for k in Data.presets:
		if Data.presets[k].get("name") == design.get("name"):
			return k
	return ""
