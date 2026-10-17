class_name ForgeLib
extends RefCounted
## The workshop's logic (forge.js and weaponDesign.js computeStats): weapon stats from the
## voxels, drawing helpers (lines, boxes), auto-sharpen and auto-grip, the guided forge (a base
## card and up to two modifier cards built into voxels by simple_weapon), "surprise me", the
## blacksmith's opinion and the dummy's verdict. No UI: tests use it directly.

## Room to try things: a weapon up to about 3.5 m long, 1.3 m wide and half a metre thick.
const GRID := {"minX": -16, "maxX": 16, "minY": -16, "maxY": 90, "minZ": -6, "maxZ": 6}
const MAX_VOXELS := 1600
const CHAIN_LINK := 0.07
const METALS := ["steel", "iron", "bronze", "gold", "stone", "bone"]

static func in_grid(x: int, y: int, z: int) -> bool:
	return x >= GRID.minX and x <= GRID.maxX and y >= GRID.minY and y <= GRID.maxY and z >= GRID.minZ and z <= GRID.maxZ

static func empty_design(name := "New weapon") -> Dictionary:
	return {"name": name, "kind": "weapon", "twoHanded": false, "sharpness": 0.8, "voxels": []}

static func set_voxel(d: Dictionary, x: int, y: int, z: int, mat: String, type: String) -> bool:
	if not in_grid(x, y, z):
		return false
	for i in d.voxels.size():
		var v: Array = d.voxels[i]
		if int(v[0]) == x and int(v[1]) == y and int(v[2]) == z:
			d.voxels[i] = [x, y, z, mat, type]
			return true
	if d.voxels.size() >= MAX_VOXELS:
		return false
	d.voxels.append([x, y, z, mat, type])
	return true

static func remove_voxel(d: Dictionary, x: int, y: int, z: int) -> bool:
	for i in d.voxels.size():
		var v: Array = d.voxels[i]
		if int(v[0]) == x and int(v[1]) == y and int(v[2]) == z:
			d.voxels.remove_at(i)
			return true
	return false

static func box(d: Dictionary, x0: int, x1: int, y0: int, y1: int, z0: int, z1: int, mat: String, type: String) -> void:
	for x in range(x0, x1 + 1):
		for y in range(y0, y1 + 1):
			for z in range(z0, z1 + 1):
				set_voxel(d, x, y, z, mat, type)

static func _mass(mat: String) -> float:
	return float(Data.material(mat).get("mass", 0.02))

## The most a gladiator can lift and swing (kg): heavier, it lies on the sand with the hand
## dragged down after it.
const MAX_KG_ONE := 14.0
const MAX_KG_TWO := 26.0
## And the most weight out at a distance from the hand (kg·m): a heavy head on a long haft
## drags the arm down though the whole weighs little (a warhammer is 6.4 two-handed, a mace 1.8).
const MAX_LEVER_ONE := 3.5
const MAX_LEVER_TWO := 10.0

## Why this design cannot be carried into a fight, or "" if it can.
static func too_heavy(d: Dictionary, st := {}) -> String:
	if st.is_empty():
		st = compute_stats(d)
	var two: bool = d.get("twoHanded", false)
	var cap := MAX_KG_TWO if two else MAX_KG_ONE
	if float(st.mass) > cap:
		return "Too heavy to lift: %.1f kg, the most is %d kg%s" % [st.mass, int(cap), "" if two else " (%d two-handed)" % int(MAX_KG_TWO)]
	var g = grip_points(d)
	if g != null and st.get("com") is Array:
		var gm: Vector3 = g.main
		var lever: float = float(st.mass) * (Vector3(st.com[0], st.com[1], st.com[2]) - gm).length() * Data.weapon_voxel
		var lcap := MAX_LEVER_TWO if two else MAX_LEVER_ONE
		if lever > lcap:
			return "Too much weight too far from the hand: the arm cannot hold it up (%.1f of %.1f%s). Lighter at the end, or nearer the hand" % [lever, lcap, "" if two else "; more two-handed"]
	return ""

## The hand points (voxel units) for the main and the off hand, or null with no grip.
static func grip_points(d: Dictionary) -> Variant:
	# Where the builder put the hands (the forge's Move hand: on any block of it), while there
	# is still a block there; one-handed, only the main hand's place counts.
	var gs = d.get("grips")
	if gs is Dictionary and gs.has("main") and gs.has("off"):
		var two: bool = d.get("twoHanded", false)
		var both := true
		for k in (["main", "off"] if two else ["main"]):
			var q := Vector3(gs[k][0], gs[k][1], gs[k][2])
			if not d.voxels.any(func(g): return Vector3(g[0], g[1], g[2]).distance_to(q) < 1.5):
				both = false
		if both:
			var m := Vector3(gs.main[0], gs.main[1], gs.main[2])
			return {"main": m, "off": Vector3(gs.off[0], gs.off[1], gs.off[2]) if two else m + Vector3(0, -2, 0)}
	var grips: Array = d.voxels.filter(func(v): return v[4] == "grip")
	if grips.is_empty():
		return null
	grips.sort_custom(func(a, b): return a[1] < b[1])
	var avg := func(list: Array) -> Vector3:
		var p := Vector3.ZERO
		for g in list:
			p += Vector3(g[0], g[1], g[2])
		return p / list.size()
	if not d.get("twoHanded", false) or grips.size() < 2:
		var m: Vector3 = avg.call(grips)
		return {"main": m, "off": m + Vector3(0, -2, 0)}
	var top: Array = grips.slice(int(grips.size() / 2))
	var bottom: Array = grips.slice(0, maxi(1, int(grips.size() / 3)))
	return {"main": avg.call(top), "off": avg.call(bottom)}

