class_name Throwables
extends Node3D
## Pots, arrows, darts and the rest (throwables.js, weaponFx.js): what each one does where it
## breaks, the zones they leave on the sand (sand cloud, fire, acid, caltrops, oil, honey,
## smoke), the burning spray of Greek fire, the hotbar of a campaign kit, and the weapons that
## shoot (bows, crossbows, flame poles). Host side; `m` is the Match.

const POTS := {"thunderPot": "pot_thunder", "nailPot": "pot_nail", "sandPot": "pot_sand", "greekFire": "pot_fire", "vitriol": "pot_acid", "beehive": "pot_bees",
	"caltrops": "pot_caltrops", "goat": "pot_goat", "bola": "pot_bola", "oliveOil": "pot_oil", "garum": "pot_garum", "honey": "pot_honey", "smoke": "pot_smoke",
	"mystery": "pot_mystery", "chickens": "pot_chickens", "anvil": "pot_anvil", "harpoon": "pot_harpoon", "discus": "pot_discus", "bigNet": "pot_bignet", "fireball": "pot_fireball"}
const THROW_SPEED := {"pot_anvil": 7.2, "pot_harpoon": 19.0, "pot_discus": 18.0, "pot_bola": 15.5}
const NAILS := 96
const CALTROPS := 14
const ZONE_COLORS := {"sand": Color(0.85, 0.75, 0.54, 0.45), "fire": Color(1.0, 0.48, 0.1, 0.55), "acid": Color(0.56, 0.83, 0.23, 0.7), "caltrops": Color(0.36, 0.37, 0.4, 1.0),
	"oil": Color(0.16, 0.23, 0.06, 0.7), "honey": Color(0.91, 0.63, 0.13, 0.75), "smoke": Color(0.6, 0.6, 0.6, 0.5)}

var m: Node
var zones: Array = []
var drops: Array = []
var swarms: Array = []   # bees out of a broken hive on their way to a man: {pos, target, owner, t, node}
var next_zone := 1
var headless := false

func _init(match_: Node) -> void:
	m = match_
	headless = match_.headless

## What a bag holds: nine kinds at most (one for each number key), and of each as many as can
## be carried into a fight: one of a heavy thing, three pots or bombs, five of something light.
const BAG_KINDS := 9
const STACK_HEAVY := ["anvil", "goat", "bigNet", "beehive", "harpoon"]
const STACK_LIGHT := ["bandage", "bread", "wine", "bananas", "cheese", "darts", "caltrops", "discus"]

static func stack_max(id: String) -> int:
	return 1 if STACK_HEAVY.has(id) else (5 if STACK_LIGHT.has(id) else 3)

## Whether one more `id` fits in the bag: below its stack, and a new kind only while there are
## fewer than nine.
static func bag_has_room(inv: Dictionary, id: String) -> bool:
	var have := int(inv.get(id, 0))
	if have >= stack_max(id):
		return false
	if have > 0:
		return true
	var kinds := 0
	for k in inv:
		if int(inv[k]) > 0:
			kinds += 1
	return kinds < BAG_KINDS

## A bag cut down to what it may hold (an old save, a guest's kit): each stack to its most,
## and only the first nine kinds.
static func bag_clamp(inv: Dictionary) -> Dictionary:
	var out := {}
	for id in Data.shop.get("throwables", {}):
		var n := mini(int(inv.get(id, 0)), stack_max(id))
		if n > 0 and out.size() < BAG_KINDS:
			out[id] = n
	return out

static func hotbar_of(inv: Dictionary) -> Array:
	var out := []
	for id in Data.shop.get("throwables", {}):
		if int(inv.get(id, 0)) > 0:
			out.append(id)
	return out

# ---------- Effects (cheap one-shot particle bursts) ----------

## A burst of particles in the colours of `color` (the effects module picks the kind).
func burst(p: Vector3, color: Color, n: int, speed := 2.0, _life := 0.7, _size := 0.05, _up := 1.0) -> void:
	var fx: Fx = m.fx
	if fx == null:
		return
	var kind := "debris"
	if color.r > 0.9 and color.g < 0.75 and color.b < 0.4:
		kind = "fire"
	elif color.g > color.r and color.g > color.b + 0.2:
		kind = "acid"
	elif color.r > 0.6 and color.g > 0.55 and color.b > 0.35 and color.b < color.g:
		kind = "dust"
	elif color.r > 0.7 and color.g < 0.3:
		kind = "blood"
	elif color.b > 0.8 and color.g > 0.8:
		kind = "sparks"
	fx.burst(kind, p, n, Vector3.UP, speed / 2.0)

func flash(p: Vector3, color: Color, energy := 8.0, r := 6.0) -> void:
	if m.fx:
		m.fx.flash(p, color, energy, r)

# ---------- Hits ----------

func _hit(c, part: VoxelPart, J: float, type: String, point: Vector3, dir: Vector3, owner_, extra := {}) -> Dictionary:
	var was_alive: bool = c.alive
	var h := {"impulse": J, "type": type, "hardness": extra.get("hardness", 0.9 if type == "point" else 0.6), "sharpness": extra.get("sharpness", 0.9 if type == "point" else 0.0), "point": point, "dir": dir, "axis": dir, "crush": extra.get("crush", 0.0), "heavy": extra.get("heavy", 0.0)}
	if extra.has("blast"):
		h.blast = extra.blast
		h.blast_r = extra.blast_r
	var res: Dictionary = c.apply_hit(part, h)
	if owner_ and owner_ != c:
		c.last_attacker = owner_
	m.report_hit({"kind": "hit", "p": point, "dir": dir, "J": J, "type": type, "char": c, "part": part, "attacker": owner_, "res": res, "killed": was_alive and not c.alive})
	return res

func _near(p: Vector3, r: float) -> Array:
	var out := []
	for e in m.entities:
		var c = e.f
		if not c.alive:
			continue
		var d: float = c.torso.global_position.distance_to(p)
		if d < r:
			out.append({"c": c, "d": d, "e": e})
	out.sort_custom(func(a, b): return a.d < b.d)
	return out

## A blast: every part of everyone in reach takes a blow on the side turned to it, harder the
## closer it is, and what was right where it went off is blown away.
func blast(p: Vector3, radius := 3.5, power := 24.0, owner_ = null) -> void:
	# The crater it blows out of what it went off against (a thunder pot's, 0.32 m wide); a
	# part farther off loses less, and none half a metre away.
	var rb := 0.06 + 0.006 * power
	for e in m.entities:
		var c = e.f
		if not c.alive:
			continue
		var hits := []
		for part in c.parts:
			if part.severed:
				continue
			var centre: Vector3 = part.global_position
			var to_p := p - centre
			var dc := to_p.length()
			var face := centre + to_p.normalized() * minf(dc, 0.1 * c.S)
			var d := face.distance_to(p)
			if d > radius:
				continue
			hits.append({"part": part, "face": face, "f": pow(1.0 - d / radius, 1.5)})
		hits.sort_custom(func(a, b): return a.f > b.f)
		var first := true
		for h in hits:
			if h.part.severed:
				continue
			var J: float = power * h.f
			# A monster's hide takes the blast hardest where it went off against it.
			if first and c is Beast:
				J *= 1.4
			first = false
			if J < 3.0:
				continue
			_hit(c, h.part, J, "blunt", h.face, (h.face - p).normalized(), owner_, {"hardness": 0.6, "blast": p, "blast_r": rb})
			# The shock goes through the trunk and the skull: what is inside is hurt under the
			# skin, a beast's as a man's, wherever the blast struck him.
			if c.alive and (h.part == c.torso or h.part == c.head) and c.has_method("blast_shock"):
				c.blast_shock(h.part, J)

## Greek fire (or vitriol) breaks like a firebomb: the liquid bursts out mostly the way the pot
## was flying and fans out along whatever it hit, flying as drops on their own momentum. A drop
## that meets a body clings and catches there, and some of it runs on down him; one that meets a
## wall runs down the wall; one that meets the floor (or a table, a crate) skates along it as a
## sheet, wetting the ground as it goes. What is on the ground spreads from wet to dry, thins
## out, and burns (or eats) until its fuel is spent.
const POT_FUEL := 7.0          # what one pot holds
func splash_burning(p: Vector3, dir, n: int, owner_, hit_part, hit_char, kind := "fire", seed_ := -1, visual := false) -> void:
	var rng := RandomNumberGenerator.new()
	if seed_ >= 0:
		rng.seed = seed_
	else:
		rng.randomize()
		seed_ = int(rng.seed % 1000000)
	var fwd: Vector3 = (dir as Vector3).normalized() if dir is Vector3 and (dir as Vector3).length_squared() > 1e-4 else Vector3.ZERO
	# The face it broke on: a body (away from him), the ground, or a wall.
	var face := Vector3.UP
	if hit_part and is_instance_valid(hit_part):
		face = p - hit_part.global_position
		face = face.normalized() if face.length_squared() > 1e-4 else -fwd
	elif p.y > 0.3 and fwd != Vector3.ZERO:
		var hit := _ray(p - fwd * 0.3, p + fwd * 0.4)
		if not hit.is_empty():
			face = hit.normal
	var speed := 8.0
	# Momentum along the face carries on; into the face it is mostly lost.
	var along := fwd - face * fwd.dot(face)
	for i in n:
		var a := rng.randf() * TAU
		var spread := Vector3(cos(a), 0, sin(a))
		spread = (spread - face * spread.dot(face)).normalized() if absf(face.y) < 0.99 else spread
		var v := along * speed * (0.35 + 0.55 * rng.randf()) + spread * speed * (0.15 + 0.4 * rng.randf()) + face * (0.4 + 1.4 * rng.randf())
		drops.append({"p": p + face * 0.03 + Vector3(rng.randf_range(-0.04, 0.04), 0.0, rng.randf_range(-0.04, 0.04)), "v": v, "fuel": POT_FUEL / n * (0.5 + rng.randf()),
			"owner": owner_, "acid": kind == "acid", "from": hit_char, "age": 0.0, "slide": false, "y": 0.0, "visual": visual, "skip": null})
	if not visual:
		if hit_part and hit_char and hit_char.alive:
			m.add_spot(hit_char, hit_part, kind, 6.0, owner_, p)
		if m.role == "host":
			Net.send_all("splash", {"p": [snappedf(p.x, 0.01), snappedf(p.y, 0.01), snappedf(p.z, 0.01)], "d": [snappedf(fwd.x, 0.01), snappedf(fwd.y, 0.01), snappedf(fwd.z, 0.01)], "k": kind, "n": n, "s": seed_})
	burst(p, Color(1.0, 0.5, 0.1) if kind == "fire" else Color(0.56, 0.83, 0.23), 24, 2.5, 0.6, 0.04)
	if kind == "fire":
		# The whump of it catching.
		flash(p, Color(1.0, 0.55, 0.2), 7.0, 6.0)
		if m.fx:
			m.fx.burst("blastfire", p + Vector3(0, 0.2, 0), 30, Vector3.UP, 0.8)

## One glob of a breath: burning fuel (or venom) flying from `p` at `v`.
func spit(kind: String, p: Vector3, v: Vector3, owner_, visual := false) -> void:
	if drops.size() > 600:
		return
	drops.append({"p": p, "v": v, "fuel": 0.05, "owner": owner_, "acid": kind == "acid", "from": owner_, "age": 0.0, "slide": false, "y": 0.0, "visual": visual, "skip": null, "glob": true})

