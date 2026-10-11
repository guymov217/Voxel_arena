class_name Items
extends Node3D
## Things in flight or lying about that are not weapons (items.js): pots, arrows, bolts, darts,
## rocks, nets, food the crowd throws, banana peels, a cheese wheel. Simple ballistic objects
## outside the physics world, walked in short steps so a fast arrow cannot pass through a body.
## Events go to `on_event` (throwables.gd decides what they do).

const RADIUS := 15.0
const TYPES := {
	"bread": {"size": 0.16}, "wine": {"size": 0.18}, "tomato": {"size": 0.1}, "banana": {"size": 0.12}, "coin": {"size": 0.06},
	"rock": {"size": 0.12, "projectile": true}, "net": {"size": 0.3, "projectile": true},
	"pot_thunder": {"size": 0.16, "projectile": true, "pot": 0x6a4a8a}, "pot_nail": {"size": 0.16, "projectile": true, "pot": 0x5b5f66},
	"pot_sand": {"size": 0.16, "projectile": true, "pot": 0xd8c08a}, "pot_fire": {"size": 0.16, "projectile": true, "pot": 0xff7a1a},
	"pot_acid": {"size": 0.16, "projectile": true, "pot": 0x8fd43a}, "pot_bees": {"size": 0.18, "projectile": true, "pot": 0xe8b830},
	"pot_caltrops": {"size": 0.14, "projectile": true, "pot": 0x444444}, "pot_goat": {"size": 0.2, "projectile": true, "pot": 0x8b5a2b},
	"pot_bola": {"size": 0.14, "projectile": true}, "pot_oil": {"size": 0.18, "projectile": true, "pot": 0x6b7a2a},
	"pot_garum": {"size": 0.16, "projectile": true, "pot": 0x8a6a2a}, "pot_honey": {"size": 0.16, "projectile": true, "pot": 0xe8a020},
	"pot_smoke": {"size": 0.16, "projectile": true, "pot": 0x777777}, "pot_mystery": {"size": 0.2, "projectile": true, "pot": 0xd04aa0},
	"pot_chickens": {"size": 0.2, "projectile": true, "pot": 0xf7d32a}, "pot_anvil": {"size": 0.22, "projectile": true},
	"pot_harpoon": {"size": 0.12, "projectile": true}, "pot_dart": {"size": 0.08, "projectile": true, "dart": true},
	"pot_bolt": {"size": 0.08, "projectile": true, "dart": true}, "nail": {"size": 0.03, "projectile": true, "dart": true},
	"pot_arrow": {"size": 0.08, "projectile": true, "dart": true}, "pot_arrow_fire": {"size": 0.08, "projectile": true, "dart": true},
	"pot_arrow_poison": {"size": 0.08, "projectile": true, "dart": true}, "pot_arrow_ice": {"size": 0.08, "projectile": true, "dart": true},
	"pot_discus": {"size": 0.12, "projectile": true, "discus": true}, "pot_bignet": {"size": 0.3, "projectile": true},
	"boomerang": {"size": 0.14, "projectile": true, "boomerang": true}, "cheese": {"size": 0.24, "rolling": true},
	"arrow_loose": {"size": 0.06, "debris": true},
	"ball": {"size": 0.28, "rolling": true, "ball": true},
}

var list: Array = []
var next_id := 1
var headless := false
var on_event: Callable

static var _mats := {}

static func _mat(color: int) -> StandardMaterial3D:
	if not _mats.has(color):
		var m := StandardMaterial3D.new()
		m.albedo_color = Color.hex(color << 8 | 0xff)
		m.roughness = 0.8
		_mats[color] = m
	return _mats[color]

static func _box(g: Node3D, w: float, h: float, d: float, color: int, x := 0.0, y := 0.0, z := 0.0) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(w, h, d)
	bm.material = _mat(color)
	mi.mesh = bm
	mi.position = Vector3(x, y, z)
	g.add_child(mi)