## The counterweight the builder set with the balance tool (weaponDesign.js ballast).
static func ballast(d: Dictionary) -> Variant:
	var want = d.get("balance")
	if not (want is Array) or want.size() < 3 or d.voxels.is_empty():
		return null
	var mass := 0.0
	var c0 := Vector3.ZERO
	for v in d.voxels:
		var m := _mass(v[3])
		mass += m
		c0 += Vector3(v[0], v[1], v[2]) * m
	if mass <= 0.0:
		return null
	c0 /= mass
	var dv := Vector3(want[0], want[1], want[2]) - c0
	var l := dv.length()
	if l < 0.3:
		return null
	var u := dv / l
	var far := 0.0
	for v in d.voxels:
		far = maxf(far, (Vector3(v[0], v[1], v[2]) - c0).dot(u))
	if far < 0.5:
		return null
	var shift := minf(l, 0.6 * far)
	return {"k": shift / far, "p": c0 + u * far, "com": c0 + u * shift, "mass": mass}

## What a fighter feels in the hand (weaponDesign.js computeStats).
static func compute_stats(d: Dictionary) -> Dictionary:
	var s: float = Data.weapon_voxel
	var mass := 0.0
	var com := Vector3.ZERO
	var edge := 0
	var point := 0
	var hard := 0.0
	for v in d.voxels:
		var m := _mass(v[3])
		mass += m
		com += Vector3(v[0], v[1], v[2]) * m
		if v[4] == "edge" or v[4] == "point":
			if v[4] == "edge":
				edge += 1
			else:
				point += 1
			hard += float(Data.material(v[3]).get("hardness", 0.5))
	if mass > 0.0:
		com /= mass
	var grips = grip_points(d)
	var bl = ballast(d)
	if bl != null:
		com = bl.com
	var g: Vector3 = grips.main if grips != null else com
	var inertia := 0.0
	var reach := 0.0
	for v in d.voxels:
		var r := (Vector3(v[0], v[1], v[2]) - g) * s
		inertia += _mass(v[3]) * r.length_squared()
		reach = maxf(reach, r.length() + s * 0.5)
	if bl != null:
		var rb: Vector3 = (bl.p - g) * s
		inertia = inertia * (1.0 - bl.k) + bl.k * mass * rb.length_squared()
	if d.get("chain") is Dictionary:
		var hm := 0.0
		for v in d.chain.head.voxels:
			hm += _mass(v[3])
		mass += hm
		inertia += hm * pow(reach + int(d.chain.links) * CHAIN_LINK, 2) * 0.5
		reach += int(d.chain.links) * CHAIN_LINK * 0.6 + 0.1
	var strength := 95.0 if d.get("twoHanded", false) else 55.0
	var sharp_n := edge + point
	var avg_hard := hard / sharp_n if sharp_n > 0 else 0.0
	var sharpness := float(d.get("sharpness", 0.8))
	return {
		"mass": mass, "com": [com.x, com.y, com.z], "balance": (com.y - g.y) * s, "inertia": inertia, "reach": reach,
		"swingSpeed": minf(30.0, sqrt(strength / (inertia + 0.02))) if inertia > 0.0 else 30.0,
		"edge": edge, "point": point, "voxelCount": d.voxels.size(), "counterweight": bl.k if bl != null else 0.0,
		"cut": avg_hard * sharpness if edge > 0 else 0.0, "pierce": avg_hard * sharpness if point > 0 else 0.0,
		"crush": minf(1.0, mass / 4.0), "tooHeavy": not d.get("twoHanded", false) and inertia > 1.2, "hasGrip": grips != null,
	}

# ---------- Drawing ----------

const SIDES := [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]

## Of the cells `add`, those that hold on to the weapon (`cells`: Vector3i -> anything): face to
## face with it, or with another new one that does. Nothing is set in the air.
static func attached(cells: Dictionary, add: Array) -> Array:
	var on := {}
	var left := add.duplicate()
	var grew := true
	while grew and not left.is_empty():
		grew = false
		for c in left.duplicate():
			for d in SIDES:
				if cells.has(c + d) or on.has(c + d):
					on[c] = true
					left.erase(c)
					grew = true
					break
	return add.filter(func(c): return on.has(c))

## The weapon's pieces: sets of cells joined face to face, the largest first.
static func pieces(cells: Dictionary) -> Array:
	var seen := {}
	var out := []
	for c0 in cells:
		if seen.has(c0):
			continue
		var piece := []
		var stack := [c0]
		seen[c0] = true
		while not stack.is_empty():
			var c: Vector3i = stack.pop_back()
			piece.append(c)
			for d in SIDES:
				var n: Vector3i = c + d
				if cells.has(n) and not seen.has(n):
					seen[n] = true
					stack.append(n)
		out.append(piece)
	out.sort_custom(func(a, b): return a.size() > b.size())
	return out

## What stays on the anvil when the weapon is cut in two: the piece with the grip in it (the
## biggest such), or else the biggest. The rest falls off.
static func kept_piece(cells: Dictionary) -> Array:
	var ps := pieces(cells)
	if ps.is_empty():
		return []
	for p in ps:
		if p.any(func(c): return cells[c] is Array and cells[c].size() > 1 and cells[c][1] == "grip"):
			return p
	return ps[0]

## A line from `a` to `b` in any direction, every cell joined face to face to the one before
## (a slanting line climbs as a staircase, so none of it hangs by a corner).
static func line_path(a: Vector3i, b: Vector3i) -> Array:
	var out := [a]
	var p := a
	var d := b - a
	var n := Vector3(absi(d.x), absi(d.y), absi(d.z))
	var done := Vector3.ZERO
	while p != b:
		# The axis furthest behind on its share of the way takes the next step.
		var best := -1
		var lag := INF
		for i in 3:
			if done[i] < n[i]:
				var t := (done[i] + 0.5) / n[i]
				if t < lag:
					lag = t
					best = i
		var step := Vector3i.ZERO
		step[best] = signi(d[best])
		p += step
		done[best] += 1.0
		out.append(p)
	return out