## What a splash meets in the world: the ground, walls, crates, and a shield or blade held up.
func _ray(a: Vector3, b: Vector3) -> Dictionary:
	if not is_inside_tree():
		return {}
	var q := PhysicsRayQueryParameters3D.create(a, b, VoxelPart.LAYER_WORLD | VoxelPart.LAYER_WEAPON)
	q.hit_from_inside = false
	return get_world_3d().direct_space_state.intersect_ray(q)

func _update_drops(dt: float) -> void:
	for d in drops.duplicate():
		d.age += dt
		var from: Vector3 = d.p
		var done := false
		if d.slide:
			# A sheet on a surface: it slows as it wets the ground, leaving fuel along its way.
			var sp: float = Vector3(d.v.x, 0, d.v.z).length()
			d.v *= exp(-3.0 * dt)
			d.p += Vector3(d.v.x, 0, d.v.z) * dt
			d.p.y = d.y + 0.01
			var left: float = d.fuel * minf(1.0, dt * 3.0)
			d.fuel -= left
			_deposit(d, d.p, left)
			# Off the edge of a crate: it falls again.
			if _ray(d.p + Vector3(0, 0.05, 0), d.p - Vector3(0, 0.12, 0)).is_empty() and d.y > 0.05:
				d.slide = false
			if sp < 0.25 or d.fuel < 0.01:
				_deposit(d, d.p, d.fuel)
				done = true
		else:
			d.v.y -= 9.81 * dt
			d.v *= pow(0.85, dt)
			d.p += d.v * dt
			# On someone: it clings there, and part of it runs on down him.
			var body := _drop_on_body(d)
			if not body.is_empty():
				var c = body.c
				var part: VoxelPart = body.part
				if not d.visual:
					m.add_spot(c, part, "acid" if d.acid else "fire", 1.5 + 3.0 * minf(1.0, d.fuel * 4.0), d.owner, d.p)
					if d.get("glob", false):
						# A breath's stream has weight: it shoves what it pours onto.
						part.apply_central_impulse(d.v * 0.04 * float(c.MS))
						if d.owner and d.owner != c:
							c.last_attacker = d.owner
				if randf() < 0.5:
					d.v = part.velocity_at(d.p) * 0.5 + Vector3(0, -0.6, 0)
					d.fuel *= 0.5
					d.skip = part
					d.from = null
				else:
					done = true
			elif d.p.y < 3.0 or d.age > 0.05 or d.get("glob", false):
				# (A breath's globs are checked from the first step: out of a mouth held a hand
				# from a wall, at nine metres a second, they were past it before the check began,
				# and the fire went through the wall.)
				var hit := _ray(from, d.p)
				if not hit.is_empty():
					var nrm: Vector3 = hit.normal
					if nrm.y > 0.6:
						# A floor or the top of something: it lands and runs on along it.
						d.slide = true
						d.y = hit.position.y
						d.p = hit.position
						d.v = (d.v - nrm * d.v.dot(nrm)) * 0.7
						_deposit(d, d.p, d.fuel * 0.25)
						d.fuel *= 0.75
					else:
						# A wall: it splashes on it and runs down it.
						_wall_mark(hit.position, nrm, d.acid)
						d.p = hit.position + nrm * 0.03
						d.v = (d.v - nrm * d.v.dot(nrm)) * 0.15 + Vector3(0, -0.5, 0)
			if not d.slide and d.p.y <= 0.0:
				d.slide = true
				d.y = 0.0
			if d.age > 6.0:
				done = true
		if done:
			drops.erase(d)
	_draw_drops()

func _drop_on_body(d: Dictionary) -> Dictionary:
	for e in m.entities:
		var c = e.f
		if not c.alive or (c == d.from and d.age < 0.3):
			continue
		if c.torso.global_position.distance_squared_to(d.p) > pow(3.2 * float(c.S), 2.0):
			continue
		for part in c.parts:
			if part.severed or part == d.skip:
				continue
			if Social.box_distance(part, d.p) < 0.03:
				return {"c": c, "part": part}
	return {}

# ---------- Liquid on the ground ----------

const CELL := 0.22
const FILM := 0.1          # thinner than this it no longer runs
const MAX_CELLS := 700
var wet := {}              # Vector3i(x, level, z) -> {"k": "fire"|"acid", "f": fuel, "y": height, "owner"}
var _wet_t := 0.0
var _wet_hurt := 0.0
var _wet_send := 0.0
var _wet_mm: MultiMeshInstance3D
var _drop_mm: MultiMeshInstance3D
var _wet_light: OmniLight3D
var _wall_marks := 0
var _wall_fires := 0

static func _key(p: Vector3) -> Vector3i:
	return Vector3i(floori(p.x / CELL), roundi(p.y / 0.4), floori(p.z / CELL))

func _deposit(d: Dictionary, p: Vector3, amount: float) -> void:
	if d.visual or m.role == "guest" or amount <= 0.0:
		return
	add_liquid("acid" if d.acid else "fire", p, amount, d.owner)

func add_liquid(kind: String, p: Vector3, amount: float, owner_ = null) -> void:
	var k := _key(p)
	var c = wet.get(k)
	if c == null:
		if wet.size() >= MAX_CELLS:
			return
		c = {"k": kind, "f": 0.0, "y": p.y, "owner": owner_}
		wet[k] = c
	c.f += amount
	c.k = kind
	if owner_:
		c.owner = owner_

func _update_wet(dt: float) -> void:
	if m.role != "guest":
		_wet_t += dt
		if _wet_t >= 0.1:
			var step := _wet_t
			_wet_t = 0.0
			# It runs from wet to drier ground beside it (walls stop it), thinning out.
			var flow := {}
			for k in wet:
				var c: Dictionary = wet[k]
				if c.f <= FILM:
					continue
				for o in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
					var nk: Vector3i = k + o
					var n = wet.get(nk)
					var nf: float = n.f if n != null else 0.0
					if c.f - nf <= 0.02:
						continue
					if n == null:
						var cp := Vector3((k.x + 0.5) * CELL, c.y + 0.08, (k.z + 0.5) * CELL)
						var np := Vector3((nk.x + 0.5) * CELL, c.y + 0.08, (nk.z + 0.5) * CELL)
						if not _ray(cp, np).is_empty() or _ray(np + Vector3(0, 0.1, 0), np - Vector3(0, 0.25, 0)).is_empty() and c.y > 0.05:
							continue
					var amt: float = (c.f - nf) * 0.06 * minf(1.0, step * 10.0)
					flow[k] = flow.get(k, 0.0) - amt
					flow[nk] = flow.get(nk, 0.0) + amt
					if n == null and not wet.has(nk) and wet.size() < MAX_CELLS:
						wet[nk] = {"k": c.k, "f": 0.0, "y": c.y, "owner": c.owner}
			for k in flow:
				if wet.has(k):
					wet[k].f += flow[k]
			# Fire eats its fuel, faster where it is thick; vitriol soaks away slowly.
			for k in wet.keys():
				var c: Dictionary = wet[k]
				c.f -= step * (0.008 + 0.05 * c.f if c.k == "fire" else 0.004 + 0.02 * c.f)
				if c.f < 0.012:
					wet.erase(k)
		_wet_hurt -= dt
		if _wet_hurt <= 0.0 and not wet.is_empty():
			_wet_hurt = 0.4
			_wet_burns()
		_wet_send -= dt
		if m.role == "host" and _wet_send <= 0.0 and (not wet.is_empty() or _wet_mm and _wet_mm.multimesh.visible_instance_count > 0):
			_wet_send = 0.35
			var cells := []
			for k in wet:
				var c: Dictionary = wet[k]
				cells.append([k.x, k.y, k.z, roundi(c.y * 100.0), roundi(c.f * 100.0), 0 if c.k == "fire" else 1])
			Net.send_all("wet", {"c": cells.slice(0, MAX_CELLS)}, false)
	_draw_wet(dt)

## What lies in a burning (or corrosive) pool catches: feet and shins of a man standing in it,
## all of a man lying in it.
func _wet_burns() -> void:
	for e in m.entities:
		var c = e.f
		if not c.alive:
			continue
		var lying: bool = c.state != "stand"
		for part in c.parts:
			if part.severed:
				continue
			var pp: Vector3 = part.global_position
			var cell = wet.get(_key(Vector3(pp.x, pp.y - (0.0 if lying else 0.6 * c.S), pp.z)))
			if cell == null:
				cell = wet.get(_key(Vector3(pp.x, 0.0, pp.z)))
			if cell == null or cell.f < 0.04:
				continue
			if pp.y - cell.y > (0.45 if lying else 0.5) * c.S + 0.15:
				continue
			if randf() < 0.6:
				m.add_spot(c, part, cell.k, 2.0 + 2.0 * minf(1.0, cell.f), cell.owner, Vector3(pp.x, cell.y, pp.z))
		if wet.has(_key(Vector3(c.torso.global_position.x, 0.0, c.torso.global_position.z))) and wet[_key(Vector3(c.torso.global_position.x, 0.0, c.torso.global_position.z))].k == "fire":
			c.blood = maxf(0.0, c.blood - 0.4)

## The guests are told the pools: they draw them, the host burns with them.
func set_wet(cells: Array) -> void:
	wet.clear()
	for r in cells.slice(0, MAX_CELLS):
		if r is Array and r.size() == 6:
			wet[Vector3i(int(r[0]), int(r[1]), int(r[2]))] = {"y": float(r[3]) / 100.0, "f": clampf(float(r[4]) / 100.0, 0.0, 20.0), "k": "fire" if int(r[5]) == 0 else "acid", "owner": null}

func _mm(color_mesh: Mesh, cap: int) -> MultiMeshInstance3D:
	var mi := MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = color_mesh
	mm.instance_count = cap
	mm.visible_instance_count = 0
	mi.multimesh = mm
	mi.custom_aabb = AABB(Vector3(-40, -2, -40), Vector3(80, 12, 80))
	mm.custom_aabb = mi.custom_aabb
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi

func _draw_drops() -> void:
	if headless:
		return
	if _drop_mm == null:
		var sm := SphereMesh.new()
		sm.radius = 0.022
		sm.height = 0.044
		sm.radial_segments = 6
		sm.rings = 3
		var mat := StandardMaterial3D.new()
		mat.vertex_color_use_as_albedo = true
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		sm.material = mat
		_drop_mm = _mm(sm, 400)
	var mm := _drop_mm.multimesh
	var n := mini(drops.size(), mm.instance_count)
	for i in n:
		var d: Dictionary = drops[i]
		var s := 1.0 if not d.slide else 0.7
		var v: Vector3 = d.v
		var stretch := clampf(v.length() * 0.06, 1.0, 2.6)
		var b := Basis.IDENTITY
		if v.length_squared() > 0.01 and absf(v.normalized().dot(Vector3.UP)) < 0.99:
			b = Basis.looking_at(v.normalized(), Vector3.UP)
		mm.set_instance_transform(i, Transform3D(b.scaled(Vector3(s, s, s * stretch)), d.p))
		mm.set_instance_color(i, Color(0.56, 0.86, 0.22) if d.acid else Color(1.0, 0.62, 0.2))
	mm.visible_instance_count = n

