class_name Fire
extends RefCounted
## Fire and acid where they struck (character.js burnTick): a spot on a body part grows from
## that point. Fire chars a patch black and burns the flesh away layer by layer down to the
## bone (which stays, scorched); acid turns it green and dissolves a pit, even into the bone. A
## burning part hurts as it goes (a giant less than a man), the oil creeps along the part and
## drips onto the one below; going down to roll on the sand puts it out sooner.

const CHAR := Color(0.082, 0.063, 0.047)
const EMBER := Color(1.0, 0.416, 0.102)
const SCORCH := Color(0.604, 0.541, 0.416)
const ACID := Color(0.561, 0.831, 0.227)
const ACID_DARK := Color(0.227, 0.353, 0.071)
const FROST := Color(0.78, 0.9, 1.0)
const NECROSIS := Color(0.12, 0.08, 0.14)

## A world point on (or near) a part, in its own frame, snapped onto its nearest live voxel.
static func _spot_on(part: VoxelPart, point) -> Variant:
	var best := -1
	var bd := INF
	if point == null:
		var live := []
		for i in part.fx.size():
			if part.alive[i] and not part.bone[i]:
				live.append(i)
		if live.is_empty():
			return null
		return part.local_of(live[randi() % live.size()])
	var lp: Vector3 = part.global_transform.affine_inverse() * (point as Vector3)
	for i in part.fx.size():
		if not part.alive[i]:
			continue
		var d := part.local_of(i).distance_squared_to(lp)
		if d < bd:
			bd = d
			best = i
	return part.local_of(best) if best >= 0 else null

## Sets `part` alight ("fire") or lets acid eat into it ("acid") at `point` for `seconds`.
static func add_spot(part: VoxelPart, kind: String, seconds: float, point = null) -> Dictionary:
	if part == null or part.missing or part.alive_count == 0:
		return {}
	var lp = _spot_on(part, point)
	if lp == null:
		return {}
	var vfs := part.vf * part.part_scale
	for s in part.spots:
		if s.kind == kind and (s.lp as Vector3).distance_to(lp) < vfs * 3.0:
			s.t = maxf(s.t, seconds)
			return s
	var n := 0
	for s in part.spots:
		if s.kind == kind:
			n += 1
	if n >= (5 if kind == "fire" else 3):
		return {}
	var s := {"kind": kind, "lp": lp, "t": seconds, "age": 0.0, "removed": 0, "clock": 0.0, "crawl": 0.0}
	part.spots.append(s)
	return s

static func is_burning(c) -> bool:
	for p in c.parts:
		for s in p.spots:
			if s.kind == "fire" and s.t > 0.0:
				return true
	return false

static func spot_world(part: VoxelPart, s: Dictionary) -> Vector3:
	return part.global_transform * (s.lp as Vector3)

## One step of fire and acid on every part of `c`. The host does the damage and the eating
## away. Returns {"removed": [{part, indices, voxels}], "caught": [{part, spot}]}.
## Frostbite at a spot: the flesh round it freezes white, then over the seconds darkens to
## the black of dead flesh (necrosis); the dead voxels fall away a few at a time, the bone is
## left. A small patch, slow, bloodless.
static func _frostbite(p: VoxelPart, s: Dictionary, vfs: float, host: bool, crumble: Array, touched: Array) -> void:
	var r: float = vfs * minf(3.0, 1.0 + s.age * 0.35)
	var cap: float = p.fx.size() * 0.12
	var near := []
	for i in p.fx.size():
		if p.alive[i]:
			var d: float = p.local_of(i).distance_to(s.lp)
			if d < r:
				near.append([i, d])
	near.sort_custom(func(a, b): return a[1] < b[1])
	for pair in near.slice(0, 24):
		var i: int = pair[0]
		var h: float = p.heat.get(i, 0.0)
		touched.append(i)
		if p.bone[i]:
			p.colors[i] = p.colors[i].lerp(FROST, 0.2)
			continue
		p.heat[i] = h + 0.12
		p.colors[i] = p.colors[i].lerp(FROST if p.heat[i] < 0.5 else NECROSIS, 0.35)
		if host and p.heat[i] >= 1.4 and s.removed < cap and crumble.size() < 2:
			crumble.append(i)
			s.removed += 1