static func line_cells(a: Vector3i, b: Vector3i) -> Array:
	var n := maxi(absi(b.x - a.x), maxi(absi(b.y - a.y), absi(b.z - a.z)))
	var out := []
	var seen := {}
	for i in n + 1:
		var t := float(i) / n if n > 0 else 0.0
		var c := Vector3i(roundi(a.x + (b.x - a.x) * t), roundi(a.y + (b.y - a.y) * t), roundi(a.z + (b.z - a.z) * t))
		if not seen.has(c):
			seen[c] = true
			out.append(c)
	return out

static func box_cells(a: Vector3i, b: Vector3i) -> Array:
	var out := []
	for x in range(mini(a.x, b.x), maxi(a.x, b.x) + 1):
		for y in range(mini(a.y, b.y), maxi(a.y, b.y) + 1):
			for z in range(mini(a.z, b.z), maxi(a.z, b.z) + 1):
				out.append(Vector3i(x, y, z))
	return out

## Metal outline becomes edge, the very tip a point, the rest stays blunt; grips and non-metal
## voxels are left alone. Returns how many changed.
static func auto_sharpen(d: Dictionary) -> int:
	var at := {}
	for v in d.voxels:
		at[Vector3i(v[0], v[1], v[2])] = v
	var metal: Array = d.voxels.filter(func(v): return METALS.has(v[3]) and v[4] != "grip")
	if metal.is_empty():
		return 0
	var max_y := -999
	for v in metal:
		max_y = maxi(max_y, int(v[1]))
	var tip_row := metal.filter(func(o): return int(o[1]) == max_y).size()
	var changed := 0
	for v in metal:
		var x: int = v[0]
		var y: int = v[1]
		var z: int = v[2]
		var side_open := not at.has(Vector3i(x - 1, y, z)) or not at.has(Vector3i(x + 1, y, z))
		var flat := not at.has(Vector3i(x, y, z - 1)) and not at.has(Vector3i(x, y, z + 1))
		var type := "blunt"
		if y == max_y and not at.has(Vector3i(x, y + 1, z)) and tip_row <= 2:
			type = "point"
		elif side_open and flat:
			type = "edge"
		if v[4] != type:
			v[4] = type
			changed += 1
	return changed

## A handle where there is none: the lowest column of wood or leather (or the lowest voxels).
static func auto_grip(d: Dictionary, length := 5) -> int:
	if d.voxels.is_empty() or d.voxels.any(func(v): return v[4] == "grip"):
		return 0
	var soft: Array = d.voxels.filter(func(v): return v[3] == "wood" or v[3] == "leather")
	var pool: Array = soft if not soft.is_empty() else d.voxels
	var min_y := 999
	for v in pool:
		min_y = mini(min_y, int(v[1]))
	var low: Array = pool.filter(func(v): return int(v[1]) == min_y)
	low.sort_custom(func(a, b): return absi(a[0]) < absi(b[0]))
	var base: Array = low[0]
	var n := 0
	for y in range(int(base[1]), int(base[1]) + length):
		var found := false
		for v in d.voxels:
			if int(v[0]) == int(base[0]) and int(v[1]) == y and int(v[2]) == int(base[2]):
				v[4] = "grip"
				found = true
				n += 1
				break
		if not found:
			break
	return n

# ---------- Names and "surprise me" ----------

const ADJ := ["Squeaky", "Unholy", "Slightly Used", "Grandma's", "The Emperor's", "Soggy", "Very Sharp", "Bent", "Legendary", "Questionable", "Haunted", "Discount", "Overcompensating", "Polite", "Angry"]
const NOUN := {"blade": ["Toothpick", "Cleaver", "Letter Opener", "Butter Knife", "Widowmaker"], "axe": ["Chopper", "Divorce Papers", "Lumberjack", "Problem Solver"], "mace": ["Bonker", "Lollipop", "Meat Tenderizer", "Headache"], "polearm": ["Shish Kebab", "Back Scratcher", "Long Argument", "Pokey Stick"], "silly": ["Spork", "Fork of Destiny", "Pool Noodle", "Ladle"]}
const SUFFIX := ["", "", " of Doom", " of Mild Inconvenience", " +1", " (Do Not Touch)", " of the Drunk Senator", " II: The Return", " of Regret"]

static func _pick(a: Array, rng: RandomNumberGenerator):
	return a[rng.randi_range(0, a.size() - 1)]

static func weapon_name(kind: String, rng: RandomNumberGenerator) -> String:
	var base := "%s %s" % [_pick(ADJ, rng), _pick(NOUN[kind], rng)]
	var full: String = base + str(_pick(SUFFIX, rng))
	return full if full.length() <= 32 else base.substr(0, 32)