## A blot of liquid: solid in the middle, soft and a little ragged at the rim.
static var _ptex: ImageTexture
static func _puddle_tex() -> ImageTexture:
	if _ptex:
		return _ptex
	var n := 64
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var noise := FastNoiseLite.new()
	noise.frequency = 0.09
	# In blocks (16 across), the way the voxel sand is.
	for yy in n:
		for xx in n:
			var x := (xx / 4) * 4 + 2
			var y := (yy / 4) * 4 + 2
			var d := Vector2(x - n * 0.5 + 0.5, y - n * 0.5 + 0.5).length() / (n * 0.5)
			var edge := 0.78 + 0.16 * noise.get_noise_2d(x, y)
			var a := 0.9 if (edge - d) / 0.22 + 0.5 > 0.5 else 0.0
			img.set_pixel(xx, yy, Color(1, 1, 1, a))
	_ptex = ImageTexture.create_from_image(img)
	return _ptex

const FLAMES := 26
var _flame_pool: Array = []
var _smoke: Node3D
var _flame_t := 0.0
func _draw_wet(dt: float) -> void:
	if headless:
		return
	if _wet_mm == null:
		var pm := PlaneMesh.new()
		pm.size = Vector2(CELL * 2.3, CELL * 2.3)
		var mat := StandardMaterial3D.new()
		mat.vertex_color_use_as_albedo = true
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.roughness = 0.45
		mat.metallic_specular = 0.35
		mat.albedo_texture = _puddle_tex()
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		pm.material = mat
		_wet_mm = _mm(pm, MAX_CELLS)
		_wet_light = OmniLight3D.new()
		_wet_light.light_color = Color(1.0, 0.55, 0.2)
		_wet_light.shadow_enabled = false
		add_child(_wet_light)
	var mm := _wet_mm.multimesh
	var i := 0
	var heat := 0.0
	var centre := Vector3.ZERO
	var t := Time.get_ticks_msec() / 1000.0
	var burning := []
	for k in wet:
		if i >= mm.instance_count:
			break
		var c: Dictionary = wet[k]
		var at := Vector3((k.x + 0.5) * CELL, c.y + 0.05 + 0.003 * (i % 3), (k.z + 0.5) * CELL)
		var s := clampf(0.8 + sqrt(c.f) * 0.7, 0.8, 1.5)
		var rot := float((k.x * 73856093) ^ (k.z * 19349663)) * 0.001
		mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, rot).scaled(Vector3(s, 1, s)), at))
		var a := clampf(0.4 + c.f * 4.0, 0.4, 0.92)
		if c.k == "fire":
			# Pitch soaked into the sand: dark and glossy, glowing where it burns hot.
			var glow := clampf(c.f * 1.5, 0.0, 0.6) * (0.8 + 0.2 * sin(t * 11.0 + k.x * 1.7 + k.z * 2.3))
			mm.set_instance_color(i, Color(0.1 + 0.6 * glow, 0.045 + 0.2 * glow, 0.02, a))
			heat += c.f
			centre += at * c.f
			burning.append([c.f, at])
		else:
			mm.set_instance_color(i, Color(0.45, 0.85, 0.15, a * 0.85))
		i += 1
	mm.visible_instance_count = i
	_place_flames(burning, dt)
	if heat > 0.6 and m.fx:
		# A big fire smokes: black pitch smoke rising off the middle of it.
		if _smoke == null:
			_smoke = Node3D.new()
			add_child(_smoke)
			m.fx.emitter("pool_smoke", _smoke, 30, 0.6)
		_smoke.visible = true
		_smoke.global_position = centre / heat + Vector3(0, 0.6, 0)
	elif _smoke:
		_smoke.visible = false
	if _wet_light:
		_wet_light.visible = heat > 0.05
		if heat > 0.05:
			_wet_light.global_position = centre / heat + Vector3(0, 1.3, 0)
			_wet_light.light_energy = clampf(heat * 0.25, 0.4, 2.2) * (0.85 + 0.15 * sin(t * 17.0))
			_wet_light.omni_range = clampf(2.5 + sqrt(heat) * 1.5, 2.5, 8.0)

## Flames stand where the pool burns thickest: a few dozen fires moved onto the hottest spots,
## each as tall as the fuel under it.
func _place_flames(burning: Array, dt: float) -> void:
	_flame_t -= dt
	if _flame_t > 0.0 or m.fx == null:
		return
	_flame_t = 0.25
	burning.sort_custom(func(x, y): return x[0] > y[0])
	var chosen := []
	for b in burning:
		if chosen.size() >= FLAMES:
			break
		if chosen.all(func(o): return (o[1] as Vector3).distance_to(b[1]) > 0.42):
			chosen.append(b)
	while _flame_pool.size() < chosen.size():
		var holder := Node3D.new()
		add_child(holder)
		var ps: GPUParticles3D = m.fx.emitter("pool_fire", holder, 20, 0.24)
		if ps == null:
			holder.queue_free()
			break
		# Every flame smokes, a little; the big plume over a large fire is on top of it.
		var sm: GPUParticles3D = m.fx.emitter("fire_smoke", holder, 14, 0.2)
		if sm:
			sm.position = Vector3(0, 0.55, 0)
		_flame_pool.append({"node": holder, "ps": ps, "smoke": sm})
	for j in _flame_pool.size():
		var fl: Dictionary = _flame_pool[j]
		var ps: GPUParticles3D = fl.ps
		if j < chosen.size():
			fl.node.global_position = chosen[j][1]
			ps.emitting = true
			ps.amount_ratio = clampf(0.3 + chosen[j][0] * 1.5, 0.3, 1.0)
			ps.speed_scale = clampf(0.8 + chosen[j][0], 0.8, 1.6)
			if fl.smoke:
				fl.smoke.emitting = true
				fl.smoke.amount_ratio = clampf(0.25 + chosen[j][0] * 2.0, 0.25, 1.0)
		else:
			ps.emitting = false
			if fl.smoke:
				fl.smoke.emitting = false

## A splash on a wall: a scorch (or a green stain) where it hit, and for fire a lick of flame.
func _wall_mark(p: Vector3, n: Vector3, acid: bool) -> void:
	if headless or _wall_marks > 60 or m.fx == null:
		return
	_wall_marks += 1
	var dcl := Decal.new()
	dcl.texture_albedo = m.fx.texture("splat")
	dcl.modulate = Color(0.45, 0.75, 0.2, 0.85) if acid else Color(0.08, 0.06, 0.05, 0.8)
	dcl.size = Vector3(0.35, 0.3, 0.35)
	add_child(dcl)
	var up := n
	var side := up.cross(Vector3.UP if absf(up.y) < 0.9 else Vector3.RIGHT).normalized()
	dcl.global_transform = Transform3D(Basis(side, up, side.cross(up)), p)
	var dr := weakref(dcl)   # (weak: the match may be gone before the mark fades)
	var me := weakref(self)
	get_tree().create_timer(20.0, false).timeout.connect(func():
		var d = dr.get_ref()
		if d:
			d.queue_free()
		var t = me.get_ref()
		if t:
			t._wall_marks -= 1)
	if not acid and _wall_fires < 8:
		# A lick of flame on the wall where it struck, burning out in a few seconds.
		var holder := Node3D.new()
		add_child(holder)
		holder.global_position = p + n * 0.06
		m.fx.emitter("fire", holder, 14, 0.12)
		var sm: GPUParticles3D = m.fx.emitter("fire_smoke", holder, 6, 0.1)
		if sm:
			sm.position = Vector3(0, 0.25, 0)
		_wall_fires += 1
		var hr := weakref(holder)
		var me2 := weakref(self)
		get_tree().create_timer(2.0 + randf() * 2.0, false).timeout.connect(func():
			var t = me2.get_ref()
			if t:
				t._wall_fires -= 1
			var h = hr.get_ref()
			if h:
				h.queue_free())

# ---------- What breaks where ----------

## A pot (or an arrow, a dart, a stone) went off at `p`: on `hit_char`'s `hit_part` if it
## struck someone, else on the sand.
## Every pot breaks like a pot, whatever was in it: glazed shards flung off the way it was going
## and bouncing on the sand, a puff of clay dust, a splash of what it held, a crack of clay.
const CONTENTS := {"pot_fire": Color(1.0, 0.5, 0.12), "pot_acid": Color(0.56, 0.86, 0.22), "pot_oil": Color(0.25, 0.22, 0.08), "pot_honey": Color(0.95, 0.66, 0.12), "pot_garum": Color(0.55, 0.4, 0.18), "pot_sand": Color(0.86, 0.76, 0.52), "pot_smoke": Color(0.5, 0.5, 0.52), "pot_bees": Color(0.95, 0.75, 0.15), "pot_mystery": Color(0.85, 0.3, 0.7), "pot_nail": Color(0.55, 0.57, 0.6), "pot_caltrops": Color(0.3, 0.3, 0.3), "pot_chickens": Color(1.0, 0.95, 0.85), "pot_goat": Color(0.9, 0.88, 0.8), "pot_thunder": Color(0.4, 0.3, 0.5), "pot_fireball": Color(1.0, 0.45, 0.1)}
func shatter(p: Vector3, type: String, dir = null) -> void:
	m.sfx("shatter", p, 1.0)
	var fx: Fx = m.fx
	if fx == null:
		return
	var glaze := Color.hex(int(Items.TYPES.get(type, {}).get("pot", 0x8a6a4a)) << 8 | 0xff)
	var d: Vector3 = (dir as Vector3) if dir is Vector3 and (dir as Vector3).length_squared() > 1e-4 else Vector3.UP
	var fling := (d.normalized() * Vector3(1, 0, 1) + Vector3(0, 1.2, 0)).normalized()
	fx.burst("debris", p, 28, fling, 1.2, glaze.darkened(0.15))
	fx.burst("debris", p, 14, Vector3.UP, 0.8, Color(0.7, 0.45, 0.3))   # the bare clay inside
	fx.burst("dust", p, 18, Vector3.UP, 0.8, Color(0.72, 0.55, 0.4, 0.5))
	fx.burst("bloodmist", p + Vector3(0, 0.1, 0), 16, fling, 1.0, Color(CONTENTS.get(type, glaze), 0.6))
	if p.y < 0.6:
		fx.mark("splat", Vector3(p.x, 0.01, p.z), 0.6)

