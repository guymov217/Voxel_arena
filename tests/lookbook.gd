extends Node
## A look book of gladiators (`-- --probe lookbook`, needs a display): five men in their own
## weapons, the body drawn four ways, by the colour of its own voxels only:
##   0 as they are now;
##   A light and shade: muscles, the rounding of every limb, a face with eyes, nose and lips;
##   B as A, each man his own: hair, beard, eyes, scars, a tan;
##   C as B, with the paint and tattoos of his school;
##   D to G as C, the body drawn in another shape (see _shape), the armour with it.
## Nothing else changes: no voxel added, moved or hidden, no mesh, scale, armour, organ, bone,
## collider, mass or hp. PNGs go to SHOT_DIR.

const KINDS := [
	{"name": "MURMILLO", "skin": 0xc68a5a, "main": "gladius", "off": "scutum",
		"hair": Color(0.09, 0.07, 0.06), "beard": 0.85, "eye": Color(0.22, 0.13, 0.07), "bald": false, "chest": 0.35},
	{"name": "SECUTOR", "skin": 0xa8714a, "main": "gladius", "off": "scutum",
		"hair": Color(0.1, 0.08, 0.07), "beard": 0.0, "eye": Color(0.3, 0.36, 0.28), "bald": true, "chest": 0.0},
	{"name": "THRAEX", "skin": 0xd9a57a, "main": "dagger", "off": "roundShield",
		"hair": Color(0.5, 0.2, 0.08), "beard": 0.55, "eye": Color(0.28, 0.42, 0.6), "bald": false, "chest": 0.25},
	{"name": "RETIARIUS", "skin": 0x8d5a3b, "main": "trident", "off": "",
		"hair": Color(0.05, 0.04, 0.04), "beard": 0.7, "eye": Color(0.15, 0.09, 0.05), "bald": false, "chest": 0.0, "goatee": true},
	{"name": "YOUR GLADIATOR", "skin": 0xc08050, "main": "gladius", "off": "roundShield",
		"hair": Color(0.2, 0.12, 0.07), "beard": 0.35, "eye": Color(0.35, 0.25, 0.1), "bald": false, "chest": 0.15},
]
const SCAR := Color(0.86, 0.6, 0.55)
const LIPS := Color(0.55, 0.27, 0.24)
const OCHRE := Color(0.62, 0.12, 0.08)
const WOAD := Color(0.13, 0.22, 0.48)
const CHALK := Color(0.9, 0.88, 0.8)
const KOHL := Color(0.06, 0.05, 0.05)
const GOLD := Color(0.85, 0.62, 0.2)

var m
var cam: Camera3D
var men: Array = []

func _hash(n: String, x: int, y: int, z: int) -> float:
	var h := (x * 73856093) ^ (y * 19349663) ^ (z * 83492791) ^ n.hash()
	return float(h & 1023) / 1023.0

## How many of the voxel's six sides are open: two or three is a corner of the limb, drawn darker
## so the block reads round.
func _open(p: VoxelPart, i: int) -> int:
	var c := Vector3i(p.fx[i], p.fy[i], p.fz[i])
	var n := 0
	for d in Physique.DIRS:
		if not p._solid(c + d):
			n += 1
	return n

func _shade(c: Color, k: float) -> Color:
	return Color(clampf(c.r * k, 0.0, 1.0), clampf(c.g * k, 0.0, 1.0), clampf(c.b * k, 0.0, 1.0), 1.0)