static func surprise_weapon(rng: RandomNumberGenerator) -> Dictionary:
	var kind: String = _pick(["blade", "blade", "axe", "mace", "polearm", "silly"], rng)
	var d := empty_design(weapon_name(kind, rng))
	var metal: String = _pick(["steel", "steel", "iron", "iron", "gold", "stone"], rng)
	var haft: String = _pick(["wood", "wood", "wood", "iron"], rng)
	var grip := rng.randi_range(3, 12 if kind == "polearm" else 6)
	for y in grip:
		set_voxel(d, 0, y, 0, haft, "grip")
	if rng.randf() < 0.6:
		var pm: String = _pick(["lead", "iron", "iron"], rng)
		set_voxel(d, 0, -1, 0, pm, "blunt")
		for o in [Vector3i(1, -1, 0), Vector3i(-1, -1, 0), Vector3i(0, -1, 1), Vector3i(0, -1, -1)]:
			set_voxel(d, o.x, o.y, o.z, pm, "blunt")
	var top := grip
	if kind == "polearm":
		var l := rng.randi_range(12, 26)
		for y in range(top, top + l):
			set_voxel(d, 0, y, 0, "wood", "blunt")
		top += l
	elif kind != "blade":
		var l2 := rng.randi_range(4, 12)
		for y in range(top, top + l2):
			set_voxel(d, 0, y, 0, "wood" if haft == "leather" else haft, "blunt")
		top += l2
	if kind == "blade" or kind == "polearm":
		if rng.randf() < 0.7:
			var guard: String = _pick(["iron", "iron", "gold"], rng)
			for x in range(-2, 3):
				set_voxel(d, x, top, 0, guard, "blunt")
			set_voxel(d, 0, top, -1, guard, "blunt")
			set_voxel(d, 0, top, 1, guard, "blunt")
		top += 1
		var bl := rng.randi_range(3, 7) if kind == "polearm" else rng.randi_range(8, 26)
		var w := rng.randi_range(0, 2)
		for y in range(top, top + bl):
			for x in range(-w, w + 1):
				set_voxel(d, x, y, 0, metal, "blunt")
			# A spine down the middle: the blade has a thickness (thin at the edges, thick at the
			# core), not a sheet of one voxel. Not near the tip, nor on a needle of a blade.
			if w >= 1 and y < top + bl - 2:
				set_voxel(d, 0, y, -1, metal, "blunt")
				set_voxel(d, 0, y, 1, metal, "blunt")
		for i in mini(2, w + 1):
			set_voxel(d, 0, top + bl + i, 0, metal, "blunt")
	elif kind == "axe":
		var h := rng.randi_range(3, 7)
		var reach := rng.randi_range(3, 6)
		var dbl := rng.randf() < 0.4
		for y in range(top - h, top):
			for x in range(1, reach + 1):
				set_voxel(d, x, y, 0, metal, "blunt")
				if dbl:
					set_voxel(d, -x, y, 0, metal, "blunt")
				# The cheeks of the head are thick where it sits on the haft, thin to the edge.
				if x <= mini(2, reach - 1):
					for z in [-1, 1]:
						set_voxel(d, x, y, z, metal, "blunt")
						if dbl:
							set_voxel(d, -x, y, z, metal, "blunt")
	elif kind == "mace":
		var r := rng.randi_range(1, 3)
		for x in range(-r, r + 1):
			for y in range(-r, r + 1):
				for z in range(-r, r + 1):
					if x * x + y * y + z * z <= r * r + 1:
						set_voxel(d, x, top + r + y, z, metal, "blunt")
		if rng.randf() < 0.6:
			for xz in [[r + 1, 0], [-r - 1, 0], [0, r + 1], [0, -r - 1]]:
				set_voxel(d, xz[0], top + r, xz[1], "steel", "point")
	else:
		for x in range(-2, 3):
			for y in 4:
				for z in [-1, 0, 1]:
					set_voxel(d, x, top + y, z, metal, "blunt")
		for x in [-2, 0, 2]:
			for y in range(4, 7):
				set_voxel(d, x, top + y, 0, metal, "point")
	auto_sharpen(d)
	one_piece(d)
	d.sharpness = roundf((0.5 + rng.randf() * 0.5) * 20.0) / 20.0
	d.twoHanded = compute_stats(d).tooHeavy or (kind == "polearm" and rng.randf() < 0.5)
	return d

## A loose piece joined on instead of thrown away (a ready-made weapon's feathers, an eye, a
## string): from its nearest cell to the nearest of the weapon's, a straight run of cells in
## the loose piece's own stuff, one axis at a time. Returns how many voxels were added.
static func bridge(d: Dictionary) -> int:
	var added := 0
	for guard in 64:
		var cells := {}
		for v in d.voxels:
			cells[Vector3i(int(v[0]), int(v[1]), int(v[2]))] = [v[3], v[4]]
		var ps := pieces(cells)
		if ps.size() <= 1:
			return added
		var main := kept_piece(cells)
		var loose: Array = ps[0] if ps[0] != main else ps[1]
		var best := INF
		var a := Vector3i.ZERO
		var b := Vector3i.ZERO
		for c in loose:
			for m in main:
				var dd: float = absi(c.x - m.x) + absi(c.y - m.y) + absi(c.z - m.z)
				if dd < best:
					best = dd
					a = c
					b = m
		var look: Array = cells[a]
		var job: String = "blunt" if look[1] == "grip" else String(look[1])
		var p := a
		for axis in 3:
			while p[axis] != b[axis]:
				p[axis] += signi(b[axis] - p[axis])
				if not cells.has(p):
					d.voxels.append([p.x, p.y, p.z, look[0], job])
					cells[p] = [look[0], job]
					added += 1
	return added

## Whatever is not joined, face to face, to the piece with the grip is taken off: nothing of a
## weapon hangs in the air. Returns how many voxels went.
static func one_piece(d: Dictionary) -> int:
	var cells := {}
	for v in d.voxels:
		cells[Vector3i(int(v[0]), int(v[1]), int(v[2]))] = [v[3], v[4]]
	var keep := {}
	for c in kept_piece(cells):
		keep[c] = true
	var before: int = d.voxels.size()
	d.voxels = d.voxels.filter(func(v): return keep.has(Vector3i(int(v[0]), int(v[1]), int(v[2]))))
	return before - d.voxels.size()

# ---------- The blacksmith and the dummy ----------