func explode(type: String, p: Vector3, owner_ = null, dir = null, hit_char = null, hit_part = null, power := 1.0) -> void:
	var pot := type.begins_with("pot_") and not ["pot_bolt", "pot_dart", "pot_discus", "pot_harpoon", "pot_bola", "pot_bignet", "pot_anvil"].has(type) and not type.begins_with("pot_arrow")
	if pot:
		shatter(p, type, dir)
	match type:
		"pot_fireball":
			# Vulcan's fire: a ball of flame with a shock in it (a thunder pot's little brother),
			# burning what it breaks on and a small pool of fire where it fell.
			m.sfx("thud", p, 0.9)
			flash(p, Color(1.0, 0.55, 0.2), 12.0, 8.0)
			if m.fx:
				m.fx.burst("blastfire", p + Vector3(0, 0.2, 0), 90, Vector3.UP, 1.6)
				m.fx.burst("smoke", p + Vector3(0, 0.4, 0), 40, Vector3.UP, 1.3)
				m.fx.burst("sparks", p, 60, Vector3.UP, 1.8)
				m.fx.mark("scorch", p, 1.8)
			if m.role == "host":
				m._send_fx("boom", p, 3)
			blast(p, 2.6, 22.0, owner_)
			splash_burning(p, dir, 30, owner_, hit_part if hit_char and hit_char.alive else null, hit_char if hit_char and hit_char.alive else null)
			for k in 4:
				add_liquid("fire", Vector3(p.x + randf_range(-0.3, 0.3), _floor_y(p), p.z + randf_range(-0.3, 0.3)), 0.22, owner_)
			if owner_:
				m.crowd_add(owner_, 6, "Vulcan's fire")
		"pot_thunder":
			m.sfx("thud", p, 1.0)
			flash(p, Color(1.0, 0.8, 0.55), 14.0, 10.0)
			if m.fx:
				m.fx.burst("blastfire", p + Vector3(0, 0.25, 0), 70, Vector3.UP)
				m.fx.burst("dust", p, 140, Vector3.UP, 2.2)
				m.fx.burst("smoke", p + Vector3(0, 0.4, 0), 50, Vector3.UP, 1.5)
				m.fx.burst("sparks", p, 120, Vector3.UP, 2.0)
				m.fx.burst("debris", p, 50, Vector3.UP, 1.6)
				m.fx.mark("scorch", p, 2.6)
			blast(p, 3.8, 44.0, owner_)
			for x in _near(p, 3.5):
				var c = x.c
				var f: float = 1.0 - x.d / 3.5
				c.concussion = minf(1.0, c.concussion + 0.55 * f)
				var out: Vector3 = c.torso.global_position - p
				out.y = 0.5
				out = out.normalized()
				c.torso.apply_central_impulse(Vector3(out.x * 160.0 * f, 60.0 * f, out.z * 160.0 * f))
				if f > 0.35 and not c.mods.get("unstoppable", false):
					c.fall(1.6, true)
				if owner_:
					c.last_attacker = owner_
			m.feed.emit("BOOM!")
		"pot_nail":
			m.sfx("clang", p, 0.6)
			# The pot bursts into a hail of nails flying out every way, up, down and all round
			# (a few carried on with the pot). Each
			# is a real little dart: it goes in only where it meets a body and stays in it. The
			# man it broke on takes the nails that go his way.
			var fwd: Vector3 = (dir as Vector3).normalized() if dir is Vector3 and (dir as Vector3).length_squared() > 1e-4 else Vector3.ZERO
			for i in NAILS:
				var a := randf() * TAU
				var y := -0.55 + randf() * 1.45
				var d := Vector3(cos(a) * sqrt(1.0 - y * y), y, sin(a) * sqrt(1.0 - y * y))
				if fwd != Vector3.ZERO and randf() < 0.2:
					d = (d * 0.55 + fwd).normalized()   # carried on the way the pot was going
				# From all round the burst, each a little way out along its own line, at its own
				# speed: let go from one spot, a hundred of them went into the one voxel the pot
				# broke on and stood there in a clump.
				var from := Vector3(p.x, maxf(0.15, p.y), p.z) - fwd * 0.06 + d * (0.12 + randf() * 0.22) + Vector3(randf_range(-0.12, 0.12), randf_range(-0.08, 0.12), randf_range(-0.12, 0.12))
				from.y = maxf(0.08, from.y)
				var it: Dictionary = m.items.spawn("nail", from, d * (16.0 + randf() * 20.0), owner_)
				it.from_char = hit_char
		"pot_sand":
			add_zone("sand", p, 3.2, 6.0, owner_)
			m.sfx("slap", p)
		"pot_fire":
			# Broken on the ground, most of it is a pool there at once; the rest flies.
			if p.y < 0.35 or hit_char == null:
				for k in 9:
					add_liquid("fire", Vector3(p.x + randf_range(-0.25, 0.25), _floor_y(p), p.z + randf_range(-0.25, 0.25)), 0.25, owner_)
			splash_burning(p, dir, 48, owner_, hit_part if hit_char and hit_char.alive else null, hit_char if hit_char and hit_char.alive else null)
			m.sfx("slash", p, 1.0)
		"pot_acid":
			if p.y < 0.35 or hit_char == null:
				for k in 9:
					add_liquid("acid", Vector3(p.x + randf_range(-0.25, 0.25), _floor_y(p), p.z + randf_range(-0.25, 0.25)), 0.3, owner_)
			splash_burning(p, dir, 48, owner_, hit_part if hit_char and hit_char.alive else null, hit_char if hit_char and hit_char.alive else null, "acid")
		"pot_caltrops":
			# The pot bursts and scatters real caltrops over the sand: each lands with a spike
			# up, and whoever walks over them (anyone) gets one in the foot.
			for i in CALTROPS:
				var a := randf() * TAU
				var out := 1.2 + randf() * 3.4
				m.items.spawn("caltrop", Vector3(p.x + cos(a) * 0.08, maxf(0.2, p.y), p.z + sin(a) * 0.08), Vector3(cos(a) * out, 1.0 + randf() * 2.5, sin(a) * out), owner_)
			m.feed.emit("Caltrops all over the sand. Watch your step.")
		"pot_bees":
			m.sfx("slap", p)
			var stung := false
			for x in _near(p, 3.0):
				if x.c == owner_:
					continue
				x.c.bee_timer = 5.0
				if owner_:
					x.c.last_attacker = owner_
				m.feed.emit("%s is covered in bees!" % x.c.display_name)
				stung = true
			# The swarm comes out of the broken hive and goes for the nearest foe of the thrower
			# (anyone but him, if he has no side) within nine metres, a cloud of bees in the air
			# that flies at him and covers him when it gets there. (A pot that broke on the sand
			# short of the man did nothing anyone could see: user.)
			if not stung:
				var my_team = null
				for e in m.entities:
					if e.f == owner_:
						my_team = e.get("team")
				var best = null
				for x in _near(p, 9.0):
					if x.c == owner_ or (my_team != null and x.e.get("team") == my_team):
						continue
					best = x.c
					break
				if best != null:
					var sw := {"pos": p + Vector3(0, 0.4, 0), "target": best, "owner": owner_, "t": 0.0, "node": null}
					if not headless and m.fx:
						var node := Node3D.new()
						m.add_child(node)
						node.global_position = sw.pos
						var em = m.fx.emitter("bees", node, 160, 0.4)
						if em:
							em.local_coords = false
						sw.node = node
					swarms.append(sw)
					m.feed.emit("The hive breaks open: the swarm goes for %s!" % best.display_name)
		"pot_goat":
			m.spawn_beast({"beast": "goat", "team": 2, "pos": Vector3(p.x, 0.1, p.z), "yaw": 0.0, "harmless": true})
			m.feed.emit("The crowd laughs. Every beast wants the goat.")
		"pot_bola":
			for x in _near(p, 1.5):
				var c = x.c
				if c == owner_:
					continue
				c.set_net(true, 2.5)
				c.fall(4.0 if c.mods.get("cyclops", false) else 1.6, true)
				if owner_:
					c.last_attacker = owner_
				m.feed.emit("%s's legs are tied up" % c.display_name)
			m.sfx("slap", p)
		"pot_oil":
			add_zone("oil", Vector3(p.x, 0, p.z), 2.6, 14.0, owner_)
		"pot_garum":
			var dropped := 0
			for x in _near(p, 3.0):
				var c = x.c
				if c == owner_ or c.kind == "beast":
					continue
				c.stagger = minf(1.0, c.stagger + 0.5)
				c.concussion = minf(1.0, c.concussion + 0.2)
				for side in ["R", "L"]:
					var w = c.weapons.get(side)
					if w and not w.is_shield:
						c.release(side)
						dropped += 1
				if owner_:
					c.last_attacker = owner_
			m.feed.emit("Rotten fish sauce! %s" % ("%d weapon%s dropped in disgust." % [dropped, "s" if dropped > 1 else ""] if dropped else "The crowd holds its nose."))
			if owner_:
				m.crowd_add(owner_, 4, "disgusting")
		"pot_honey":
			add_zone("honey", Vector3(p.x, 0, p.z), 2.0, 12.0, owner_)
			# Bees love it: whoever the honey splashed over is covered in them for a while.
			for x in _near(p, 1.6):
				if x.c == owner_:
					continue
				x.c.bee_timer = maxf(float(x.c.bee_timer), 3.5)
				if owner_:
					x.c.last_attacker = owner_
				m.feed.emit("%s is dripping honey, and the bees have found him!" % x.c.display_name)
		"pot_smoke":
			add_zone("smoke", Vector3(p.x, 0, p.z), 3.0, 9.0, owner_)
			m.sfx("whoosh", p)
		"pot_mystery":
			var pick: String = ["pot_thunder", "pot_nail", "pot_goat", "pot_bees", "pot_chickens", "pot_confetti", "pot_grape", "pot_oil"][randi() % 8]
			m.feed.emit("The mystery amphora was... %s!" % ("a grape" if pick == "pot_grape" else ("confetti" if pick == "pot_confetti" else pick.trim_prefix("pot_"))))
			explode(pick, p, owner_)
		"pot_confetti":
			if m.fx:
				m.fx.burst("confetti", p + Vector3(0, 0.5, 0), 160, Vector3.UP, 1.3)
			m.sfx("cheer", p)
			if owner_:
				m.crowd_add(owner_, 15, "confetti!")
		"pot_grape":
			m.feed.emit("A single grape rolls out. The crowd is silent.")
			if owner_:
				m.crowd_add(owner_, -3, "a grape")
		"pot_chickens":
			var chicken := Data.preset("chicken")
			for i in 6:
				var w = m.spawn_loose_weapon(chicken, p + Vector3(randf_range(-0.2, 0.2), 0.4 + i * 0.1, randf_range(-0.2, 0.2)))
				if w:
					w.linear_velocity = Vector3(randf_range(-3.5, 3.5), 4.0 + randf() * 4.0, randf_range(-3.5, 3.5))
			m.feed.emit("CHICKENS EVERYWHERE!")
			if owner_:
				m.crowd_add(owner_, 10, "chickens")
		"pot_harpoon":
			var hv = hit_char if hit_char and hit_char != owner_ else null
			if hv == null:
				for x in _near(p, 1.2):
					if x.c != owner_:
						hv = x.c
						break
			if hv == null:
				return
			var hdir: Vector3 = (p - owner_.torso.global_position).normalized() if owner_ else Vector3(0, 0, 1)
			_hit(hv, hv.torso, 14.0, "point", hv.torso.global_position, hdir, owner_)
			hv.torso.bleed += 1.5
			if owner_:
				var pull: Vector3 = owner_.torso.global_position - hv.torso.global_position
				pull.y = 0.4
				hv.torso.apply_central_impulse(pull.normalized() * 260.0 * hv.S * hv.S)
				if hv.state == "stand":
					hv.fall(1.2)
				m.feed.emit("%s reeled in %s!" % [owner_.display_name, hv.display_name])
				m.crowd_add(owner_, 8, "catch of the day")
		"pot_bolt", "pot_arrow", "pot_arrow_fire", "pot_arrow_poison", "pot_arrow_ice", "pot_dart", "nail":
			_dart(type, p, owner_, dir, hit_char, hit_part, power)
		"pot_discus":
			m.sfx("clang", p, 0.5)
			var dv = _near(p, 1.1)
			if dv.is_empty():
				return
			var c = dv[0].c
			var part: VoxelPart = c.head if c.head.global_position.distance_to(p) < 0.35 else c.torso
			var ddir: Vector3 = p - owner_.torso.global_position if owner_ else Vector3(0, 0, 1)
			ddir.y = 0.0
			_hit(c, part, 16.0, "blunt", part.global_position, ddir.normalized(), owner_, {"hardness": 0.8})
			if c == owner_:
				m.feed.emit("%s got hit by their own discus" % c.display_name)
		"pot_bignet":
			var n := 0
			for x in _near(p, 1.8):
				if x.c == owner_:
					continue
				x.c.set_net(true, 4.0)
				n += 1
				if owner_:
					x.c.last_attacker = owner_
			m.feed.emit("%d caught in the big net" % n)
		"rock":
			if hit_char and hit_part:
				_hit(hit_char, hit_part, 9.0, "blunt", p, dir if dir != null else Vector3.DOWN, owner_, {"hardness": 0.7})
		"net":
			if hit_char:
				hit_char.set_net(true, 3.0)