## Repaints man `f` (KINDS[ki]) in plate A, B or C; only p.colors of his own voxels.
func _look(f, ki: int, plate: String) -> void:
	var K: Dictionary = KINDS[ki]
	var skin := Color.hex(int(K.skin) << 8 | 0xff)
	for p in f.parts:
		var n := String(p.part_name)
		var g: Vector3i = p.grid
		var list := []
		for i in p.fx.size():
			if p.alive[i] == 0 or p.organ[i] != 0:
				continue
			var face := Physique._facing(p, i)
			if face == Vector3i.ZERO:
				continue
			var x: int = p.fx[i]
			var y: int = p.fy[i]
			var z: int = p.fz[i]
			var kind: int = p.kinds[i]
			var c: Color = p.colors[i]
			var r := _hash(n, x, y, z)
			var cx := absf(float(x) - (g.x - 1) * 0.5)
			var front: bool = face.z == 1
			if kind == 0:
				# The muscles, deeper than the game's own, and the light from above.
				var k := 1.0 + (Physique.muscle(n, x, y, z, g, face, cx) - 1.0) * 2.4
				k *= 1.07 if face.y == 1 else (0.8 if face.y == -1 else 1.0)
				if plate != "S":
					# (Not on a man drawn round: his shape does that, and the corners left dark
					# read as stripes down the limbs.)
					var o := _open(p, i)
					k *= 0.84 if o == 2 else (0.74 if o >= 3 else 1.0)
				if n == "head" and front:
					if y == 8 and (x <= 1 or x >= 8):
						k *= 0.9
					if (y == 4 or y == 5) and (x <= 1 or x >= 8):
						k *= 0.88      # the hollow of the cheeks
					if y == 6 and (x == 4 or x == 5):
						k *= 1.06      # the bridge of the nose
					if y == 4 and (x == 4 or x == 5):
						k *= 0.82      # the nostrils
					if y == 1 and x >= 3 and x <= 6:
						k *= 0.86      # under the lip
				c = _shade(c, k)
				if plate not in ["A"]:
					# Sun on the shoulders and the forearms, paler where the belt and sandals sit.
					if (n.begins_with("upperArm") and y >= 9) or (n == "torso" and y >= 19):
						c = c.lerp(c * Color(0.92, 0.82, 0.74), 0.5)
					if n == "head":
						var jaw: bool = (front and y <= 3 and (x <= 1 or x >= 8)) or (front and y <= 1) \
							or (face.x != 0 and y <= 4 and z >= 5) or (face.y == -1 and z >= 4)
						if K.get("goatee", false):
							jaw = front and y <= 1 and x >= 3 and x <= 6
						if jaw and float(K.beard) > 0.0:
							c = c.lerp(K.hair, float(K.beard) * (0.75 + 0.25 * r))
						if K.bald and (y >= 10 or face.y == 1):
							c = c.lerp(K.hair, 0.12 + 0.06 * r)   # a shaven head's shadow
					if n == "torso" and front and float(K.chest) > 0.0 and cx < 3.5 and y >= 13 and y <= 17:
						c = c.lerp(K.hair, float(K.chest) * r)
					if _scar(ki, n, face, x, y, z):
						c = c.lerp(SCAR, 0.55)
				if plate in ["C", "S"]:
					var pc = _paint(ki, n, face, x, y, z, g, cx)
					if pc != null:
						c = c.lerp(pc, 0.82)
			elif kind == 2 and n == "head":
				if front and y == 6 and (x == 3 or x == 6):
					c = K.eye if plate != "A" else Color(0.18, 0.12, 0.08)   # the iris
				elif front and y == 6:
					c = KOHL
				elif front and y == 9:
					c = K.hair.darkened(0.2) if plate != "A" else c       # the brows
				elif plate not in ["A"]:
					if K.bald:
						c = _shade(skin, 0.9 if face.y == 1 else 0.82).lerp(K.hair, 0.15 + 0.06 * r)
					else:
						c = K.hair.lerp(K.hair.lightened(0.35), 0.35 if face.y == 1 and r > 0.6 else 0.0)
						c = _shade(c, 0.85 + 0.25 * r)                  # strands
				if plate in ["C", "S"] and ki == 4 and front and y == 6 and (x == 2 or x == 7):
					c = KOHL
			elif kind == 9 and n == "head":
				c = LIPS.lerp(skin, 0.25)
			elif kind == 6 and n == "head" and front and y == 3:
				c = _shade(LIPS, 0.7)   # lips closed over the teeth
			else:
				continue
			if c == p.colors[i]:
				continue
			p.colors[i] = c
			list.append(i)
		if not list.is_empty():
			p.refresh_colors(list)