static func blacksmith_says(d: Dictionary, st := {}) -> String:
	if st.is_empty():
		st = compute_stats(d)
	var n: int = maxi(1, d.voxels.size())
	var share := func(m: String) -> float: return d.voxels.filter(func(v): return v[3] == m).size() / float(n)
	if d.voxels.is_empty():
		return "An empty anvil. Draw something. Anything. Please."
	if not st.hasGrip:
		return "Lovely. And where exactly do you plan to hold it? Mark a Grip, or press Auto-grip."
	if share.call("rubber") > 0.5:
		return "It squeaks. The crowd will love you. Your enemies will be confused."
	if share.call("fish") > 0.5:
		return "That is a fish. I am a blacksmith. Why am I holding a fish?"
	if share.call("gold") > 0.4:
		return "All gold? Shiny, heavy and soft as butter. The Emperor approves, physics does not."
	if share.call("lead") > 0.2:
		return "Is that... lead? You will need to bench press a horse to swing this."
	if d.get("kind", "weapon") == "shield":
		return "A door. You made a door. A very safe door." if st.mass > 4.0 else "A fine shield. Hide behind it and judge people."
	if st.voxelCount < 8:
		return "Is this a weapon or a toothpick? Even the rats are laughing."
	if st.reach > 1.4:
		return "You could poke someone in the next city with this."
	if st.tooHeavy:
		return "Too heavy for one hand, friend. Make it two-handed or lose the weight."
	if st.balance > 0.5:
		return "All the weight is at the far end. It will hit like a cart, and turn like one too."
	if st.edge == 0 and st.point == 0 and st.crush < 0.15:
		return "No edge, no point, no weight. You will tickle them to death."
	if st.edge == 0 and st.point == 0:
		return "A proper bonker. No cutting, but heads will ring like bells."
	if st.cut > 0.7 and st.swingSpeed > 10.0:
		return "Sharp and quick. Now that is a gladiator's weapon."
	if st.point > 0 and st.edge == 0:
		return "Pointy! Thrust with C for best results."
	if st.mass < 0.6:
		return "Light as a feather. Fast, but do not expect to cut through armour."
	return "Not bad. Not bad at all. Go hit something with it."

## The three numbers a fighter cares about, 0..1.
static func three_bars(st: Dictionary) -> Dictionary:
	return {
		"speed": clampf(float(st.swingSpeed) / 14.0, 0.0, 1.0),
		"damage": clampf(maxf(float(st.cut), maxf(float(st.pierce) * 0.9, float(st.crush) * 1.2)), 0.0, 1.0),
		"reach": clampf(float(st.reach) / 1.5, 0.0, 1.0),
	}

static func dummy_verdict(d: Dictionary, st := {}) -> String:
	if st.is_empty():
		st = compute_stats(d)
	if d.get("kind", "weapon") == "shield":
		return "Blocks anything. Also blocks you from moving fast." if st.mass > 4.0 else "Blocks a sword. Bash with it when they get close."
	if d.get("shoots", "") == "arrow":
		return "Hold the left button to draw, let go to loose. Arrows stick and bleed."
	if d.get("throwable", false):
		return "Made to fly. Press F and it goes where you aim."
	var b := three_bars(st)
	if b.damage < 0.15:
		return "Barely a scratch. The dummy is laughing."
	if st.cut > 0.75:
		return "Opens a limb to the bone, and comes back fast." if b.speed > 0.6 else "Takes an arm clean off, if you can land it."
	if st.pierce > 0.6:
		return "Goes straight through. Thrust with C."
	if st.crush > 0.5:
		return "Cracks ribs and knocks the dummy flat." if b.speed > 0.5 else "Flattens the dummy. One swing, if it connects."
	if st.cut > 0.4:
		return "Cuts deep enough to bleed them out."
	return "Hurts, bruises, nothing dramatic. Hit them twice."

static func checklist(d: Dictionary, st := {}) -> Array:
	if st.is_empty():
		st = compute_stats(d)
	return [
		{"done": st.hasGrip, "text": "Give it a handle (Grip voxels)"},
		{"done": st.edge + st.point > 0 or st.crush > 0.2, "text": "Add something that hurts (Edge, Point or a heavy head)"},
	]

# ---------- Simple weapons from a handful of numbers ----------

const SIMPLE_SHAPES := {
	"sword": {"label": "Sword", "blade": [10, 34], "width": [1, 3]},
	"axe": {"label": "Axe", "blade": [10, 30], "width": [3, 7]},
	"mace": {"label": "Mace", "blade": [8, 26], "width": [2, 5]},
	"hammer": {"label": "Warhammer", "blade": [12, 30], "width": [3, 7]},
	"spear": {"label": "Spear", "blade": [16, 36], "width": [1, 3]},
	"dagger": {"label": "Dagger", "blade": [6, 14], "width": [1, 2]},
	"club": {"label": "Club", "blade": [10, 26], "width": [1, 4]},
	"shield": {"label": "Shield", "blade": [8, 14], "width": [4, 8]},
	"bow": {"label": "Bow", "blade": [7, 14], "width": [1, 2]},
}
const SIMPLE_MATERIALS := ["steel", "iron", "wood", "stone", "lead", "gold", "explosive", "spring", "glue", "magnet"]
const DEFAULT_SIMPLE := {"shape": "sword", "blade": 20, "width": 2, "handle": 5, "mat": "steel", "handleMat": "wood", "pommel": 1, "spikes": false, "twoHanded": false, "throwable": false, "sharp": 0.8}