## What an item looks like (items.js makeItemVisual), nose along +z for darts.
static func visual(type: String) -> Node3D:
	var g := Node3D.new()
	match type:
		"bread":
			_box(g, 0.28, 0.1, 0.16, 0xb07a3a); _box(g, 0.24, 0.05, 0.12, 0xd9a35a, 0, 0.07, 0)
		"wine":
			_box(g, 0.14, 0.2, 0.14, 0x7a3b2a); _box(g, 0.07, 0.08, 0.07, 0x7a3b2a, 0, 0.14, 0)
		"tomato":
			_box(g, 0.1, 0.1, 0.1, 0xd22a1c); _box(g, 0.05, 0.02, 0.05, 0x2e8b2e, 0, 0.055, 0)
		"banana":
			_box(g, 0.06, 0.03, 0.12, 0xf2d640); _box(g, 0.05, 0.03, 0.08, 0xf2d640, 0.07, 0, 0.07); _box(g, 0.05, 0.03, 0.08, 0xf2d640, -0.07, 0, 0.07)
		"coin":
			_box(g, 0.12, 0.03, 0.12, 0xffc62a)
		"rock":
			_box(g, 0.12, 0.1, 0.11, 0x777068); _box(g, 0.06, 0.05, 0.06, 0x8a837a, 0.03, 0.05, 0)
		"net", "pot_bignet":
			var s := 0.6 if type == "net" else 0.9
			for i in 5:
				_box(g, s, 0.01, 0.01, 0x8a6a3a, 0, 0, -s / 2 + i * s / 4); _box(g, 0.01, 0.01, s, 0x8a6a3a, -s / 2 + i * s / 4, 0, 0)
		"pot_bola":
			_box(g, 0.07, 0.07, 0.07, 0x4a4f63, -0.12); _box(g, 0.07, 0.07, 0.07, 0x4a4f63, 0.12); _box(g, 0.07, 0.07, 0.07, 0x4a4f63, 0, 0, 0.12); _box(g, 0.22, 0.015, 0.015, 0x8a6a3a)
		"pot_anvil":
			_box(g, 0.3, 0.12, 0.14, 0x3a3f46, 0, 0.1); _box(g, 0.14, 0.1, 0.12, 0x3a3f46); _box(g, 0.1, 0.06, 0.1, 0x3a3f46, 0.17, 0.12)
		"pot_harpoon":
			_box(g, 0.03, 0.03, 0.5, 0x8b5a2b); _box(g, 0.03, 0.03, 0.12, 0xc9d1d9, 0, 0, 0.3); _box(g, 0.08, 0.02, 0.05, 0xc9d1d9, 0, 0, 0.25)
		"pot_bolt":
			_box(g, 0.025, 0.025, 0.34, 0x6b4426); _box(g, 0.03, 0.03, 0.06, 0xc9d1d9, 0, 0, 0.18)
		"pot_dart":
			_box(g, 0.025, 0.025, 0.22, 0x8a8f96); _box(g, 0.06, 0.06, 0.03, 0xd04a3a, 0, 0, -0.1)
		"nail":
			_box(g, 0.012, 0.012, 0.09, 0x6a6e74); _box(g, 0.03, 0.03, 0.008, 0x8a8f96, 0, 0, -0.045)
		"pot_arrow", "pot_arrow_fire", "pot_arrow_poison", "pot_arrow_ice", "arrow_loose":
			var tip: int = {"pot_arrow_fire": 0xff7a1a, "pot_arrow_poison": 0x7ae04a, "pot_arrow_ice": 0xa8e8ff}.get(type, 0xc9d1d9)
			_box(g, 0.02, 0.02, 0.6, 0xc9a86a); _box(g, 0.03, 0.03, 0.07, tip, 0, 0, 0.32); _box(g, 0.06, 0.02, 0.08, 0xe04040, 0, 0, -0.26); _box(g, 0.02, 0.06, 0.08, 0xe8e8e8, 0, 0, -0.26)
		"pot_discus":
			_box(g, 0.26, 0.025, 0.26, 0xc08a3e)
		"boomerang":
			_box(g, 0.04, 0.03, 0.3, 0xc9d1d9, 0, 0, 0.12); _box(g, 0.3, 0.03, 0.04, 0xc9d1d9, 0.12); _box(g, 0.06, 0.05, 0.06, 0x8b5a2b)
		"cheese":
			_box(g, 0.12, 0.42, 0.42, 0xf2c94c)
		"bandage":
			_box(g, 0.16, 0.12, 0.12, 0xf2ecdc); _box(g, 0.17, 0.04, 0.04, 0xd8cfb8); _box(g, 0.06, 0.012, 0.2, 0xf2ecdc, 0.03, -0.065, 0.06)
		"ball":
			_box(g, 0.26, 0.28, 0.26, 0xd9a37a); _box(g, 0.27, 0.08, 0.27, 0x2b1d14, 0, 0.12, 0); _box(g, 0.05, 0.05, 0.03, 0x111111, 0.06, 0.02, 0.13); _box(g, 0.05, 0.05, 0.03, 0x111111, -0.06, 0.02, 0.13)
		_:
			# A clay pot: a round belly, shoulders, a neck, a painted band and a sealed lid in
			# the colour of what is inside.
			var pot = TYPES.get(type, {}).get("pot")
			_box(g, 0.13, 0.04, 0.13, 0x8a5a30, 0, -0.07, 0)
			_box(g, 0.17, 0.1, 0.17, 0x9a6a3a, 0, -0.01, 0)
			_box(g, 0.14, 0.12, 0.19, 0x9a6a3a, 0, -0.01, 0)
			_box(g, 0.19, 0.12, 0.14, 0x9a6a3a, 0, -0.01, 0)
			_box(g, 0.13, 0.04, 0.13, 0xa87442, 0, 0.065, 0)
			_box(g, 0.07, 0.04, 0.07, 0x8a5a30, 0, 0.1, 0)
			if pot != null:
				_box(g, 0.195, 0.03, 0.145, int(pot), 0, 0.0, 0)
				_box(g, 0.145, 0.03, 0.195, int(pot), 0, 0.0, 0)
				_box(g, 0.09, 0.03, 0.09, int(pot), 0, 0.13, 0)
	return g