## Plates D to G: the body drawn in another shape, drawing only. Each voxel of a part (and each
## plate of its armour, by the same map, so it still sits on him) is drawn moved and sized within
## the part: where it hits, how it breaks, its organs, bones, mass and colliders stay the voxels'
## own cubes, as in the game.
##   D the cross-section of every part a rounded square, the shoulders and crown sloped;
##   E as D, shaped as a man: thighs full at the hip and narrow at the knee, a calf, a slim wrist
##     and ankle, a chest broader than the waist, a narrower jaw; the ends of the limbs drawn
##     reaching into the next part, so the body reads one piece at the shoulder, elbow, hip and knee;
##   F as E, cut in facets (an octagon across), a carved statue's planes instead of a curve;
##   G as E, a heavier man: broader chest and shoulders, thicker arms and thighs;
##   H as G, in the game's own voxel drawing (no chamfered corners).
const ROUND := {"torso": [3.2, 3.0], "head": [2.6, 2.4]}
const ROUND_E := {"torso": [2.8, 5.0], "head": [2.4, 2.6], "upperArmR": [2.6, 0.0], "upperArmL": [2.6, 0.0]}

func _smooth(a: float, b: float, t: float) -> float:
	return lerpf(a, b, smoothstep(0.0, 1.0, clampf(t, 0.0, 1.0)))

## The man's width across x and z at height t (0 the bottom of the part, 1 its top).
func _taper(n: String, t: float, heavy: bool) -> Vector2:
	var k := 1.0
	var kz := 1.0
	match n:
		"thighR", "thighL":
			k = _smooth(0.86, 1.04, t)                      # the knee up to the hip
			k *= 1.05 if heavy else 1.0
			kz = k
		"shinR", "shinL":
			if t < 0.22:
				k = 1.0                                     # the foot
			elif t < 0.45:
				k = _smooth(0.8, 0.84, (t - 0.22) / 0.23)    # the ankle
			elif t < 0.75:
				k = _smooth(0.84, 1.0, (t - 0.45) / 0.3)     # the calf
			else:
				k = _smooth(1.0, 0.86, (t - 0.75) / 0.25)    # up to the knee
			kz = k
		"upperArmR", "upperArmL":
			k = _smooth(0.9, 1.08, t / 0.6)                 # the elbow to the biceps and deltoid
			k *= 1.08 if heavy else 1.0
			kz = k
		"forearmR", "forearmL":
			if t < 0.22:
				k = 0.96                                    # the fist
			elif t < 0.4:
				k = _smooth(0.78, 0.8, (t - 0.22) / 0.18)    # the wrist
			else:
				k = _smooth(0.82, 1.0, (t - 0.4) / 0.4)      # the forearm up to the elbow
			k *= 1.06 if heavy else 1.0
			kz = k
		"torso":
			if t < 0.3:
				k = 0.97                                    # the hips, on the thighs
			elif t < 0.5:
				k = _smooth(0.97, 0.9, (t - 0.3) / 0.2)      # the waist
			else:
				k = _smooth(0.92, 1.07 if not heavy else 1.13, (t - 0.5) / 0.3)   # the chest and broad shoulders
			kz = 1.0 - (1.0 - k) * 0.5 if k < 1.0 else 1.0 + (k - 1.0) * 0.6
		"head":
			k = _smooth(0.86, 1.0, t / 0.45)                # the jaw narrower than the crown
			kz = _smooth(0.94, 1.0, t / 0.45)
	return Vector2(k, kz)

## How far the end rows of a part are drawn into the next one (in voxels): the shoulder, elbow,
## hip, knee and neck, not the fist or the foot.
func _reach(n: String) -> Vector2:
	match n:
		"upperArmR", "upperArmL":
			return Vector2(1.0, 1.6)   # (bottom, top): the deltoid over the shoulder
		"thighR", "thighL":
			return Vector2(1.0, 1.0)
		"forearmR", "forearmL", "shinR", "shinL":
			return Vector2(0.0, 1.0)
		"head":
			return Vector2(2.0, 0.0)   # a neck down into the shoulders
	return Vector2.ZERO