static func tick(c, dt: float, host := true) -> Dictionary:
	var out := {"removed": [], "caught": []}
	var rolling: bool = c.state == "down" or c.state == "rising"
	var soak: float = sqrt(c.S) * sqrt(float(c.mods.get("toughness", 1.0)))
	for p in c.parts:
		if p.spots.is_empty():
			continue
		var active: Array = p.spots.filter(func(s): return s.t > 0.0)
		if active.is_empty():
			p.spots = []
			p.set_flames(false)
			p.set_poison(false)
			continue
		var fire := active.any(func(s): return s.kind == "fire")
		var acid_on := active.any(func(s): return s.kind == "acid")
		var frost_on := active.any(func(s): return s.kind == "frost")
		if frost_on and not p.severed:
			# Frostbite: the limb all but useless while the cold is in it, and frozen flesh
			# does not bleed.
			p.frozen_until = maxf(p.frozen_until, VoxelPart.clock() + 0.4)
			p.bleed *= maxf(0.0, 1.0 - dt * 0.8)
			if host:
				p.hp = maxf(0.0, p.hp - dt * 3.0 / soak)
		p.set_flames(fire)
		p.set_poison(acid_on)
		if host and not p.severed:
			p.hp = maxf(0.0, p.hp - dt * ((8.0 if fire else 0.0) + (6.0 if acid_on else 0.0)) / soak)
			if fire or acid_on:   # (frostbite does not bleed)
				c.blood = maxf(0.0, c.blood - dt * (0.9 if acid_on else 0.6))
		var limb: bool = p != c.torso and p != c.head and p.bone.has(1)
		var vfs: float = p.vf * p.part_scale
		var crumble := []
		var touched := []
		for s in active:
			s.t -= dt * (2.6 if s.kind == "fire" and rolling else 1.0)
			s.age += dt
			s.clock += dt
			if s.clock < 0.2:
				continue
			s.clock = 0.0
			if s.kind == "frost":
				_frostbite(p, s, vfs, host, crumble, touched)
				continue
			var acid: bool = s.kind == "acid"
			var r: float = vfs * minf(4.5 if acid else 6.0, 1.2 + s.age * (0.75 if acid else 0.7))
			var cap: float = p.fx.size() * (0.4 if limb else 0.25)
			var ring: float = r + vfs * (1.5 if acid else 3.0)
			var near := []
			for i in p.fx.size():
				if not p.alive[i]:
					continue
				var d: float = p.local_of(i).distance_to(s.lp)
				if d < ring:
					near.append([i, d])
			near.sort_custom(func(a, b): return a[1] < b[1])
			for pair in near.slice(0, 18 if acid else 34):
				var i: int = pair[0]
				var d: float = pair[1]
				var h: float = p.heat.get(i, 0.0)
				touched.append(i)
				if d > r:
					if acid:
						p.heat[i] = minf(0.5, h + 0.2)
						p.colors[i] = p.colors[i].lerp(ACID, 0.3)
					elif not p.bone[i]:
						p.heat[i] = minf(0.9, h + 0.3)
						p.colors[i] = p.colors[i].lerp(EMBER if p.heat[i] < 0.4 else CHAR, 0.4)
					continue
				if acid:
					p.heat[i] = h + (0.12 if p.bone[i] else 0.45)
					p.colors[i] = p.colors[i].lerp(ACID if p.heat[i] < 0.6 else ACID_DARK, 0.4)
					if host and p.heat[i] >= 1.0 and s.removed < cap and crumble.size() < 4 and (not p.bone[i] or randf() < 0.3):
						crumble.append(i)
						s.removed += 1
				elif p.bone[i]:
					p.heat[i] = minf(1.0, h + 0.15)
					p.colors[i] = p.colors[i].lerp(SCORCH, 0.15)
				else:
					p.heat[i] = minf(1.4, h + 0.4)
					p.colors[i] = p.colors[i].lerp(EMBER if p.heat[i] < 0.5 else CHAR, 0.5)
					if host and p.heat[i] >= 1.2 and s.removed < cap and crumble.size() < 3:
						crumble.append(i)
						s.removed += 1
			# Burning oil creeps along the part, and drips onto the one below it.
			if host and not acid and s.t > 1.0:
				s.crawl += 0.2
				if s.crawl >= 0.6:
					s.crawl = 0.0
					var edge := near.filter(func(x): return x[1] > r * 0.85 and not p.bone[x[0]])
					if not edge.is_empty() and randf() < 0.45:
						var v: int = edge[randi() % edge.size()][0]
						var ns := add_spot(p, "fire", maxf(1.2, s.t * 0.7), p.world_of(v))
						if not ns.is_empty() and ns.age == 0.0:
							s.t -= 0.3
							out.caught.append({"part": p, "spot": ns})
			if host and not acid and s.t > 1.4 and randf() < 0.035:
				var sy := spot_world(p, s).y
				var nbs: Array = ([p.parent_part] if p.parent_part else []) + p.child_parts
				nbs = nbs.filter(func(q): return q and not q.severed and q.global_position.y < sy - 0.05 and not q.spots.any(func(x): return x.kind == "fire" and x.t > 0.0))
				if not nbs.is_empty():
					var q: VoxelPart = nbs[randi() % nbs.size()]
					var at := spot_world(p, s)
					at.y = q.global_position.y + 0.05
					var ns := add_spot(q, "fire", 1.2 + randf() * 0.8, at)
					if not ns.is_empty():
						s.t -= 0.4
						out.caught.append({"part": q, "spot": ns})
		if not crumble.is_empty():
			var idx: Array = []
			for i in crumble:
				if not idx.has(i):
					idx.append(i)
			out.removed.append({"part": p, "indices": idx, "voxels": p.remove_voxels(idx, false)})
		if not touched.is_empty():
			p.refresh_colors(touched)
	return out