static func simple_weapon(o: Dictionary) -> Dictionary:
	var p := DEFAULT_SIMPLE.duplicate()
	p.merge(o, true)
	var sh: Dictionary = SIMPLE_SHAPES.get(p.shape, SIMPLE_SHAPES.sword)
	var blade := clampi(roundi(float(p.blade)), sh.blade[0], sh.blade[1])
	var width := clampi(roundi(float(p.width)), sh.width[0], sh.width[1])
	var handle := clampi(roundi(float(p.handle)), 3, 14)
	var mat: String = p.mat
	var hm: String = p.get("handleMat", "wood")
	var d := empty_design(str(p.get("name", "")) if str(p.get("name", "")) != "" else "My " + str(sh.label))
	d.sharpness = clampf(float(p.sharp), 0.0, 1.0)
	d.twoHanded = bool(p.twoHanded) and p.shape != "shield" and p.shape != "dagger"
	d.throwable = bool(p.throwable) and p.shape != "shield"
	d.spins = d.throwable and p.shape != "spear"
	var top := mini(GRID.maxY, handle + blade)
	box(d, 0, 0, 0, handle, 0, 0, "leather", "grip")
	for i in range(1, int(p.pommel) + 1):
		set_voxel(d, 0, -i, 0, "lead", "blunt")
	var half := int(width / 2)
	match String(p.shape):
		"shield":
			var w := mini(6, width + 1)
			var h := mini(18, blade + 4)
			d.kind = "shield"
			d.voxels = []
			box(d, -1, 1, int(h / 2) - 2, int(h / 2) + 2, 0, 0, "leather", "grip")
			box(d, -w, w, 0, h, 1, 1, mat, "blunt")
			for x in range(-w, w + 1):
				set_voxel(d, x, 0, 1, hm, "blunt")
				set_voxel(d, x, h, 1, hm, "blunt")
			one_piece(d)
			return d
		"bow":
			d.voxels = []
			d.twoHanded = true
			d.throwable = false
			d.shoots = "arrow"
			var l := blade
			var wood := "wood" if hm == "leather" else hm
			box(d, 0, 0, l, l + 4, 0, 0, "leather", "grip")
			box(d, 0, 0, 0, l - 1, 0, 0, wood, "blunt")
			box(d, 0, 0, l + 5, 2 * l + 4, 0, 0, wood, "blunt")
			if width > 1:
				box(d, 1, 1, 0, l - 1, 0, 0, mat, "blunt")
				box(d, 1, 1, l + 5, 2 * l + 4, 0, 0, mat, "blunt")
			# The tips curl back to the string, face to face (corner to corner it hung in the air).
			for xy in [[-1, 0], [-1, 1], [-1, 2 * l + 4], [-1, 2 * l + 3], [-2, 1], [-2, 2 * l + 3]]:
				set_voxel(d, xy[0], xy[1], 0, "wood", "blunt")
			box(d, -2, -2, 2, 2 * l + 2, 0, 0, "leather", "blunt")
			one_piece(d)
			return d
		"sword":
			box(d, -2, 2, handle + 1, handle + 1, 0, 0, "bronze", "blunt")
			box(d, 0, 0, handle + 2, top, 0, 0, mat, "blunt")
			if width > 1:
				box(d, -half, -1, handle + 2, top - 2, 0, 0, mat, "edge")
				box(d, 1, half, handle + 2, top - 2, 0, 0, mat, "edge")
			else:
				box(d, -1, -1, handle + 2, top - 2, 0, 0, mat, "edge")
				box(d, 1, 1, handle + 2, top - 2, 0, 0, mat, "edge")
			box(d, 0, 0, top - 1, top, 0, 0, mat, "point")
		"dagger":
			box(d, 0, 0, handle + 1, top, 0, 0, mat, "blunt")
			box(d, -1, -1, handle + 1, top - 2, 0, 0, mat, "edge")
			box(d, 1, 1, handle + 1, top - 2, 0, 0, mat, "edge")
			set_voxel(d, 0, top, 0, mat, "point")
		"spear":
			box(d, 0, 0, handle + 1, top - 4, 0, 0, hm, "blunt")
			box(d, -half, half, top - 5, top - 2, 0, 0, mat, "edge")
			box(d, 0, 0, top - 3, top, 0, 0, mat, "point")
		"axe":
			box(d, 0, 0, handle + 1, top, 0, 0, hm, "blunt")
			var ah := maxi(4, int(blade * 0.35))
			box(d, 1, width, top - ah, top - 1, 0, 0, mat, "blunt")
			box(d, width + 1, width + 1, top - ah - 1, top, 0, 0, mat, "edge")
			if p.twoHanded:
				box(d, -width, -1, top - ah, top - 1, 0, 0, mat, "blunt")
				box(d, -width - 1, -width - 1, top - ah - 1, top, 0, 0, mat, "edge")
		"mace":
			box(d, 0, 0, handle + 1, top - 4, 0, 0, hm, "blunt")
			var r := maxi(1, half)
			var zr := mini(r, GRID.maxZ)
			for x in range(-r, r + 1):
				for y in range(top - 2 * r - 1, top + 1):
					for z in range(-zr, zr + 1):
						if x * x + (y - (top - r)) * (y - (top - r)) + z * z <= r * r + 1:
							set_voxel(d, x, y, z, mat, "blunt")
			if p.spikes:
				for c in [[r + 1, top - r, 0], [-r - 1, top - r, 0], [0, top + 1, 0], [0, top - r, mini(r + 1, GRID.maxZ)], [0, top - r, -mini(r + 1, GRID.maxZ)]]:
					set_voxel(d, c[0], c[1], c[2], "steel", "point")
		"hammer":
			box(d, 0, 0, handle + 1, top, 0, 0, hm, "blunt")
			var hh := maxi(3, int(width * 0.8))
			box(d, -width, width, top - hh, top, -1, 1, mat, "blunt")
			if p.spikes:
				box(d, -width - 2, -width - 1, top - int(hh / 2), top - int(hh / 2), 0, 0, "steel", "point")
		_:
			box(d, 0, 0, handle + 1, top, 0, 0, hm, "blunt")
			box(d, -half, half, top - int(blade / 2), top, 0, 0, hm, "blunt")
			if p.spikes:
				for y in range(top - int(blade / 2), top + 1, 3):
					set_voxel(d, half + 1, y, 0, "steel", "point")
					set_voxel(d, -half - 1, y, 0, "steel", "point")
	if p.spikes and (p.shape == "sword" or p.shape == "spear"):
		for y in range(handle + 4, top - 3, 4):
			set_voxel(d, -half - 1, y, 0, "steel", "point")
			set_voxel(d, half + 1, y, 0, "steel", "point")
	# Spikes off a blade narrower than they stand out from, and the like: nothing is left
	# hanging in the air, apart from the weapon (Something silly, any card).
	one_piece(d)
	return d