func _shape_map(plate: String, n: String, q: Vector3, h: Vector3, vox: float) -> Array:
	var round_: Dictionary = ROUND if plate == "D" else ROUND_E
	var e: Array = round_.get(n, [2.4 if plate == "D" else 2.6, 0.0])
	var s := Vector3.ONE
	var p := q
	var u := Vector2(p.x / h.x, p.z / h.z)
	var sq := maxf(absf(u.x), absf(u.y))
	if sq > 0.0001:
		var se: float
		if plate == "F":
			se = maxf(sq, (absf(u.x) + absf(u.y)) / 1.42)   # an octagon
		else:
			se = pow(pow(absf(u.x), e[0]) + pow(absf(u.y), e[0]), 1.0 / e[0])
		var f := sq / se
		p.x *= f
		p.z *= f
		s.x *= f
		s.z *= f
	if e[1] > 0.0 and q.y > 0.0:
		var v := Vector2(q.x / h.x, q.y / h.y)
		var sq2 := maxf(absf(v.x), absf(v.y))
		if sq2 > 0.0001:
			var se2: float
			if plate == "F":
				se2 = maxf(sq2, (absf(v.x) + absf(v.y)) / 1.42)
			else:
				se2 = pow(pow(absf(v.x), e[1]) + pow(absf(v.y), e[1]), 1.0 / e[1])
			var f2 := sq2 / se2
			p.x *= f2
			p.y = q.y * f2
			s.x *= f2
			if plate == "D":
				s.y *= f2
	if plate != "D":
		var t := clampf((q.y / h.y + 1.0) * 0.5, 0.0, 1.0)
		var k := _taper(n, t, plate == "G" or plate == "H")
		p.x *= k.x
		p.z *= k.y
		s.x *= k.x
		s.z *= k.y
		# The ends drawn into the next part: the last row stretched outward.
		var r := _reach(n)
		var edge := h.y - vox
		if vox <= 0.0:
			pass
		elif r.y > 0.0 and q.y > edge - 0.01 * vox:
			p.y += r.y * vox * 0.5
			s.y *= 1.0 + r.y
		elif r.x > 0.0 and q.y < -edge + 0.01 * vox:
			p.y -= r.x * vox * 0.5
			s.y *= 1.0 + r.x
	return [p, s]

func _shape(f, plate: String) -> void:
	for p in f.parts:
		if p.mm == null:
			continue
		var n := String(p.part_name)
		var vox: float = p.vf * p.part_scale
		var h: Vector3 = Vector3(p.grid) * vox * 0.5
		for i in p.fx.size():
			var r := _shape_map(plate, n, p.local_of(i), h, vox)
			p.mm.set_instance_transform(i, Transform3D(Basis.from_scale(r[1] * 1.06), r[0]))
		for c in p.get_children():
			if c is MultiMeshInstance3D and c != p.mmi and c.multimesh:
				var mmz: MultiMesh = c.multimesh
				for j in mmz.instance_count:
					var t := mmz.get_instance_transform(j)
					var r := _shape_map(plate, n, t.origin, h, 0.0)
					mmz.set_instance_transform(j, Transform3D(t.basis * Basis.from_scale(r[1] * 1.04), r[0]))
		if plate == "H":
			continue   # the game's own voxel drawing, no chamfer: no lines down the limbs
		p.set_look(PackedByteArray(), true)
		if p.mmi:
			p.mmi.material_override = VoxelPart.look_material(false)

const METALS :=["steel", "iron", "bronze", "gold", "lead", "magnet"]