func spawn(type: String, pos: Vector3, vel := Vector3.ZERO, owner_: Node = null, id := -1) -> Dictionary:
	var def: Dictionary = TYPES.get(type, {"size": 0.15})
	var it := {"id": next_id if id < 0 else id, "type": type, "p": pos, "vel": vel, "owner": owner_, "age": 0.0, "grounded": false,
		"dart": def.get("dart", false), "spin": Vector3.ZERO if def.get("dart", false) else Vector3(randf() * 8.0, randf() * 8.0, 0), "node": null}
	next_id = maxi(next_id, it.id) + 1
	if not headless:
		var n := visual(type)
		add_child(n)
		n.position = pos
		it.node = n
		_face(it)
	list.append(it)
	return it

## Thrown from a hand so it lands on `target` (the flat speed given, the lob worked out).
func throw_at(type: String, from: Vector3, target: Vector3, owner_: Node, speed := 11.0, gravity := 9.81) -> Dictionary:
	var d := target - from
	var t := maxf(0.2, Vector2(d.x, d.z).length() / speed)
	return spawn(type, from, Vector3(d.x / t, (d.y + 0.5 * gravity * t * t) / t, d.z / t), owner_)

## Thrown in from the stands to land at `target` after `t` seconds.
func throw_from_stands(type: String, target: Vector3, t := 1.2, gravity := 9.81) -> Dictionary:
	var a := randf() * TAU
	var from := Vector3(sin(a) * (RADIUS + 3.0), 4.5, cos(a) * (RADIUS + 3.0))
	var v := Vector3((target.x - from.x) / t, 0, (target.z - from.z) / t)
	v.y = (target.y - from.y + 0.5 * gravity * t * t) / t
	return spawn(type, from, v)

func remove(it: Dictionary) -> void:
	if it.node and is_instance_valid(it.node):
		it.node.queue_free()
	list.erase(it)

func clear() -> void:
	for it in list.duplicate():
		remove(it)