static func silly_simple(rng: RandomNumberGenerator) -> Dictionary:
	var shapes: Array = SIMPLE_SHAPES.keys().filter(func(s): return s != "shield")
	var shape: String = _pick(shapes, rng)
	var sh: Dictionary = SIMPLE_SHAPES[shape]
	var kind := "blade" if shape == "sword" or shape == "dagger" else ("polearm" if shape == "spear" else ("axe" if shape == "axe" else "mace"))
	return {"shape": shape, "blade": rng.randi_range(sh.blade[0], sh.blade[1]), "width": rng.randi_range(sh.width[0], sh.width[1]),
		"handle": rng.randi_range(3, 10), "mat": _pick(SIMPLE_MATERIALS, rng), "handleMat": _pick(["wood", "wood", "iron", "gold"], rng),
		"pommel": rng.randi_range(0, 2), "spikes": rng.randf() < 0.5, "twoHanded": rng.randf() < 0.3, "throwable": rng.randf() < 0.3,
		"sharp": roundf(rng.randf() * 20.0) / 20.0, "name": weapon_name(kind, rng)}

# ---------- The guided forge: a base card, up to two modifier cards ----------

const BASES := {
	"gladius": {"label": "Gladius", "blurb": "The short sword. Quick cuts and stabs.", "params": {"shape": "sword", "blade": 16, "width": 2, "handle": 5, "mat": "steel", "pommel": 1, "sharp": 0.85}},
	"spatha": {"label": "Spatha", "blurb": "A long cavalry sword. Reach and slashes.", "params": {"shape": "sword", "blade": 28, "width": 2, "handle": 6, "mat": "steel", "pommel": 2, "sharp": 0.8}},
	"axe": {"label": "Axe", "blurb": "One heavy edge. Deep cuts, slow swings.", "params": {"shape": "axe", "blade": 18, "width": 4, "handle": 6, "mat": "iron", "pommel": 0, "sharp": 0.7}},
	"hammer": {"label": "Warhammer", "blurb": "A flat head that knocks people over.", "params": {"shape": "hammer", "blade": 20, "width": 4, "handle": 7, "mat": "iron", "pommel": 0, "sharp": 0.0}},
	"spear": {"label": "Spear", "blurb": "Keep them at the end of it.", "params": {"shape": "spear", "blade": 30, "width": 2, "handle": 8, "mat": "steel", "pommel": 0, "sharp": 0.8}},
	"dagger": {"label": "Dagger", "blurb": "Tiny and fast. Get close.", "params": {"shape": "dagger", "blade": 10, "width": 1, "handle": 4, "mat": "steel", "pommel": 1, "sharp": 0.9}},
	"mace": {"label": "Mace", "blurb": "A ball of metal. Never goes dull.", "params": {"shape": "mace", "blade": 16, "width": 3, "handle": 6, "mat": "iron", "pommel": 1, "sharp": 0.0}},
	"shield": {"label": "Shield", "blurb": "Goes in the off hand and blocks.", "params": {"shape": "shield", "blade": 10, "width": 5, "handle": 5, "mat": "wood", "pommel": 0, "sharp": 0.0}},
	"bow": {"label": "Bow", "blurb": "Hold the left button to draw, release to shoot.", "params": {"shape": "bow", "blade": 10, "width": 1, "handle": 5, "mat": "wood", "handleMat": "wood", "pommel": 0, "sharp": 0.0}},
	"javelin": {"label": "Javelin", "blurb": "A light spear made to be thrown. F throws it.", "params": {"shape": "spear", "blade": 20, "width": 1, "handle": 5, "mat": "steel", "pommel": 0, "sharp": 0.8, "throwable": true}},
	"throwingAxe": {"label": "Throwing axe", "blurb": "A small axe that spins when thrown. F throws it.", "params": {"shape": "axe", "blade": 11, "width": 3, "handle": 4, "mat": "steel", "pommel": 0, "sharp": 0.7, "throwable": true}},
	"silly": {"label": "Something silly", "blurb": "Vulcanus rolls the dice.", "params": null},
}