## Repaints a weapon or shield by its voxels' colour only: the edge honed bright, a fuller down
## the blade, the metal lighter toward the point, wood in its grain, leather wrapped round the
## grip, every corner darker so the block reads round.
func _weapon_look(w) -> void:
	if w == null or not is_instance_valid(w) or w.mm == null:
		return
	var cells := {}
	var lo := Vector3i(999, 999, 999)
	var hi := -lo
	for v in w.vox:
		var k := Vector3i(roundi(float(v[0])), roundi(float(v[1])), roundi(float(v[2])))
		cells[k] = str(v[3])
		lo = Vector3i(mini(lo.x, k.x), mini(lo.y, k.y), mini(lo.z, k.z))
		hi = Vector3i(maxi(hi.x, k.x), maxi(hi.y, k.y), maxi(hi.z, k.z))
	var ext := hi - lo
	var la := 0   # the long axis
	for a in 3:
		if ext[a] > ext[la]:
			la = a
	for i in w.vox.size():
		var v: Array = w.vox[i]
		var k := Vector3i(roundi(float(v[0])), roundi(float(v[1])), roundi(float(v[2])))
		var mat := str(v[3])
		var type := str(v[4])
		var c: Color = Weapon.voxel_color(mat, type)
		var open := 0
		for d in Physique.DIRS:
			if not cells.has(k + d):
				open += 1
		var r := _hash(mat, k.x, k.y, k.z)
		var along := float(k[la] - lo[la]) / maxf(1.0, float(ext[la]))
		if METALS.has(mat):
			c = _shade(c, 0.9 + 0.16 * along + (r - 0.5) * 0.08)   # polished toward the point
			if type == "edge" or type == "point":
				c = c.lerp(Color(0.96, 0.97, 1.0), 0.45)            # the honed line
			else:
				# The fuller: a blade's middle, between metal on both sides across it.
				var mid := 0
				for a in 3:
					if a == la:
						continue
					var d := Vector3i.ZERO
					d[a] = 1
					if cells.get(k + d, "") == mat and cells.get(k - d, "") == mat:
						mid += 1
				if mid == 1 and along > 0.15 and along < 0.85:
					c = _shade(c, 0.72)
			if mat == "bronze" or mat == "gold":
				c = c.lerp(Color(1.0, 0.86, 0.5), 0.18 if r > 0.7 else 0.0)
		elif mat == "wood":
			var across := 0
			for a in 3:
				if a != la:
					across += k[a] * (a + 3)
			c = _shade(c, 0.86 + 0.12 * sin(float(across) * 1.7 + float(k[la]) * 0.25) + (r - 0.5) * 0.08)
		elif mat == "leather":
			c = _shade(c, 1.12 if int(k[la] + (k[(la + 1) % 3])) % 3 == 0 else 0.8)   # the wrapping
		c = _shade(c, 1.0 if open <= 1 else (0.86 if open == 2 else 0.76))
		w.mm.set_instance_color(i, c)

func _scar(ki: int, n: String, face: Vector3i, x: int, y: int, z: int) -> bool:
	match ki:
		0:
			return n == "torso" and face.z == 1 and x + 12 == y and x >= 2 and x <= 7
		1:
			# The secutor's face cut across and a chest full of them.
			return (n == "head" and face.z == 1 and x == y - 1 and y >= 3 and y <= 8) \
				or (n == "torso" and face.z == 1 and ((y == 17 and x >= 9 and x <= 13) or (x == 12 and y >= 9 and y <= 12) or (y == 14 and x >= 1 and x <= 4))) \
				or (n.begins_with("upperArm") and face.x != 0 and (y == 7 or y == 10) and z >= 2 and z <= 4)
		2:
			return n == "forearmL" and face.z == 1 and y == 8
		3:
			return n == "head" and face.z == 1 and x == 1 and y >= 6 and y <= 9
		4:
			return n == "head" and face.z == 1 and x == 7 and y >= 8 and y <= 10
	return false