func _dart(type: String, p: Vector3, owner_, dir, hit_char, hit_part, power := 1.0) -> void:
	# A nail only wounds what it actually met: one that reaches the sand lies there.
	if type == "nail" and (hit_char == null or hit_part == null):
		return
	if type == "pot_arrow_fire":
		add_zone("fire", Vector3(p.x, 0.0, p.z), 0.8, 3.0, owner_)
	var c = hit_char if hit_char and hit_char.alive and hit_char != owner_ else null
	if c == null:
		for x in _near(p, 0.9 if type == "pot_dart" else 1.0):
			if x.c != owner_:
				c = x.c
				break
	if c == null:
		return
	var part: VoxelPart = hit_part if hit_part and c.parts.has(hit_part) and not hit_part.severed else null
	if part == null:
		var bd := INF
		for q in c.parts:
			if q.severed:
				continue
			var d: float = q.global_position.distance_to(p)
			if d < bd:
				bd = d
				part = q
	if part == null:
		return
	var hdir: Vector3 = dir if dir != null else ((p - owner_.torso.global_position).normalized() if owner_ else Vector3(0, 0, 1))
	var was_alive: bool = c.alive
	var arrow := type.begins_with("pot_arrow")
	var headshot: bool = part == c.head and (arrow or type == "pot_bolt")
	# An arrow strikes as hard as the bow was drawn (a half draw stings, a full one goes deep);
	# a crossbow's bolt always has the whole of the prod behind it.
	if type == "nail":
		# A nail is a sting, not a stab: it goes in and stays, it bleeds a little. Out of one
		# burst only the first dozen in a body count; the rest just stick (a dragon catches half
		# the hail, and every nail at full weight bled it dry in seconds and stalled the game).
		var now := int(VoxelPart.clock() * 1000.0)
		var nh: Array = c.get_meta("nail_hits", [0, 0])
		if now - int(nh[0]) > 1500:
			nh = [now, 0]
		nh[1] = int(nh[1]) + 1
		c.set_meta("nail_hits", nh)
		if int(nh[1]) <= 12:
			_hit(c, part, 1.2, "point", p, hdir, owner_)
			part.bleed += 0.06 / maxf(1.0, c.S)
		part.stick("nail", p, hdir)
		return
	var J := (17.0 if type == "pot_bolt" else ((3.0 + 13.0 * clampf(power, 0.0, 1.0)) if arrow else 10.0)) * ((1.2 if c.S >= 1.5 else 1.8) if headshot else 1.0)
	_hit(c, part, J, "point", p, hdir, owner_)
	if headshot:
		c.concussion = minf(1.0, c.concussion + (0.2 if c.S >= 1.5 else 0.5))
		m.feed.emit("HEADSHOT! %s%s's head%s" % [(owner_.display_name + " puts one in ") if owner_ else "", c.display_name, ". Down and out." if was_alive and not c.alive else ""])
	if type == "pot_bolt":
		part.bleed += 1.0
		part.stick("pot_bolt", p, hdir)
	if arrow:
		part.bleed += (0.5 + 1.0 * clampf(power, 0.0, 1.0)) / maxf(1.0, c.S * 0.6)
		part.stick(type, p, hdir)
	if type == "pot_arrow_fire":
		m.add_spot(c, part, "fire", 4.0, owner_, p)
	if type == "pot_arrow_poison":
		part.bleed += 2.0
		c.slow(3.0, 0.7)
		m.add_spot(c, part, "acid", 5.0, owner_, p)
	if type == "pot_arrow_ice":
		c.slow(4.0, 0.45)
		burst(p, Color(0.66, 0.91, 1.0), 12, 1.5, 0.6, 0.03)

## What an item event means: a splat (it broke, or struck someone), food eaten, a banana
## slipped on, a cheese wheel bowling a man over, a boomerang caught.
func on_item(ev: Dictionary) -> void:
	var c = ev.get("char")
	var it: Dictionary = ev.item
	var owner_ = it.get("owner")
	match ev.kind:
		"strike":
			# A heavy thing's blow is its momentum: 30 kg of iron at a walking throw's speed
			# crushes what it lands on and puts a man down.
			var part: VoxelPart = ev.part
			var spd: float = ev.speed
			var J := minf(95.0, float(ev.mass) * spd * 0.42)
			m.sfx("thud", ev.p, 1.0)
			burst(ev.p, Color(0.6, 0.5, 0.4), 14, 2.0)
			if part and c and c.alive:
				# It crushes what it lands on: a dent the size of the blow, flesh and bone.
				var crush := minf(0.12, 0.03 + J * 0.0009) * sqrt(float(c.S))
				_hit(c, part, J, "blunt", ev.p, ev.dir, owner_, {"hardness": 1.0, "crush": crush, "heavy": clampf(J / 60.0, 0.0, 1.0)})
				var push: Vector3 = (ev.dir as Vector3) * float(ev.mass) * spd * 0.35
				c.torso.apply_central_impulse(Vector3(push.x, maxf(0.0, push.y), push.z))
				if c.state == "stand" and J > 25.0 and not c.mods.get("unstoppable", false):
					c.fall(2.0)
				m.feed.emit("An anvil hits %s. Classic." % c.display_name)
				if owner_ and owner_ != c:
					m.crowd_add(owner_, 10, "anvil")
		"land":
			m.sfx("thud", ev.p, minf(1.0, float(ev.speed) / 8.0))
			if m.fx:
				m.fx.burst("dust", ev.p, 16, Vector3.UP, 0.8)
				m.fx.mark("crater", ev.p, 0.5)
		"splat":
			if ev.type == "tomato":
				if c:
					m.feed.emit("SPLAT! A tomato hits %s" % c.display_name)
					m.crowd_add(c, -2, "tomato")
				burst(ev.p, Color(0.82, 0.16, 0.11), 10, 1.5, 0.5, 0.03)
			else:
				explode(ev.type, ev.p, owner_, ev.get("dir"), c, ev.get("part"), float(it.get("power", 1.0)))
		"eat":
			match ev.type:
				"bread":
					c.blood = minf(100.0, c.blood + 30.0)
					m.feed.emit("%s eats the bread" % c.display_name)
				"wine":
					c.drink_wine()
					m.feed.emit("%s downs the wine" % c.display_name)
				"coin":
					m.feed.emit("%s pockets a gold coin" % c.display_name)
					m.on_coin(c)
		"caltrop":
			var part: VoxelPart = ev.part
			var foot: bool = part.def.get("leg", false) and c.state == "stand"
			var Jc := 7.0 * sqrt(float(c.S)) if foot else 4.0
			var was: bool = c.alive
			var res: Dictionary = c.apply_hit(part, {"impulse": Jc, "type": "point", "hardness": 0.95, "sharpness": 1.0, "point": ev.p, "dir": Vector3.UP, "axis": Vector3.UP})
			part.bleed += 0.8
			if not headless:
				part.stick("caltrop", ev.p, Vector3.UP)
			if foot:
				# He snatches the foot up and hops: slower for a while, the leg buckling under him.
				c.slow(2.5, 0.5)
				part.flinch_t = maxf(part.flinch_t, 0.8)
				c.stagger = minf(1.0, c.stagger + 0.35 / float(c.S))
				m.feed.emit("%s steps on a caltrop!" % c.display_name)
				m.crowd_add(c, -2, "caltrop")
			if owner_ and owner_ != c:
				c.last_attacker = owner_
			m.report_hit({"kind": "hit", "p": ev.p, "dir": Vector3.UP, "J": Jc, "type": "point", "char": c, "part": part, "attacker": owner_, "res": res, "killed": was and not c.alive})
		"slip":
			c.fall(1.6, true)
			c.torso.apply_central_impulse(Vector3(0, 30.0, 0))
			m.feed.emit("%s slipped on a banana peel!" % c.display_name)
			m.crowd_add(c, -3, "banana")
			m.sfx("whoosh", ev.p)
		"ram":
			c.fall(1.4, true)
			m.feed.emit("%s is bowled over by a cheese wheel" % c.display_name)
			if owner_:
				m.crowd_add(owner_, 6, "cheese")
		"return":
			m.feed.emit("%s caught the boomerang" % c.display_name)
		"kick":
			if m.modes:
				m.modes.kick_ball(ev)

# ---------- Zones ----------

func add_zone(type: String, p: Vector3, r: float, t: float, owner_ = null) -> Dictionary:
	var z := {"id": next_zone, "type": type, "p": p, "r": r, "t": t, "owner": owner_, "tick": 0.0, "node": null}
	next_zone += 1
	if not headless:
		var mi := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = r
		cm.bottom_radius = r
		cm.height = 1.6 if type == "sand" or type == "smoke" else 0.02
		var mat := StandardMaterial3D.new()
		mat.albedo_color = ZONE_COLORS.get(type, Color.WHITE)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED if type == "fire" else BaseMaterial3D.SHADING_MODE_PER_PIXEL
		if type == "sand" or type == "smoke":
			mat.albedo_color.a = 0.3
		cm.material = mat
		if type == "fire" or type == "acid" or type == "oil" or type == "honey":
			cm.material = _zone_material(type, r)
			# Room for the splash's lobes and droplets (the shader draws the shape inside).
			cm.top_radius = r * 1.7
			cm.bottom_radius = r * 1.7
		mi.mesh = cm
		add_child(mi)
		mi.global_position = Vector3(p.x, 0.8 if type == "sand" or type == "smoke" else 0.02, p.z)
		z.node = mi
	zones.append(z)
	if m.fx and (type == "fire" or type == "acid"):
		m.fx.mark("scorch" if type == "fire" else "acid", p, r * 2.2)
	if m.fx and type == "fire" and r >= 0.5 and t > 2.0 and z.node:
		var fl: GPUParticles3D = m.fx.emitter("fire", z.node, int(clampf(r * 40.0, 12.0, 80.0)), r * 0.8)
		if fl:
			fl.emitting = true
	if m.fx and type == "fire" and t > 1.0 and z.node:
		# Smoke off it, as much as the fire is big.
		var sm: GPUParticles3D = m.fx.emitter("fire_smoke", z.node, int(clampf(r * 26.0, 8.0, 40.0)), r * 0.6)
		if sm:
			sm.position = Vector3(0, 0.4, 0)
	if m.fx and type == "sand" and z.node:
		# The cloud itself: voxel grains of sand turning in the air, and the haze thinner.
		(z.node.mesh.material as StandardMaterial3D).albedo_color.a = 0.2
		var sc: GPUParticles3D = m.fx.emitter("sandcloud", z.node, int(clampf(r * 150.0, 80.0, 500.0)), r * 0.85)
		if sc:
			var spm := sc.process_material as ParticleProcessMaterial
			spm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
			spm.emission_box_extents = Vector3(r * 0.8, 0.75, r * 0.8)
			sc.emitting = true
	if m.fx and type == "acid" and z.node:
		var pz: GPUParticles3D = m.fx.emitter("poison", z.node, int(clampf(r * 30.0, 8.0, 60.0)), r * 0.8)
		if pz:
			pz.emitting = true
	if m.role == "host":
		Net.send_all("zone", {"type": type, "p": [p.x, p.y, p.z], "r": r, "t": t})
	return z