func _face(it: Dictionary) -> void:
	var n: Node3D = it.node
	if n == null:
		return
	n.position = it.p
	if it.dart and it.vel.length_squared() > 1e-6:
		var d: Vector3 = it.vel.normalized()
		if absf(d.dot(Vector3.UP)) < 0.999:
			n.look_at(it.p + d, Vector3.UP)
			n.rotate_object_local(Vector3.UP, PI)

## The body (and part) at point `p` within `r`: a dart must be inside the part's box, anything
## else breaks when it comes within its own radius of the box.
func hit_char(p: Vector3, chars: Array, r: float, owner_, any_part: bool):
	for c in chars:
		if not is_instance_valid(c) or not c.alive or c == owner_:
			continue
		var parts: Array = c.parts if any_part else [c.head, c.torso]
		for part in parts:
			if part == null or part.severed:
				continue
			var d := Social.box_distance(part, p)
			if d <= 0.0 or (r > 0.17 and d < r) or (not any_part and part.global_position.distance_to(p) < r + 0.1 * c.S):
				return {"char": c, "part": part}
	return null

## One step: flight, landing, hits. `chars` are the fighters and beasts in the arena.
func update(dt: float, chars: Array, gravity := 9.81) -> void:
	for it in list.duplicate():
		if not list.has(it):
			continue
		it.age += dt
		var def: Dictionary = TYPES.get(it.type, {"size": 0.15})
		var size: float = def.get("size", 0.15)
		if not it.grounded:
			if def.get("boomerang", false) and it.owner and is_instance_valid(it.owner):
				if it.age > 0.8:
					it.returning = true
				if it.get("returning", false):
					var home: Vector3 = it.owner.torso.global_position + Vector3(0, 0.3, 0)
					var dh: Vector3 = home - it.p
					if dh.length() < 0.6:
						_emit({"kind": "return", "type": it.type, "char": it.owner, "item": it, "p": it.p})
						remove(it)
						continue
					it.vel = it.vel.lerp(dh.normalized() * 11.0, minf(1.0, dt * 4.0))
			elif def.get("discus", false):
				it.vel.y -= gravity * dt * 0.25
			else:
				it.vel.y -= gravity * dt
			var steps := 1
			if it.dart:
				steps = maxi(1, ceili(it.vel.length() * dt / 0.05))
			elif def.get("projectile", false):
				steps = maxi(1, ceili(it.vel.length() * dt / 0.08))
			var hit = null
			for k in steps:
				it.p += it.vel * (dt / steps)
				if it.type == "tomato" or def.get("projectile", false):
					var r: float = 0.45 if it.type == "net" or it.type == "pot_bignet" else (0.16 if it.dart else size * 0.6 + 0.04)
					hit = hit_char(it.p, chars, r, null if it.get("bounced", false) or it.get("returning", false) else it.owner, true)
					if hit:
						break
			if it.node:
				_face(it)
				if not it.dart:
					it.node.rotation += it.spin * dt
			if hit:
				_emit({"kind": "splat", "type": it.type, "char": hit.char, "part": hit.part, "item": it, "p": it.p, "dir": it.vel.normalized()})
				remove(it)
				continue
			if it.p.y <= size / 2.0:
				it.p.y = size / 2.0
				if it.type == "tomato" or def.get("projectile", false):
					_emit({"kind": "splat", "type": it.type, "char": null, "part": null, "item": it, "p": it.p, "dir": it.vel.normalized()})
					remove(it)
					continue
				it.grounded = true
				if it.node:
					it.node.rotation = Vector3(0, it.node.rotation.y, 0)
			# Kept inside the arena wall (a discus bounces off it).
			var rr := Vector2(it.p.x, it.p.z).length()
			if rr > RADIUS - 0.3 and it.p.y < 2.5:
				it.p.x *= (RADIUS - 0.3) / rr
				it.p.z *= (RADIUS - 0.3) / rr
				if def.get("discus", false):
					var n := Vector3(it.p.x, 0, it.p.z).normalized()
					it.vel = (it.vel - n * 2.0 * it.vel.dot(n)) * 0.85
					it.bounced = true
					_emit({"kind": "bounce", "type": it.type, "char": null, "item": it, "p": it.p})
				else:
					it.vel.x *= -0.3
					it.vel.z *= -0.3
			continue
		if it.age > 60.0:
			remove(it)
			continue
		if def.get("ball", false):
			# The head: anyone's leg can kick it, moving or not.
			for c in chars:
				if not c.alive or c.kind == "beast":
					continue
				var kicked := false
				for n in ["shinL", "shinR"]:
					var sp = c.by_name.get(n)
					if sp == null or sp.severed:
						continue
					if Vector2(sp.global_position.x - it.p.x, sp.global_position.z - it.p.z).length() > 0.42 or absf(sp.global_position.y - it.p.y) > 0.6:
						continue
					var lv: Vector3 = sp.linear_velocity
					var spd := Vector2(lv.x, lv.z).length()
					if spd < 1.2:
						continue
					_emit({"kind": "kick", "type": it.type, "char": c, "item": it, "p": it.p, "dir": Vector3(lv.x, 0, lv.z).normalized(), "speed": minf(9.0, spd)})
					kicked = true
					break
				if kicked:
					break
		if def.get("rolling", false) and it.vel.length_squared() > 0.05:
			it.vel *= pow(0.4, dt)
			it.p += it.vel * dt
			if it.node:
				it.node.position = it.p
				it.node.rotation.x -= it.vel.length() * dt / (size / 2.0)
			var rr2 := Vector2(it.p.x, it.p.z).length()
			if rr2 > RADIUS - 0.4:
				var n2 := Vector3(it.p.x, 0, it.p.z).normalized()
				it.vel = (it.vel - n2 * 2.0 * it.vel.dot(n2)) * 0.6
			if it.vel.length() > 2.0:
				for c in chars:
					if not c.alive or c.state != "stand" or (c == it.owner and it.age < 0.6):
						continue
					if _near_feet(c, it.p, 0.35):
						_emit({"kind": "ram", "type": it.type, "char": c, "item": it, "p": it.p})
						it.vel *= 0.5
						break
			continue
		if def.get("debris", false):
			continue
		for c in chars:
			if not c.alive:
				continue
			if it.type == "banana":
				if c.state == "stand" and _near_feet(c, it.p, 0.28):
					_emit({"kind": "slip", "type": it.type, "char": c, "item": it, "p": it.p})
					remove(it)
					break
			elif c.kind != "beast":
				var t: Vector3 = c.torso.global_position
				if Vector2(t.x - it.p.x, t.z - it.p.z).length() < 0.55:
					_emit({"kind": "eat", "type": it.type, "char": c, "item": it, "p": it.p})
					remove(it)
					break