## The paint or ink of his school at a skin voxel, or null.
func _paint(ki: int, n: String, face: Vector3i, x: int, y: int, z: int, g: Vector3i, cx: float):
	match ki:
		0:
			# Murmillo: a band of red ochre across the eyes, red to the elbow.
			if n == "head" and (face.z == 1 or face.x != 0) and y >= 6 and y <= 7:
				return OCHRE
			if n.begins_with("forearm") and y >= 11:
				return OCHRE
		1:
			# Secutor: a black stripe down the middle of the face and the chest (the scars are his).
			if n == "head" and face.z == 1 and (x == 4 or x == 5) and y >= 6:
				return KOHL
			if n == "torso" and face.z == 1 and cx < 1.0 and y >= 8:
				return KOHL
		2:
			# Thraex: Thracian woad: rings round the arms, a sun on the chest, a mark on each cheek.
			if n.begins_with("upperArm") and (y == 5 or y == 6 or y == 9):
				return WOAD
			if n.begins_with("forearm") and (y == 7 or y == 10):
				return WOAD
			if n == "torso" and face.z == 1:
				var d := Vector2(cx, float(y) - 15.5).length()
				if absf(d - 2.6) < 0.6 or (d < 4.2 and d > 3.2 and int(y + x) % 2 == 0):
					return WOAD
			if n == "head" and face.z == 1 and y == 5 and (x == 1 or x == 8):
				return WOAD
			if n.begins_with("thigh") and face.z == 1 and (y == 6 or y == 7):
				return WOAD
		3:
			# Retiarius: chalk waves on the shoulders and the chest, a net inked on the left arm.
			if n == "torso" and face.z == 1 and y >= 16 and y <= 19 and (y - 16) == int(absf(float((x % 4) - 2))):
				return CHALK
			if n == "upperArmL" and (x + y) % 3 == 0 and (x - y + 30) % 3 == 0:
				return Color(0.05, 0.06, 0.12)
			if n == "upperArmL" and ((x + y) % 3 == 0 or (x - y + 30) % 3 == 0) and y >= 3:
				return Color(0.1, 0.12, 0.2)
			if n == "head" and face.z == 1 and y == 4 and (x <= 2 or x >= 7):
				return CHALK
		4:
			# Yours: a gold band round the right arm and a red hand on the chest.
			if n == "upperArmR" and (y == 10 or y == 11):
				return GOLD
			if n == "torso" and face.z == 1:
				var hx := cx - 3.5
				var hy := float(y) - 13.0
				if x >= 8 and ((absf(hx) <= 1.6 and hy >= -1.0 and hy <= 1.5) or (hy > 1.5 and hy <= 4.0 and int(x) % 2 == 0 and absf(hx) <= 2.0)):
					return OCHRE
			if n == "head" and face.z == 1 and y == 5 and (x == 1 or x == 8):
				return GOLD
	return null

func _lineup(plate: String) -> void:
	men = []
	for i in KINDS.size():
		var k: Dictionary = KINDS[i]
		var e = m.spawn_fighter({"kind": "bot", "name": k.name, "loadout": {"main": k.main, "off": k.off}, "team": 1, "pos": Vector3((i - 2) * 1.5, 0.1, 0.0), "yaw": PI, "skin": k.skin})
		e.erase("bot")
		e.drive = func(_e): return {"main": {"x": 0.3, "y": 0.35}, "off": {"x": -0.35, "y": 0.25}}
		men.append(e.f)
		if plate != "0":
			_look(e.f, i, "S" if plate >= "D" else plate)
			if plate >= "D":
				_shape(e.f, plate)
			for s in e.f.weapons:
				_weapon_look(e.f.weapons[s])
	for i in 50:
		await get_tree().physics_frame

func _snap(out: String, name: String, pos: Vector3, look: Vector3, fov := 42.0) -> void:
	cam.global_position = pos
	cam.look_at(look, Vector3.UP)
	cam.fov = fov
	for i in 24:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(out.path_join(name))
	print("saved ", name)

func _ready() -> void:
	var out := OS.get_environment("SHOT_DIR")
	var plates := OS.get_environment("PLATES")
	OS.set_environment("VA_BODIES", "blocky")
	Physique.forced = "classic"
	for plate in (plates.split(",") if plates != "" else PackedStringArray(["0", "A", "B", "C", "D", "E", "F", "G"])):
		m = Match.new()
		add_child(m)
		m.setup({"mode": "training", "training": {"enemy": "none"}, "decrees": [], "hazards": [], "seed": 3})
		m.me.f.teleport(Vector3(0, 0, 30))
		var hud = m.get("hud")
		if hud and hud is CanvasItem:
			hud.visible = false
		if m.cam:
			m.cam.set_process(false)
		cam = Camera3D.new()
		m.add_child(cam)
		cam.make_current()
		await _lineup(plate)
		await _snap(out, "look_%s_lineup.png" % plate, Vector3(0, 1.5, -5.8), Vector3(0, 1.05, 0), 48.0)
		await _snap(out, "look_%s_faces.png" % plate, Vector3(-0.75, 1.75, -2.6), Vector3(-0.75, 1.55, 0), 44.0)
		await _snap(out, "look_%s_side.png" % plate, Vector3(4.6, 1.5, -2.6), Vector3(2.2, 1.05, 0), 40.0)
		men = []
		m.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame
	get_tree().quit()