## Weapons near the ground in a fire or acid pool, held or loose, burn or fume; so do items
## lying in one (food and cloth flare and smoke, metal glows). Drawing only.
func _show_burning() -> void:
	var ws: Array = m.combat.loose_weapons.duplicate() if m.combat else []
	for e in m.entities:
		if e.f and e.f.get("weapons") is Dictionary:
			for side in e.f.weapons:
				if e.f.weapons[side]:
					ws.append(e.f.weapons[side])
	for w in ws:
		if not is_instance_valid(w) or w.is_hazard:
			continue
		var p: Vector3 = w.global_position
		var low := p.y < 0.7
		w.set_burn(low and inside("fire", p), low and inside("acid", p))
	_burn_items()

## Items (m.items) lying in fire or acid: each gets its flames or fumes once.
func _burn_items() -> void:
	if m.items == null:
		return
	for it in m.items.list:
		var n = it.get("node")
		if n == null or not is_instance_valid(n) or n.has_meta("burning"):
			continue
		var p: Vector3 = it.p
		if p.y > 0.5:
			continue
		var fire := inside("fire", p)
		var acid := inside("acid", p)
		if not fire and not acid:
			continue
		var metal: bool = str(it.type) in ["coin", "rock", "nail", "caltrop", "pot_anvil", "pot_discus", "boomerang"]
		var e := BurnFx.make(n, "metal" if metal else "cloth", fire, 0.5)
		if e:
			n.set_meta("burning", true)

## A burning or poisoned patch drawn on the sand's voxel grid (shaders/zone.gdshader).
static func _zone_material(type: String, r: float) -> ShaderMaterial:
	var sm := ShaderMaterial.new()
	sm.shader = load("res://shaders/zone.gdshader")
	sm.set_shader_parameter("radius", r)
	if type == "fire":
		sm.set_shader_parameter("color_a", Color(1.0, 0.72, 0.25, 0.9))
		sm.set_shader_parameter("color_b", Color(0.45, 0.07, 0.02, 0.75))
		sm.set_shader_parameter("glow", 2.2)
		sm.set_shader_parameter("speed", 6.0)
	elif type == "oil":
		sm.set_shader_parameter("color_a", Color(0.22, 0.26, 0.12, 0.9))
		sm.set_shader_parameter("color_b", Color(0.06, 0.07, 0.03, 0.85))
		sm.set_shader_parameter("glow", 0.15)
		sm.set_shader_parameter("speed", 0.6)
	elif type == "honey":
		sm.set_shader_parameter("color_a", Color(1.0, 0.75, 0.25, 0.92))
		sm.set_shader_parameter("color_b", Color(0.75, 0.42, 0.06, 0.85))
		sm.set_shader_parameter("glow", 0.35)
		sm.set_shader_parameter("speed", 0.4)
	else:
		sm.set_shader_parameter("color_a", Color(0.62, 0.95, 0.25, 0.85))
		sm.set_shader_parameter("color_b", Color(0.16, 0.36, 0.06, 0.7))
		sm.set_shader_parameter("glow", 0.9)
		sm.set_shader_parameter("speed", 2.0)
	return sm

func inside(type: String, pos: Vector3) -> bool:
	for z in zones:
		if z.type == type and Vector2(pos.x - z.p.x, pos.z - z.p.z).length() < z.r:
			return true
	return false

## Bots in sand or smoke, or covered in bees, cannot fight properly.
func impaired(c) -> bool:
	return c.bee_timer > 0.0 or inside("sand", c.torso.global_position) or inside("smoke", c.torso.global_position)

## The height of what is under `p` (the sand, or the crate it broke on).
func _floor_y(p: Vector3) -> float:
	var hit := _ray(p + Vector3(0, 0.3, 0), p - Vector3(0, 1.5, 0))
	return float(hit.position.y) if not hit.is_empty() else 0.0

func update(dt: float) -> void:
	_update_drops(dt)
	_update_wet(dt)
	for z in zones.duplicate():
		z.t -= dt
		z.tick -= dt
		if z.node and z.type == "fire" and z.node.mesh.material is StandardMaterial3D:
			z.node.mesh.material.albedo_color.a = 0.4 + sin(m.time * 20.0) * 0.1
		if m.role != "guest" and z.tick <= 0.0:
			z.tick = 0.6 if z.type == "caltrops" else 0.5
			for e in m.entities:
				var c = e.f
				if not c.alive or Vector2(c.torso.global_position.x - z.p.x, c.torso.global_position.z - z.p.z).length() > z.r:
					continue
				var v: Vector3 = c.torso.linear_velocity
				match z.type:
					"oil":
						if c.state != "stand" or Vector2(v.x, v.z).length() < 1.1:
							continue
						c.fall(1.4)
						c.torso.apply_central_impulse(Vector3(v.x * 8.0, 40.0, v.z * 8.0))
						m.crowd_add(c, -3, "slip")
						m.feed.emit("%s slipped in the olive oil" % c.display_name)
					"honey":
						c.slow(0.7, 0.3)
						if c.bee_timer > 0.0:
							c.bee_timer += 0.3
					"fire":
						var low: float = c.S * 0.65
						for part in c.parts:
							if not part.severed and (c.state != "stand" or part.global_position.y < low) and randf() < 0.6:
								m.add_spot(c, part, "fire", 2.5, z.owner, Vector3(part.global_position.x, 0, part.global_position.z))
						c.blood = maxf(0.0, c.blood - 0.5)
					"acid":
						var low2: float = c.S * 0.45
						for part in c.parts:
							if not part.severed and (c.state != "stand" or part.global_position.y < low2) and randf() < 0.5:
								m.add_spot(c, part, "acid", 2.0, z.owner, Vector3(part.global_position.x, 0, part.global_position.z))
					"caltrops":
						if Vector2(v.x, v.z).length() < 0.5:
							continue
						var shin = null
						for n in ["shinL", "shinR"]:
							var sp = c.by_name.get(n)
							if sp and not sp.severed:
								shin = sp
								break
						if shin:
							var sp2: Vector3 = shin.global_position
							_hit(c, shin, 5.0, "point", Vector3(sp2.x, 0.05, sp2.z), Vector3.UP, z.owner)
		if z.t <= 0.0:
			if z.node:
				z.node.queue_free()
			zones.erase(z)
	# Swarms in the air fly at their man, a little wavering, and cover him when they arrive.
	if not swarms.is_empty():
		for sw in swarms.duplicate():
			var tgt = sw.target
			if not is_instance_valid(tgt) or not tgt.alive or sw.t > 6.0:
				if sw.node and is_instance_valid(sw.node):
					sw.node.queue_free()
				swarms.erase(sw)
				continue
			sw.t += dt
			var goal: Vector3 = tgt.torso.global_position
			var to: Vector3 = goal - sw.pos
			var step := minf(to.length(), 5.5 * dt)
			sw.pos += to.normalized() * step + Vector3(sin(sw.t * 9.0), cos(sw.t * 7.0), sin(sw.t * 11.0)) * 0.6 * dt
			if sw.node and is_instance_valid(sw.node):
				sw.node.global_position = sw.pos
			if to.length() < 0.7 * float(tgt.S):
				if m.role != "guest":
					tgt.bee_timer = maxf(float(tgt.bee_timer), 5.0)
					if sw.owner:
						tgt.last_attacker = sw.owner
				m.feed.emit("%s is covered in bees!" % tgt.display_name)
				if sw.node and is_instance_valid(sw.node):
					sw.node.queue_free()
				swarms.erase(sw)
	# A swarm of voxel bees round whoever they cover (only the look; drawn wherever the timer runs).
	if not headless and m.fx:
		for e in m.entities:
			var bc = e.f
			if not is_instance_valid(bc) or bc.torso == null:
				continue
			var swarm = bc.get_meta("bee_swarm") if bc.has_meta("bee_swarm") else null
			var want: bool = bc.bee_timer > 0.0 and bc.alive
			if want and swarm == null:
				swarm = m.fx.emitter("bees", bc.torso, 140, 0.55)
				if swarm:
					swarm.local_coords = true
					bc.set_meta("bee_swarm", swarm)
			if swarm and is_instance_valid(swarm):
				swarm.emitting = want
	# Weapons and items lying in a fire or a pool of acid look it (only the look).
	if not headless and m.fx and not zones.is_empty():
		_show_burning()
	# Bees sting the man they cover now and then.
	if m.role != "guest":
		for e in m.entities:
			var c = e.f
			if c.bee_timer > 0.0:
				c.bee_timer -= dt
				# (Four stings a second that are felt: three a second at a third the sting were
				# a swarm that did nothing: user.)
				if c.alive and randf() < dt * 4.0:
					var part: VoxelPart = c.parts[randi() % c.parts.size()]
					if not part.severed:
						_hit(c, part, 6.0, "point", part.global_position, Vector3.DOWN, c.last_attacker, {"hardness": 0.6, "sharpness": 0.7})
						c.stagger = minf(1.0, c.stagger + 0.2)
						c.pain = minf(1.0, float(c.pain) + 0.15)

func clear() -> void:
	for z in zones:
		if z.node:
			z.node.queue_free()
	zones.clear()
	for sw in swarms:
		if sw.node and is_instance_valid(sw.node):
			sw.node.queue_free()
	swarms.clear()
	drops.clear()
	wet.clear()

# ---------- The hotbar ----------

## A team-mate down within reach of `e` (the nearest), or null.
func _downed_friend(e: Dictionary):
	var p: Vector3 = e.f.torso.global_position
	var best = null
	var bd := 1.8 * float(e.f.S)
	for o in m.entities:
		if o == e or o.team != e.team or o.kind == "beast" or not is_instance_valid(o.f) or not o.f.alive:
			continue
		if o.f.state != "down" and o.f.state != "rising":
			continue
		var d: float = o.f.torso.global_position.distance_to(p)
		if d < bd:
			bd = d
			best = o
	return best