## Each card changes the simple numbers a little and adds a word to the name; `fits` keeps
## nonsense off the table (a serrated hammer, a two-handed dagger).
const MODIFIERS := {
	"longer": {"label": "Longer", "blurb": "More reach, a bit heavier (a bow: a harder draw).", "word": "Long", "fits": "weapon_or_bow", "blade": 8},
	"shorter": {"label": "Shorter", "blurb": "Quicker, less reach.", "word": "Short", "fits": "weapon_not_dagger", "blade": -6},
	"heavyHead": {"label": "Heavy head", "blurb": "Hits harder, swings slower.", "word": "Heavy", "fits": ["axe", "hammer", "mace", "club", "silly"], "width": 2},
	"razor": {"label": "Razor edge", "blurb": "Cuts deeper, bleeds more.", "word": "Razor", "fits": ["gladius", "spatha", "axe", "spear", "dagger", "silly"], "set": {"sharp": 1.0}},
	"serrated": {"label": "Serrated", "blurb": "Teeth along the edge: ugly wounds.", "word": "Serrated", "fits": ["gladius", "spatha", "dagger", "spear", "silly"], "set": {"serrated": true}},
	"spikes": {"label": "Spikes", "blurb": "Steel points: stabbing on every hit.", "word": "Spiked", "fits": "weapon", "set": {"spikes": true}},
	"leadPommel": {"label": "Lead pommel", "blurb": "Balanced: faster swings.", "word": "Balanced", "fits": "weapon", "set": {"pommel": 3}},
	"longHandle": {"label": "Long handle", "blurb": "Steadier grip, a little more reach.", "word": "Long-hafted", "fits": "weapon", "handle": 5},
	"twoHanded": {"label": "Two-handed", "blurb": "Much stronger swings. No shield.", "word": "Great", "fits": "weapon_not_dagger", "set": {"twoHanded": true}},
	"throwable": {"label": "Throwable", "blurb": "F throws it where you aim.", "word": "Throwing", "fits": "weapon", "set": {"throwable": true}},
	"gold": {"label": "Gold", "blurb": "Heavy, soft, the crowd loves it.", "word": "Golden", "fits": "not_bow", "set": {"mat": "gold"}},
	"stone": {"label": "Stone", "blurb": "Very heavy. Crushes.", "word": "Stone", "fits": ["axe", "hammer", "mace", "club", "silly"], "set": {"mat": "stone"}},
	"explosive": {"label": "Explosive", "blurb": "BOOM on a hard hit. Once.", "word": "Exploding", "fits": "weapon", "set": {"mat": "explosive"}},
	"spring": {"label": "Spring", "blurb": "Bounces people across the arena.", "word": "Springy", "fits": "not_bow", "set": {"mat": "spring"}},
	"glue": {"label": "Glue", "blurb": "Sticks to bodies and weapons.", "word": "Sticky", "fits": "not_bow", "set": {"mat": "glue"}},
	"magnet": {"label": "Magnet", "blurb": "Pulls iron weapons out of hands.", "word": "Magnetic", "fits": "weapon", "set": {"mat": "magnet"}},
	"heavyDraw": {"label": "Heavy draw", "blurb": "A stiffer bow: arrows hit harder, slower to draw.", "word": "War", "fits": ["bow"], "set": {"width": 2}, "blade": 2},
	"quickDraw": {"label": "Short bow", "blurb": "Draws fast, hits softer.", "word": "Short", "fits": ["bow"], "blade": -3},
	"fireArrows": {"label": "Fire arrows", "blurb": "Arrows set the sand ablaze where they land.", "word": "Fire", "fits": ["bow"], "set": {"gem": "fire"}},
	"poisonArrows": {"label": "Poison arrows", "blurb": "Wounds that keep bleeding.", "word": "Venom", "fits": ["bow"], "set": {"gem": "poison"}},
	"iceArrows": {"label": "Ice arrows", "blurb": "A hit slows them to a crawl.", "word": "Frost", "fits": ["bow"], "set": {"gem": "ice"}},
	"ironRim": {"label": "Iron rim", "blurb": "A harder shield, heavier.", "word": "Iron-rimmed", "fits": ["shield"], "set": {"mat": "iron"}, "width": 1},
	"tower": {"label": "Tower", "blurb": "A door. A very safe door.", "word": "Tower", "fits": ["shield"], "blade": 4, "width": 2},
}
const MAX_PICKS := 2
const WILD := ["explosive", "spring", "glue", "magnet", "gold", "lead"]

static func mod_fits(key: String, base: String) -> bool:
	var f = MODIFIERS[key].fits
	if f is Array:
		return f.has(base)
	var weapon := base != "shield" and base != "bow"
	match String(f):
		"weapon": return weapon
		"weapon_or_bow": return weapon or base == "bow"
		"weapon_not_dagger": return weapon and base != "dagger"
		"not_bow": return base != "bow"
	return false

static func apply_mod(key: String, p: Dictionary) -> Dictionary:
	var m: Dictionary = MODIFIERS[key]
	var o := p.duplicate()
	if m.has("blade"):
		o.blade = int(o.blade) + int(m.blade)
	if m.has("width"):
		o.width = int(o.width) + int(m.width)
	if m.has("handle"):
		o.handle = int(o.handle) + int(m.handle)
	for k in m.get("set", {}):
		o[k] = m.set[k]
	return o

## `n` cards that fit the base: mostly sensible ones, then a wild one.
static func deal_modifiers(base: String, rng: RandomNumberGenerator, n := 5) -> Array:
	var fit: Array = MODIFIERS.keys().filter(func(k): return mod_fits(k, base))
	var sane: Array = fit.filter(func(k): return not WILD.has(k))
	var odd: Array = fit.filter(func(k): return WILD.has(k))
	var draw := func(pool: Array, k: int) -> Array:
		var out := []
		var p := pool.duplicate()
		while out.size() < k and not p.is_empty():
			out.append(p.pop_at(rng.randi_range(0, p.size() - 1)))
		return out
	var out: Array = draw.call(sane, maxi(1, n - 1))
	out.append_array(draw.call(odd, maxi(1, n - out.size())))
	if out.size() < n:
		out.append_array(draw.call(sane.filter(func(k): return not out.has(k)), n - out.size()))
	return out.slice(0, n)

static func build_from_cards(base_key: String, mod_keys: Array, rng: RandomNumberGenerator, name := "") -> Dictionary:
	var base: Dictionary = BASES.get(base_key, BASES.gladius)
	var p: Dictionary = DEFAULT_SIMPLE.duplicate()
	if base.params != null:
		p.merge(base.params, true)
	else:
		p = silly_simple(rng)
	var mods: Array = mod_keys.filter(func(k): return MODIFIERS.has(k)).slice(0, MAX_PICKS)
	for k in mods:
		p = apply_mod(k, p)
	var words: Array = mods.map(func(k): return MODIFIERS[k].word)
	var label: String = base.label if base.params != null else str(p.get("name", "Thing"))
	p.name = name if name != "" else (" ".join(words) + " " + label).strip_edges().substr(0, 32)
	var d := simple_weapon(p)
	if p.get("serrated", false):
		d.serrated = true
	if p.get("gem") != null:
		d.gem = p.gem
	return d