func _near_feet(c, p: Vector3, r: float) -> bool:
	for n in ["shinL", "shinR"]:
		var sp = c.by_name.get(n)
		if sp and not sp.severed and Vector2(sp.global_position.x - p.x, sp.global_position.z - p.z).length() < r:
			return true
	return false

func _emit(ev: Dictionary) -> void:
	if on_event.is_valid():
		on_event.call(ev)

## For guests: what is in the air, to draw.
func snapshot() -> Array:
	var out := []
	for it in list:
		out.append([it.id, it.type, snappedf(it.p.x, 0.01), snappedf(it.p.y, 0.01), snappedf(it.p.z, 0.01), snappedf(it.vel.x, 0.01), snappedf(it.vel.y, 0.01), snappedf(it.vel.z, 0.01)])
	return out

func apply_snapshot(rows: Array) -> void:
	var seen := {}
	for r in rows:
		if not (r is Array) or r.size() < 8 or not TYPES.has(String(r[1])):
			continue
		seen[int(r[0])] = true
		var it = null
		for x in list:
			if x.id == int(r[0]):
				it = x
				break
		var p := Vector3(r[2], r[3], r[4])
		if it == null:
			it = spawn(String(r[1]), p, Vector3(r[5], r[6], r[7]), null, int(r[0]))
		it.p = p
		it.vel = Vector3(r[5], r[6], r[7])
		_face(it)
	for it in list.duplicate():
		if not seen.has(it.id):
			remove(it)