## Uses the kit item in hotbar `slot`: food and bandages at once; anything thrown goes into the
## free hand for a player (aimed and thrown with F), straight at the target for a bot.
func use_item(e: Dictionary, slot: int) -> bool:
	var inv: Dictionary = e.get("inventory", {})
	var bar := hotbar_of(inv)
	if slot < 0 or slot >= bar.size():
		return false
	var id: String = bar[slot]
	var c = e.f
	if not c.alive:
		return false
	# Its number again: back into the kit.
	if c.held_item != null and c.held_item.id == id:
		put_away(e)
		return true
	var fwd := Vector3(sin(c.yaw), 0, cos(c.yaw))
	var player: bool = e.kind == "local" or e.kind == "remote"
	var hand_type = POTS.get(id, {"darts": "pot_dart", "boomerang": "boomerang"}.get(id))
	if hand_type != null and player:
		hold_item(e, hand_type, id)   # still in the kit (and on the hotbar) until it is thrown
		return true
	inv[id] = int(inv[id]) - 1
	match id:
		"telekinesis":
			# The Hand of Jupiter: a man in the crosshair seized in an unseen grip (Social).
			if not m.social.mind_hold(e):
				inv[id] = int(inv[id]) + 1   # nothing to seize: the charge is not spent
				return false
		"bandage":
			# A friend down beside him: the bandage is for the friend, who is on his feet twice
			# as soon. Otherwise his own wounds.
			var friend = _downed_friend(e)
			var who = friend.f if friend else c
			for p in who.parts:
				p.bleed = 0.0
				p.artery = 0.0
				p.stump = false
			who.torso.hp = minf(100.0, who.torso.hp + 15.0)
			if friend:
				who.help_up()
				m.feed.emit("%s bandages %s and helps %s up" % [c.display_name, who.display_name, who.display_name])
			else:
				m.feed.emit("%s bandaged up" % c.display_name)
		"bread":
			c.blood = minf(100.0, c.blood + 40.0)
		"wine":
			c.drink_wine()
		"cheese":
			var cp: Vector3 = c.torso.global_position + fwd * 0.8
			var it: Dictionary = m.items.spawn("cheese", Vector3(cp.x, 0.21, cp.z), fwd * 7.0, c)   # on its edge on the sand
			it.grounded = true
			m.feed.emit("%s bowled a cheese wheel" % c.display_name)
		"bananas":
			for i in [-1, 0, 1]:
				var bp: Vector3 = c.torso.global_position + fwd * 1.2 + Vector3(fwd.z * i * 0.6, 0, -fwd.x * i * 0.6)
				var it2: Dictionary = m.items.spawn("banana", Vector3(bp.x, 0.06, bp.z), Vector3.ZERO, c)
				it2.grounded = true
			m.feed.emit("%s laid a banana trap" % c.display_name)
		_:
			var tgt = m.nearest_enemy(e)
			var aim: Vector3 = tgt.f.torso.global_position if tgt else c.torso.global_position + fwd * 6.0
			var ia = e.get("last_aim")
			if player and ia is Vector3:
				aim = Social.aim_ahead(c, ia, e.get("input", {}).get("look"), e.get("last_aim_from"))   # a player's pot goes to the crosshair
			throw_type(c, hand_type, aim, null, player)
	return true

## A pot readied in the free hand (the left, or the right if the left is busy): held where it
## can be seen until F throws it.
func hold_item(e: Dictionary, type: String, id: String) -> void:
	var c = e.f
	put_away(e)
	var side: String = c.item_hand()
	if side == "":
		return   # no hand left to hold it
	if side == "L" and c.two_handed:
		c.toggle_grip()   # the off hand lets go of the haft to take the pot (H takes it back)
	var node = null
	if not headless:
		node = Items.visual(type)
		c.arm[side].fore.add_child(node)
		node.position = c.hand_point
	c.held_item = {"type": type, "id": id, "node": node, "side": side}
	if e.kind == "local":
		m.feed.emit("%s ready: hold F to aim, let go to throw" % Data.shop.throwables.get(id, {}).get("name", id))

## The readied pot goes back into the kit (its number pressed again, or another pot readied):
## it was never taken out, so nothing is owed.
func put_away(e: Dictionary) -> void:
	var c = e.f
	if c.held_item == null:
		return
	var id: String = c.held_item.id
	drop_held(c)
	if e.kind == "local":
		m.feed.emit("%s put away" % Data.shop.throwables.get(id, {}).get("name", id))

func drop_held(c) -> void:
	if c.held_item == null:
		return
	if c.held_item.node and is_instance_valid(c.held_item.node):
		c.held_item.node.queue_free()
	c.held_item = null

## Throws the readied pot where the player looks (power from the wind-up).
func throw_held(e: Dictionary, inp: Dictionary) -> void:
	var c = e.f
	var h = c.held_item
	if h == null:
		return
	var side: String = c.item_hand()   # (read before the pot leaves the hand)
	drop_held(c)
	var inv: Dictionary = e.get("inventory", {})
	if int(inv.get(h.id, 0)) <= 0:
		return   # the kit ran out under it (shared purse, a sale): nothing to throw
	inv[h.id] = int(inv[h.id]) - 1
	var look = inp.get("look", {"yaw": c.yaw, "pitch": 0.0})
	var power := clampf(float(inp.get("throwPower", 0.8)), 0.3, 1.0)
	var dir := Vector3(sin(look.yaw) * cos(look.pitch), sin(look.pitch), cos(look.yaw) * cos(look.pitch))
	var reach := 4.0 + 10.0 * power
	var aim: Vector3 = c.head.global_position + dir * reach
	if inp.get("aimAt") is Vector3:
		aim = Social.aim_ahead(c, inp.aimAt, look, inp.get("aimFrom"))
	aim.y = maxf(0.1, aim.y)
	throw_type(c, h.type, aim, null, true, power, side)

## How fast a thrown thing leaves the hand, of its full speed, for a wind-up of `power` (0.3, a
## flick, to 1, held to the full).
static func throw_speed_k(power: float) -> float:
	return 0.35 + 0.8 * clampf(power, 0.0, 1.0)

## `straight`: a player's throw flies along the line to the crosshair (the flat one of the two
## arcs that reach it, or along the line itself when it is out of reach), never a lob.
func throw_type(c, type: String, aim: Vector3, _dir, straight := false, power := 0.8, side := "") -> void:
	# From the hand that throws it, a hand's breadth on toward the mark (clear of the fist): it
	# was always the left hand's place, a span over it, whichever hand held it.
	var sd: String = side if side != "" else c.item_hand()
	if sd == "L" and c.two_handed:
		c.toggle_grip()
	var hand: Vector3 = c.hand_world(sd) if sd != "" else c.head.global_position
	var from: Vector3 = hand + (aim - hand).normalized() * 0.12 * c.S if aim.distance_to(hand) > 0.3 else hand
	if type == "pot_dart":
		var fwd: Vector3 = (aim - from)
		fwd.y = 0.0
		fwd = fwd.normalized()
		for i in [-1, 0, 1]:
			var da := aim + Vector3(fwd.z * i * 0.5, i * 0.15, -fwd.x * i * 0.5)
			if straight:
				m.items.spawn("pot_dart", from, Items.flat_shot(da - from, 19.0 * throw_speed_k(1.0)).normalized() * 19.0 * throw_speed_k(power), c)
			else:
				m.items.throw_at("pot_dart", from, da, c, 15.0)
	elif type == "boomerang":
		m.items.throw_at("boomerang", from, aim, c, 12.0, 0.0)
	elif straight:
		# The wind-up is the throw: a quick flick tosses it a few paces (short of a far mark),
		# held to the full it flies hard and far.
		# Along the line a full throw takes to the mark, whatever the wind-up: it says how far,
		# not which way (at its own speed every throw left at another angle: user).
		var full: float = float(THROW_SPEED.get(type, 14.5))
		m.items.spawn(type, from, Items.flat_shot(aim - from, full * throw_speed_k(1.0)).normalized() * full * throw_speed_k(power), c)
	else:
		m.items.throw_at(type, from, aim, c, THROW_SPEED.get(type, 14.5))
	m.sfx("whoosh", from)

# ---------- Weapons that shoot ----------

## A bow: hold the button to draw, let go to loose an arrow where the archer looks (bots at their
## target). Power comes from the draw time and the length of the limbs. A crossbow shoots a bolt
## on a thrust; a flame pole sets alight what its jet plays over.
func update_shooters(dt: float) -> void:
	for e in m.entities:
		var c = e.f
		if c.kind == "beast" or not c.alive:
			continue
		c.off_goal = null
		for side in ["R", "L"]:
			var w = c.weapons.get(side)
			if w == null or not w.design.has("shoots"):
				continue
			var inp: Dictionary = e.get("input", {})
			match String(w.design.shoots):
				"arrow":
					_draw_bow(e, w, inp, dt)
				"bolt":
					# A thrust, or (a player) a click of that hand's button.
					var click := false
					if e.kind == "local" or e.kind == "remote":
						var pw: bool = inp.get("power", false)
						click = pw and not w.get_meta("pw", false)
						w.set_meta("pw", pw)
					_crossbow(e, w, 1.0 if click else float(inp.get("thrust" if side == "R" else "offThrust", 0.0)), dt, inp)
				"flame":
					_flame(e, w, float(inp.get("thrust" if side == "R" else "offThrust", 0.0)), dt)

func _draw_bow(e: Dictionary, w: Weapon, inp: Dictionary, dt: float) -> void:
	var c = e.f
	var held: bool = inp.get("power", false)
	var ys := []
	for v in w.design.voxels:
		ys.append(v[1])
	# A war bow is hard work: a long pull (longer the longer the limbs, slower tired), a pause to
	# nock the next arrow after each shot, and a full draw held costs breath fast.
	var draw_time := (0.9 + (int(ys.max()) - int(ys.min())) * 0.035) * (1.0 + 0.6 * (1.0 - minf(1.0, c.stamina / 100.0)))
	var nock: float = maxf(0.0, float(w.get_meta("nock", 0.0)) - dt)
	w.set_meta("nock", nock)
	var draw: float = w.get_meta("draw", 0.0)
	var hold_t: float = w.get_meta("hold_t", 0.0)
	if held and nock > 0.0 and draw <= 0.0:
		return
	if held:
		if draw <= 0.0:
			m.sfx("draw", w.global_position, 0.6)
		draw = minf(1.0, draw + dt / draw_time)
		hold_t += dt
		if draw >= 1.0:
			c.stamina = maxf(0.0, c.stamina - 12.0 * dt)
		w.set_meta("draw", draw)
		w.set_meta("hold_t", hold_t)
		_show_draw(w, c, draw)
		return
	_show_draw(w, c, 0.0)
	w.set_meta("draw", 0.0)
	w.set_meta("hold_t", 0.0)
	if draw <= 0.2:
		return
	w.set_meta("nock", 0.8)
	var from: Vector3 = w.global_transform * w.center_of_mass + Vector3(0, 0.15, 0)
	var vel: Vector3
	var look = inp.get("look")
	var player: bool = e.kind == "local" or e.kind == "remote"
	if player and inp.get("aimAt") is Vector3:
		# Where the crosshair sits, allowing for the drop over the distance (weaponFx.js): a
		# short draw, a long hold or a tired arm scatters it a little.
		var speed := ARROW_SPEED.x + ARROW_SPEED.y * draw
		from = _on_sight(from, inp)
		var dd: Vector3 = (inp.aimAt as Vector3) - from
		var dist := dd.length()
		var wobble := _bow_wobble(c, draw, hold_t)
		var a1 := randf() * TAU
		var r1 := sqrt(randf()) * wobble
		var sd := Vector3(dd.z, 0, -dd.x).normalized()
		var upv := sd.cross(dd).normalized()
		dd += sd * cos(a1) * r1 * dist + upv * sin(a1) * r1 * dist
		# The flat shot that lands on the mark at this speed, solved exactly (the old guess of
		# the flight time from the straight distance fell short of a far mark).
		vel = Items.flat_shot(dd, speed, 9.81)
		from += dd.normalized() * 0.5
	elif player and look != null:
		var speed := ARROW_SPEED.x + ARROW_SPEED.y * draw
		var wobble := _bow_wobble(c, draw, hold_t)
		var dir := Vector3(sin(look.yaw) * cos(look.pitch), sin(look.pitch) + 0.06, cos(look.yaw) * cos(look.pitch)).normalized()
		dir = dir.rotated(Vector3.UP, randf_range(-wobble, wobble)).normalized()
		dir.y += randf_range(-wobble, wobble)
		vel = dir.normalized() * speed
		from += dir * 0.5
	else:
		var tgt = m.nearest_enemy(e)
		var aim: Vector3 = tgt.f.torso.global_position + Vector3(0, 0.2, 0) if tgt else from + Vector3(sin(c.yaw) * 8.0, 0.5, cos(c.yaw) * 8.0)
		var dd := aim - from
		var t := maxf(0.15, dd.length() / (ARROW_SPEED.x + ARROW_SPEED.y * draw))
		vel = Vector3(dd.x / t, (dd.y + 0.5 * 9.81 * t * t) / t, dd.z / t)
		from += dd.normalized() * 0.5
	var gem = w.design.get("gem")
	var type: String = ("pot_arrow_" + str(gem)) if gem != null and Items.TYPES.has("pot_arrow_" + str(gem)) else "pot_arrow"
	var it: Dictionary = m.items.spawn(type, from, vel, c)
	it.power = draw
	m.sfx("twang", from)
	m.sfx("whoosh", from, 0.6)
	c.stamina = maxf(0.0, c.stamina - 9.0)

