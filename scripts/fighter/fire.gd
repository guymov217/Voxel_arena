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
## What the acid leaves once it is spent: the flesh it ate, a dull dark green-brown.
const ACID_SPENT := Color(0.16, 0.19, 0.07)

## The fire and the acid gone out on a part: what they marked cools to the mark they leave, the
## embers' orange to char, the acid's bright green to the dull dark of what it ate. (Left as they
## burned, the orange and the green read as fire and poison still on the body, long after they had
## gone out: user, the fire and the poison never go out on the enemy, and the glowing green stays
## on a man for good.)
static func cool(p: VoxelPart) -> void:
	if p.heat.is_empty():
		return
	var touched := []
	for i in p.heat.keys():
		var c: Color = p.colors[i]
		if _near(c, ACID, 0.42) or (c.g > c.r * 1.12 and c.g > c.b * 1.6):
			p.colors[i] = c.lerp(ACID_SPENT, 0.8)
		elif _near(c, EMBER, 0.42):
			p.colors[i] = c.lerp(CHAR, 0.85)
		else:
			continue
		touched.append(i)
	p.heat.clear()
	if not touched.is_empty():
		p.refresh_colors(touched)

static func _near(a: Color, b: Color, d: float) -> bool:
	return Vector3(a.r - b.r, a.g - b.g, a.b - b.b).length() < d

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
	# (The nearest found among those round the point, the reach widened until there are some: not
	# every voxel of a big part gone over for each drop of fire that lands.)
	var r := part.vf * part.part_scale * 2.0
	var far := part.half_ext.length() * 2.0 + r
	var found := PackedInt32Array()
	while r < far:
		found = part.voxels_within(lp, r)
		if not found.is_empty():
			break
		r *= 2.0
	if found.is_empty():
		found = part.voxels_within(lp, far)
	for i in found:
		var d := part.local_of(i).distance_squared_to(lp)
		if d < bd:
			bd = d
			best = i
	return part.local_of(best) if best >= 0 else null

## The `n` live voxels of `p` nearest `lp` (no further than `ring`), nearest first, as [index,
## distance]: looked for within a few voxels first, and only if too few are there in all of
## `ring` (whichever way, the same nearest `n`).
static func _nearest(p: VoxelPart, lp: Vector3, ring: float, n: int, vfs: float) -> Array:
	var q := minf(ring, vfs * 3.5)
	var found := p.voxels_within(lp, q)
	if found.size() < n and q < ring:
		found = p.voxels_within(lp, ring)
	var lps := p.local_positions()
	var near := []
	for i in found:
		near.append([i, lps[i].distance_to(lp)])
	near.sort_custom(func(a, b): return a[1] < b[1])
	return near.slice(0, n)

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
	var s := {"kind": kind, "lp": lp, "t": seconds, "age": 0.0, "removed": 0, "crawl": 0.0}
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
	for i in p.voxels_within(s.lp, r):
		near.append([i, p.local_of(i).distance_to(s.lp)])
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

## The work at the spots (the flesh burned and eaten away, the colours, the oil creeping on) is
## done SPOT_EVERY seconds apart, each part at its own time within that, and no more than
## DUE_PER_STEP parts of everyone's in one step (a part whose turn it is when the step has had
## its share waits for the next, and never through a second turn). On one clock for every spot, all the parts a pot or a breath
## set alight together did all of it in the same step: 30 to 40 ms five times a second with four
## men alight, and nothing between (user: the frames drop when an enemy starts to burn or is
## poisoned). Only that work waits; the burn's harm goes on every step.
const SPOT_EVERY := 0.2
const DUE_PER_STEP := 1
static var _due_frame := -1
static var _due_left := 0
## A part's place in the fifth of a second: by its place in the body and its man's slot.
static func _phase(c, p: VoxelPart) -> float:
	var i: int = c.parts.find(p)
	var slot = c.get("slot")
	return fposmod(float(maxi(0, i)) * 0.0731 + float(slot if slot is int else 0) * 0.0419, SPOT_EVERY)

static func tick(c, dt: float, host := true) -> Dictionary:
	var out := {"removed": [], "caught": []}
	var rolling: bool = c.state == "down" or c.state == "rising"
	var soak: float = sqrt(c.S) * sqrt(float(c.mods.get("toughness", 1.0)))
	for p in c.parts:
		if p.spots.is_empty():
			continue
		# (Every frame for every part that burns: a plain pass over its few spots.)
		var active: Array = []
		var fire := false
		var acid_on := false
		var frost_on := false
		for s in p.spots:
			if s.t > 0.0:
				active.append(s)
				fire = fire or s.kind == "fire"
				acid_on = acid_on or s.kind == "acid"
				frost_on = frost_on or s.kind == "frost"
		if active.is_empty():
			p.spots = []
			p.set_flames(false)
			p.set_poison(false)
			cool(p)
			continue
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
		var limb = null   # (whether it has bone in it: looked up only when a spot works on it)
		var vfs: float = p.vf * p.part_scale
		var crumble := []
		var touched := []
		if p.spot_clock < 0.0:
			p.spot_clock = _phase(c, p)
		p.spot_clock += dt
		var frame := Engine.get_physics_frames()
		if frame != _due_frame:
			_due_frame = frame
			_due_left = DUE_PER_STEP
		var due: bool = p.spot_clock >= SPOT_EVERY and (_due_left > 0 or p.spot_clock >= 2.0 * SPOT_EVERY)
		if due:
			_due_left -= 1
			p.spot_clock = fposmod(p.spot_clock, SPOT_EVERY)
		for s in active:
			s.t -= dt * (2.6 if s.kind == "fire" and rolling else 1.0)
			s.age += dt
			if not due:
				continue
			if s.kind == "frost":
				_frostbite(p, s, vfs, host, crumble, touched)
				continue
			var acid: bool = s.kind == "acid"
			var r: float = vfs * minf(4.5 if acid else 6.0, 1.2 + s.age * (0.75 if acid else 0.7))
			if limb == null:
				limb = p != c.torso and p != c.head and p.bone.has(1)
			var cap: float = p.fx.size() * (0.4 if limb else 0.25)
			var ring: float = r + vfs * (1.5 if acid else 3.0)
			# (Only the voxels round the spot, found by the part's own lookup, and only the nearest
			# that are worked on: every voxel of the part gone over for every spot, five times a
			# second, then every one in reach put in order, on a beast's or a giant's parts of
			# thousands, was a hitch whenever a dragon's breath set a creature alight, user.)
			for pair in _nearest(p, s.lp, ring, 18 if acid else 34, vfs):
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
					# Onto the flesh at the rim of what burns.
					var edge := []
					var lps: PackedVector3Array = p.local_positions()
					for i in p.voxels_within(s.lp, ring):
						if not p.bone[i] and lps[i].distance_to(s.lp) > r * 0.85:
							edge.append(i)
					if not edge.is_empty() and randf() < 0.45:
						var v: int = edge[randi() % edge.size()]
						# (Each spot it spreads to burns shorter than what is left of this one: given
						# at least 1.2 s, a beast's broad body kept passing the fire round itself
						# and it never went out, user.)
						var ns := add_spot(p, "fire", s.t * 0.6, p.world_of(v))
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
					var ns := add_spot(q, "fire", minf(1.2 + randf() * 0.8, s.t * 0.6), at)
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