## Where a shot leaves from: on the crosshair's own line of sight, beside the bow (the nearest
## point of it), not at the bow out on the right shoulder. From there it flies under the
## crosshair the whole way: from the bow it crossed the line of sight only at the mark, and at
## anything nearer or farther (a ray that ran past the man to the far wall) it went to the
## right of where the crosshair sat.
func _on_sight(from: Vector3, inp: Dictionary) -> Vector3:
	var af = inp.get("aimFrom")
	if not (af is Vector3) or not (inp.get("aimAt") is Vector3):
		return from
	var line: Vector3 = (inp.aimAt as Vector3) - (af as Vector3)
	if line.length_squared() < 0.01:
		return from
	var n := line.normalized()
	var t := clampf((from - (af as Vector3)).dot(n), 0.0, line.length() - 0.2)
	var on: Vector3 = (af as Vector3) + n * t
	# Only from beside the archer: a camera thrown far off (a free look) keeps the bow's own.
	return on if on.distance_to(from) < 1.2 else from

## Arrows fly fast and near straight (a dropping lob was the old slow arrow): speed at no draw
## plus what a full draw adds, m/s.
const ARROW_SPEED := Vector2(20.0, 38.0)
const BOLT_SPEED := 58.0

## How far off the mark the arrow may go: a short draw, a full draw held too long (the arm
## shakes from about a second), a tired archer, one on the move or on the ground.
func _bow_wobble(c, draw: float, hold_t: float) -> float:
	var tired: float = 1.0 - minf(1.0, c.stamina / 100.0)
	var lv: Vector3 = c.torso.linear_velocity
	var moving := minf(1.0, Vector2(lv.x, lv.z).length() / 3.0)
	return (0.008 + 0.045 * (1.0 - draw) + 0.03 * minf(1.0, maxf(0.0, hold_t - 1.0) / 2.0) + 0.03 * tired + 0.03 * moving) * (1.0 if c.state == "stand" else 2.0)

## The crossbow's string and bolt: `k` 0 just shot (the string slack at the prod, no bolt) to
## 1 cocked and loaded. In between the free off hand works the string back to the latch.
func _show_cock(w: Weapon, c, k: float) -> void:
	var vs: float = w.vs
	var latch_y := 15.0 * vs
	var prod_y := 18.0 * vs
	# Hand to the string at the prod (first fifth), haul it to the latch, lay the bolt (last fifth).
	var pull := clampf((k - 0.2) / 0.6, 0.0, 1.0)
	var sy := lerpf(prod_y, latch_y, pull * pull * (3.0 - 2.0 * pull))
	if k < 1.0 and c.weapons.L == null and c.arm.L.fore.function() > 0.2:
		c.off_goal = w.global_transform * Vector3(0, sy if k > 0.2 else prod_y, 0.0)
	if Fx.current == null or Fx.current.headless:
		return
	var vis: Node3D = w.get_node_or_null("CockVis")
	if vis == null:
		var bolt := Items.visual("pot_bolt")
		vis = _cords_node(w, bolt)
		vis.name = "CockVis"
		bolt.basis = Basis(Vector3(1, 0, 0), -PI / 2.0)   # its nose (+z) up the stock (+y)
	# The voxel string is the cocked one; while cocking it is drawn by the cords instead.
	_set_cords(vis, Vector3(-7.0 * vs, latch_y, 0), Vector3(7.0 * vs, latch_y, 0), Vector3(0, sy, 0))
	(vis.get_child(0) as Node3D).visible = k < 1.0
	(vis.get_child(1) as Node3D).visible = k < 1.0
	var bolt_n: Node3D = vis.get_child(2)
	bolt_n.visible = k >= 0.85
	bolt_n.position = Vector3(0, latch_y + 0.17, 0.04)
	w.set_string_hidden(k < 1.0)

func _tip(w: Weapon) -> Array:
	var top := -999
	for v in w.design.voxels:
		top = maxi(top, int(v[1]))
	var q := w.global_transform.basis.get_rotation_quaternion()
	return [w.global_transform * Vector3(0, (top + 1) * w.vs, 0), q * Vector3.UP]

## The drawn bow (weaponFx.js showDraw): the string pulled back to the nock with an arrow laid
## on it, and the off hand there pulling. The stave runs up the bow's y, the string on its -x
## side, the arrow flies out along +x.
func _show_draw(w: Weapon, c, d: float) -> void:
	var vs: float = w.vs
	var ys := []
	var sx := 0.0
	for v in w.design.voxels:
		if v[3] == "leather" and v[0] < 0:
			ys.append(v[1])
			sx = minf(sx, v[0])
	var y0: float = (ys.min() if not ys.is_empty() else 2) * vs
	var y1: float = (ys.max() if not ys.is_empty() else 18) * vs
	sx *= vs
	var pull := sx - d * 7.0 * vs
	var ym := (y0 + y1) * 0.5
	var nock := Vector3(pull, ym, 0)
	c.off_goal = w.global_transform * nock
	if Fx.current == null or Fx.current.headless:
		return
	var vis: Node3D = w.get_node_or_null("DrawVis")
	if vis == null:
		vis = _cords_node(w, Items.visual(("pot_arrow_" + str(w.design.gem)) if w.design.get("gem") != null else "pot_arrow"))
		vis.name = "DrawVis"
		var ar: Node3D = vis.get_child(2)
		ar.basis = Basis(Vector3.UP, PI / 2.0)   # its nose (+z) along the shot (+x)
	vis.visible = d > 0.0
	if d <= 0.0:
		return
	_set_cords(vis, Vector3(sx, y0, 0), Vector3(sx, y1, 0), nock)
	(vis.get_child(2) as Node3D).position = Vector3(pull + 0.3, ym, 0)

## Two cords from the string's ends to the nock, and (third child) what lies on the string.
func _cords_node(w: Weapon, load_vis: Node3D) -> Node3D:
	var vis := Node3D.new()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.94, 0.91, 0.82)
	mat.roughness = 0.9
	for i in 2:
		var cm := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.014, 0.014, 1.0)
		bm.material = mat
		cm.mesh = bm
		cm.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		vis.add_child(cm)
	load_vis.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	vis.add_child(load_vis)
	vis.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	w.add_child(vis)
	return vis

func _set_cords(vis: Node3D, a: Vector3, b: Vector3, nock: Vector3) -> void:
	for i in 2:
		var end: Vector3 = a if i == 0 else b
		var seg := nock - end
		var cord: MeshInstance3D = vis.get_child(i)
		var l := maxf(0.01, seg.length())
		var z := seg / l
		var x := z.cross(Vector3.UP if absf(z.y) < 0.95 else Vector3.RIGHT).normalized()
		cord.transform = Transform3D(Basis(x, z.cross(x), z * l), end + seg * 0.5)

## A crossbow (weaponFx.js shoot, extended): after each bolt the string is cocked again, the
## off hand hauling it back from the prod to the latch while the bolt is laid in, and only then
## can it shoot. A player shoots where the crosshair is, allowing for the drop; a bot at its man.
const CROSSBOW_RELOAD := 2.2
func _crossbow(e: Dictionary, w: Weapon, thrust: float, dt: float, inp := {}) -> void:
	var c = e.f
	var reload: float = maxf(0.0, w.get_meta("reload", 0.0) - dt)
	w.set_meta("reload", reload)
	_show_cock(w, c, 1.0 - reload / CROSSBOW_RELOAD if reload > 0.0 else 1.0)
	if thrust < 0.6 or reload > 0.0:
		return
	var td := _tip(w)
	w.set_meta("reload", CROSSBOW_RELOAD)
	var tgt = m.nearest_enemy(e)
	var aim: Vector3 = tgt.f.torso.global_position if tgt else td[0] + td[1] * 8.0
	var start: Vector3 = td[0]
	if (e.kind == "local" or e.kind == "remote") and inp.get("aimAt") is Vector3:
		aim = inp.aimAt
		start = _on_sight(start, inp)
	var bolt: Dictionary = m.items.throw_flat("pot_bolt", start, aim, c, BOLT_SPEED)
	bolt.power = 1.0
	m.sfx("clang", td[0], 0.4)
	c.stamina = maxf(0.0, c.stamina - 8.0)

func _flame(e: Dictionary, w: Weapon, thrust: float, dt: float) -> void:
	var c = e.f
	var reload: float = maxf(0.0, w.get_meta("reload", 0.0) - dt)
	w.set_meta("reload", reload)
	if thrust < 0.6 or reload > 0.0:
		return
	w.set_meta("reload", 0.35)
	var fuel: int = int(w.get_meta("fuel", 12)) - 1
	w.set_meta("fuel", fuel)
	if fuel < 0:
		w.set_meta("reload", 2.0)
		return
	var td := _tip(w)
	var tip: Vector3 = td[0]
	var dir: Vector3 = td[1]
	var zp := tip + dir * 0.9
	add_zone("fire", Vector3(zp.x, 0.05, zp.z), 0.9, 1.6, c)
	for o in m.entities:
		var oc = o.f
		if oc == c or not oc.alive:
			continue
		for part in oc.parts:
			if part.severed:
				continue
			var along := clampf((part.global_position - tip).dot(dir), 0.0, 1.8)
			var at := tip + dir * along
			if at.distance_to(part.global_position) < 0.22 * oc.S:
				m.add_spot(oc, part, "fire", 3.0, c, at)
	burst(tip + dir * 0.4, Color(1.0, 0.6, 0.15), 10, 2.0, 0.4, 0.04, -0.2)
