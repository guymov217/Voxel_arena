class_name Physique
extends RefCounted
## A gladiator's look (Options, Graphics): five ways of drawing the same man besides the classic
## blocks. Drawing only. Every voxel, organ, bone, joint, collider, mass and hp is the classic
## man's: a style changes what is drawn and how, never what is there.
##
## Four things a style may do, all through VoxelPart's drawing:
## - veil: pare a shell of voxels from the outline (a neck, sloped shoulders, a waist, rounded
##   limbs). A veiled voxel is still there for every blow, cut and count; it is only not drawn.
##   Only ever over plain flesh: never an organ or a bone, nor anything that would uncover one,
##   so whatever a wound opens is what it opens on the classic man. The flesh bared under the
##   shell is drawn in the colour of the skin pared off it.
## - bevel: the body's outer edges drawn chamfered (the shader pulls in the corners where open
##   faces meet; nothing inside is uncovered).
## - paint: light and shade on the skin (muscles, wear), and an oiled sheen. Colours only.
## - shape (the strong man): every voxel drawn moved and sized within its part (VoxelPart.
##   set_shape): limbs and torso a rounded square across, tapered as a man is, broad in the chest
##   and the shoulders, the ends of the limbs drawn into the next part so the body reads one piece
##   at the shoulder, elbow, hip, knee and neck. The armour is drawn by the same map, so it sits
##   on him. The cubes stay where they are for everything else.
## A man's own choices (skin, hair, beard, armour) are worn over any of them. Each player picks
## for himself; nothing of it goes over the network.

const STYLES := ["strong", "classic", "sculpted", "heroic", "anatomy", "worn", "oiled"]
const NAMES := {
	"strong": "Strong gladiator",
	"classic": "Classic blocks",
	"sculpted": "Sculpted",
	"heroic": "Heroic",
	"anatomy": "Anatomy",
	"worn": "Arena-worn",
	"oiled": "Oiled champion",
}
const BLURB := {
	"strong": "Broad, muscled men built of voxels: rounded, tapered limbs, one body from neck to feet.",
	"classic": "The gladiators as they were: square blocks.",
	"sculpted": "A neck, sloped shoulders, rounded limbs, bevelled edges.",
	"heroic": "Sculpted, with a narrow waist under a broad chest.",
	"anatomy": "Sculpted, the muscles drawn in light and shade.",
	"worn": "Anatomy, with arena sand on the legs, old scars and linen-wrapped fists.",
	"oiled": "Heroic and muscled, the skin oiled to shine under the sun.",
}
const DIRS := [Vector3i(0, 0, 1), Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, -1), Vector3i(0, 1, 0), Vector3i(0, -1, 0)]

static var forced := ""   # set by tests; else the player's setting

## The game draws every man as the strong gladiator (one look, no choice in the menus); the
## other styles are kept for the tests and the look studies (`forced`).
static func current() -> String:
	return forced if forced != "" else "strong"

## Men only, in their own skins: beasts, and giants with their own heads, keep theirs.
static func applies(f) -> bool:
	return f is Fighter and not (f is Beast) and String(f.mods.get("look", "")) == ""

## Draws `f` in `style` (the setting when empty), from whatever look he had: at spawn, or any
## time after, wounded or not; nothing of his state changes.
static func dress(f, style := "") -> void:
	if style == "":
		style = current()
	if not applies(f):
		return
	for p in f.parts:
		_undo(p)
		if style == "classic" or p.missing or p.prosthetic != "":
			p.set_look(PackedByteArray(), false)
			_material(p, "classic")
			continue
		if style == "strong":
			p.set_look(PackedByteArray(), false)
			_paint(p, style)
			if p == f.get("head"):
				if f.get("is_bot"):
					_face(p, hash(str(f.display_name)) ^ int(f.slot) * 7919)
				var worn := beard_worn(p)
				if worn != "":
					_paint_face(p, ArmorStyle.base_color(worn, {}, f.skin), false, BEARD_PAINT.get(worn, 2), false)
			_material(p, "classic")   # the game's own voxels: crisp, no chamfer
			p.set_shape(shape_of(p))
			continue
		p.set_look(_veil(p, style), true)
		_bare(p)
		if style == "anatomy" or style == "worn" or style == "oiled":
			_paint(p, style)
		_material(p, style)
		p.resync_later()
	_faces(f)
	f.set_meta("physique", style)
	if f.has_method("place_armor"):
		f.place_armor()

## Every man in the tree under `root` drawn in the setting's look again (Options).
static func restyle_all(root: Node) -> void:
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Fighter:
			dress(n)
			continue
		stack.append_array(n.get_children())

static func _material(p: VoxelPart, style: String) -> void:
	if p.mmi:
		p.mmi.material_override = null if style == "classic" else VoxelPart.look_material(style == "oiled")

# ---------- The shell ----------

## The voxels a style would pare away at this cell of a part (before the safety rules).
static func shell(n: String, x: int, y: int, z: int, g: Vector3i, style: String) -> bool:
	var heroic := style == "heroic" or style == "oiled"
	var ex := mini(x, g.x - 1 - x)
	var ez := mini(z, g.z - 1 - z)
	var yt := g.y - 1 - y
	var front := z == g.z - 1
	match n:
		"head":
			# The jaw narrower than the cheeks, the nape curving in to the neck (the skull is
			# right under the skin above: that stays whole and is bevelled only).
			if y <= 3 and ex == 0:
				return true
			if y <= 1 and (ex <= 1 or z <= 2):
				return true
			if z == 0 and y <= 3:
				return true
			return false
		"torso":
			if yt == 0 and (ex <= 4 or ez <= 1):
				return true   # the trapezius sloping up to the neck
			if yt == 1 and (ex <= 1 or ez == 0):
				return true
			if ex == 0 and ez == 0:
				return true
			if ex == 0 and y >= 6 and y <= 14:
				return true   # the waist under the ribs
			if ex == 1 and y >= 7 and y <= 10 and ez <= 1:
				return true
			if heroic and ((ex == 1 and y >= 6 and y <= 12) or (ex == 2 and y >= 7 and y <= 10 and ez <= 1)):
				return true
			if front and y >= 8 and y <= 10:
				return true   # the belly under the chest
			if z == 0 and y >= 7 and y <= 10 and ex >= 3:
				return true   # the small of the back
			return false
		"upperArmR", "upperArmL":
			if ex == 0 and ez == 0:
				return true
			if yt == 0 and (ex == 0 or ez == 0):
				return true   # the round of the shoulder
			if y <= 3 and ((ex == 0 and ez <= 1) or (ez == 0 and ex <= 1)):
				return true   # in to the elbow
			if heroic and y <= 6 and (ex == 0 or ez == 0):
				return true
			return false
		"forearmR", "forearmL":
			if ex == 0 and ez == 0:
				return true
			if y >= 4 and y <= 5 and (ex == 0 or ez == 0):
				return true   # the wrist
			return false
		"thighR", "thighL":
			if ex + ez <= 1:
				return true
			if y <= 2 and (ex == 0 or ez == 0):
				return true   # in to the knee
			if heroic and y <= 6 and ex + ez <= 2:
				return true
			return false
		"shinR", "shinL":
			if y >= 4:
				if ex + ez <= 1:
					return true
				if y <= 7 and (ex == 0 or (ez == 0 and z == 0)):
					return true   # the calf high behind, the shin narrowing to the ankle
				return false
			if y >= 2 and (ex == 0 or z <= 1):
				return true   # the ankle over a long low foot
			if z == 0 and ex <= 1:
				return true   # the heel
			return false
	return false

## What must never be veiled or bared: an organ or a bone (a wound must open on them as on the
## classic man).
static func _inner(p: VoxelPart, i: int) -> bool:
	return p.organ[i] != 0 or p.bone[i] == 1

static func _veil(p: VoxelPart, style: String) -> PackedByteArray:
	var n := p.fx.size()
	var v := PackedByteArray()
	v.resize(n)
	v.fill(0)
	var cand := {}
	for i in n:
		if p.alive[i] == 1 and not _inner(p, i) and shell(p.part_name, p.fx[i], p.fy[i], p.fz[i], p.grid, style):
			cand[i] = true
	# Drop every voxel of the shell that would uncover an organ or a bone, until none would.
	var changed := true
	while changed:
		changed = false
		for i in cand.keys():
			for d in DIRS:
				var j := p._cell(p.fx[i] + d.x, p.fy[i] + d.y, p.fz[i] + d.z)
				if j >= 0 and p.alive[j] == 1 and not cand.has(j) and _inner(p, j):
					cand.erase(i)
					changed = true
					break
	for i in cand:
		v[i] = 1
	return v

## Was voxel i out of sight with nothing veiled (every side against a living voxel)?
static func _was_hidden(p: VoxelPart, i: int) -> bool:
	for d in DIRS:
		var j := p._cell(p.fx[i] + d.x, p.fy[i] + d.y, p.fz[i] + d.z)
		if j < 0 or p.alive[j] == 0:
			return false
	return true

## The flesh bared under the shell takes the look of the outside pared off it: the colour and
## kind of the outermost veiled voxel straight out from it.
static func _bare(p: VoxelPart) -> void:
	var saved: Dictionary = p.get_meta("look_saved", {})
	var list := []
	for i in p.fx.size():
		if p.alive[i] == 0 or p.veiled(i) or not _was_hidden(p, i):
			continue
		for d in DIRS:
			var j := p._cell(p.fx[i] + d.x, p.fy[i] + d.y, p.fz[i] + d.z)
			if j < 0 or not p.veiled(j):
				continue
			var src := j
			var k := 2
			while true:
				var q := p._cell(p.fx[i] + d.x * k, p.fy[i] + d.y * k, p.fz[i] + d.z * k)
				if q < 0 or not p.veiled(q):
					break
				src = q
				k += 1
			_keep(saved, p, i)
			p.colors[i] = p.colors[src]
			p.kinds[i] = p.kinds[src]
			saved[i][2] = p.colors[i]
			list.append(i)
			break
	p.set_meta("look_saved", saved)
	_redraw(p, list)

static func _keep(saved: Dictionary, p: VoxelPart, i: int) -> void:
	if not saved.has(i):
		saved[i] = [p.colors[i], p.kinds[i], p.colors[i]]

static func _redraw(p: VoxelPart, list: Array) -> void:
	if list.is_empty():
		return
	p.refresh_colors(list)
	for i in list:
		p._set_status(i, p.glowing.get(i, Vector2.ZERO))

## Back to the colours the man had before his look (those a blow or a flame has not changed
## since: blood, a burn or a scar stays).
static func _undo(p: VoxelPart) -> void:
	if not p.shape_xf.is_empty():
		p.set_shape([])
	var saved: Dictionary = p.get_meta("look_saved", {})
	if saved.is_empty():
		return
	var list := []
	for i in saved:
		if p.colors[i] == saved[i][2]:
			p.colors[i] = saved[i][0]
		p.kinds[i] = saved[i][1]
		list.append(i)
	p.set_meta("look_saved", {})
	_redraw(p, list)

# ---------- Paint ----------

## Which way voxel i faces out, as drawn now (+z first: the front of the man).
static func _facing(p: VoxelPart, i: int) -> Vector3i:
	for d in DIRS:
		if not p._solid(Vector3i(p.fx[i], p.fy[i], p.fz[i]) + d):
			return d
	return Vector3i.ZERO

const LINEN := Color(0.85, 0.81, 0.71)
const LINEN_FOLD := Color(0.72, 0.67, 0.53)
const SAND := Color(0.62, 0.5, 0.35)

static func _paint(p: VoxelPart, style: String) -> void:
	var saved: Dictionary = p.get_meta("look_saved", {})
	var list := []
	var n := p.part_name
	var g := p.grid
	for i in p.fx.size():
		if p.alive[i] == 0 or p.veiled(i) or p.kinds[i] != 0:
			continue
		var face := _facing(p, i)
		if face == Vector3i.ZERO:
			continue
		var x: int = p.fx[i]
		var y: int = p.fy[i]
		var z: int = p.fz[i]
		var cx := absf(float(x) - (g.x - 1) * 0.5)
		var k := 1.0 + (muscle(n, x, y, z, g, face, cx) - 1.0) * 1.8
		if style == "strong":
			# The muscles deeper, lit from above: the shape reads in the light.
			k = 1.0 + (muscle(n, x, y, z, g, face, cx) - 1.0) * 2.4
			k *= 1.07 if face.y == 1 else (0.82 if face.y == -1 else 1.0)
		var c: Color = p.colors[i]
		var kind := 0
		if style == "worn":
			var h := (x * 73856093) ^ (y * 19349663) ^ (z * 83492791) ^ n.hash()
			var r := float(h & 1023) / 1023.0
			if n.begins_with("forearm") and y >= 1 and y <= 3:
				# Linen wrapped round the fists.
				c = LINEN if (x + y + z) % 3 != 0 else LINEN_FOLD
				k = 1.0
				kind = 1
			elif n.begins_with("shin") and (y <= 5 or (y <= 9 and r > 0.35)):
				c = c.lerp(SAND, 0.32 + 0.18 * r)   # arena sand caked on the feet and shins
			elif n.begins_with("thigh") and y <= 6 and r > 0.65:
				c = c.lerp(SAND, 0.22)
			if (n == "torso" and face.z == 1 and ((y == 17 and x >= 3 and x <= 8) or (x == 11 and y >= 10 and y <= 13))) \
					or (n.begins_with("upperArm") and face.x != 0 and y == 8 and z >= 2 and z <= 4) \
					or (n == "head" and face.z == 1 and x == 7 and y >= 3 and y <= 5):
				c = c.lerp(VoxelPart.SCAR, 0.45)   # old scars, pale and pink
		if k == 1.0 and c == p.colors[i] and kind == 0:
			continue
		_keep(saved, p, i)
		p.colors[i] = Color(clampf(c.r * k, 0.0, 1.0), clampf(c.g * k, 0.0, 1.0), clampf(c.b * k, 0.0, 1.0), 1.0)
		p.kinds[i] = kind
		saved[i][2] = p.colors[i]
		list.append(i)
	p.set_meta("look_saved", saved)
	_redraw(p, list)

## A bot gladiator of the strong look his own face, in colour only (the player wears what he
## chose): his hair black, brown, red or grey, or the head shaved; clean-shaven, stubble, a full
## beard, a goatee or a moustache. From `seed`, so the same man looks the same every time.
const HAIRS := [Color(0.08, 0.06, 0.05), Color(0.2, 0.12, 0.07), Color(0.33, 0.2, 0.1), Color(0.45, 0.2, 0.08), Color(0.42, 0.4, 0.38), Color(0.55, 0.42, 0.22)]
static func _face(p: VoxelPart, seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var hair: Color = HAIRS[rng.randi() % HAIRS.size()]
	var shaved := rng.randf() < 0.2
	var beard := rng.randi() % 5   # 0 none, 1 stubble, 2 full, 3 goatee, 4 moustache
	_paint_face(p, hair, shaved, beard, true)

## A beard worn (the cosmetic piece) is drawn in the strong look as the face's own voxels in the
## hair's colour (fine, on the jaw), its cells only for what hangs below the chin (plate_xf).
const BEARD_PAINT := {"beard_full": 2, "beard_braided": 2, "beard_philosopher": 2, "beard_forked": 2, "beard_short": 1, "beard_stubble": 7, "beard_goatee": 3, "beard_moustache": 4, "beard_mutton": 5, "beard_chinstrap": 6}
static func beard_worn(p: VoxelPart) -> String:
	for ad in p.get_meta("armor", []):
		if String(ad.id).begins_with("beard_"):
			return String(ad.id)
	return ""

## The face painted: `hair` the colour of his hair and beard, `shaved` his crown bare, `beard` as
## in _face (0 none), the crown and brows only when `crown`.
static func _paint_face(p: VoxelPart, hair: Color, shaved: bool, beard: int, crown: bool) -> void:
	var saved: Dictionary = p.get_meta("look_saved", {})
	var list := []
	var g := p.grid
	var skin_c := Color(0.6, 0.4, 0.3)
	for i in p.fx.size():
		if p.kinds[i] == 0 and p.fy[i] == 5 and p.fz[i] == g.z - 1:
			skin_c = p.colors[i]   # (a cheek: the skin's own colour)
			break
	for i in p.fx.size():
		if p.alive[i] == 0 or p.organ[i] != 0:
			continue
		var face := _facing(p, i)
		if face == Vector3i.ZERO:
			continue
		var x: int = p.fx[i]
		var y: int = p.fy[i]
		var z: int = p.fz[i]
		var front: bool = face.z == 1
		var c: Color = p.colors[i]
		var r := float(((x * 73856093) ^ (y * 19349663) ^ (z * 83492791)) & 1023) / 1023.0
		if crown and p.kinds[i] == 2 and y >= g.y - 2:
			c = skin_c.darkened(0.12).lerp(hair, 0.18) if shaved else hair.lerp(hair.lightened(0.3), 0.3 * r)
		elif crown and p.kinds[i] == 2 and front and y == g.y - 3:
			c = hair.darkened(0.15)   # the brows his hair's colour
		elif p.kinds[i] == 0 and beard > 0:
			var jaw: bool = (front and y <= 1) or (front and y <= 3 and (x <= 1 or x >= g.x - 2)) \
				or (face.x != 0 and y <= 4 and z >= g.z / 2) or (face.y == -1 and z >= g.z / 2 - 1)
			var k := 0.0
			match beard:
				1: k = (0.35 if crown else 0.6) if jaw else 0.0
				2: k = 0.85 if jaw else 0.0
				3: k = 0.85 if front and y <= 1 and x >= 4 and x <= g.x - 5 else 0.0
				4: k = 0.85 if front and y == 4 and x >= 2 and x <= g.x - 3 and (x <= 3 or x >= g.x - 4) else 0.0
				5: k = 0.85 if (front and y <= 4 and (x <= 1 or x >= g.x - 2)) or (face.x != 0 and y <= 4 and z >= g.z / 2) else 0.0
				6: k = 0.85 if (front and y == 0) or (front and y <= 3 and (x == 0 or x == g.x - 1)) or (face.x != 0 and y <= 3 and z >= g.z - 3) else 0.0
				7: k = 0.3 if jaw else 0.0
			if k <= 0.0:
				continue
			c = c.lerp(hair, k * (0.8 + 0.2 * r))
		else:
			continue
		if c == p.colors[i]:
			continue
		_keep(saved, p, i)
		p.colors[i] = c
		saved[i][2] = c
		list.append(i)
	p.set_meta("look_saved", saved)
	_redraw(p, list)

## The light and shade of the muscles at a skin voxel facing `face`, as a brightness factor.
static func muscle(n: String, x: int, y: int, z: int, g: Vector3i, face: Vector3i, cx: float) -> float:
	match n:
		"torso":
			if face.z == 1:
				if y == 15 and cx >= 1.0 and cx <= 6.0:
					return 0.8    # under the pecs
				if y >= 16 and y <= 18 and cx >= 1.5 and cx <= 6.0:
					return 1.07   # the pecs
				if y >= 8 and y <= 14 and cx < 1.0:
					return 0.85   # the line down the belly
				if (y == 10 or y == 12) and cx <= 3.5:
					return 0.86   # between the abs
				if y >= 9 and y <= 13 and cx >= 4.5:
					return 0.9    # the obliques
			elif face.z == -1:
				if cx < 1.0 and y >= 7:
					return 0.84   # the spine
				if y >= 14 and y <= 18 and cx >= 2.5 and cx <= 5.5:
					return 1.06   # the shoulder blades
			elif face.x != 0 and y >= 9 and y <= 15 and y % 2 == 0:
				return 0.9        # the ribs under the arm
		"upperArmR", "upperArmL":
			var k := 1.0
			if face.z == 1 and y >= 5 and y <= 10:
				k = 1.08          # the biceps
			elif face.z == -1 and y >= 6 and y <= 11:
				k = 0.95
			return k * (0.9 if y == 12 else 1.0)
		"forearmR", "forearmL":
			if y >= 10:
				return 1.04
		"thighR", "thighL":
			if face.z == 1 and cx < 1.0 and y >= 3 and y <= 9:
				return 0.88       # between the quads
			if face.z == 1 and y <= 2:
				return 1.08       # the kneecap
		"shinR", "shinL":
			if face.z == -1 and y >= 9 and y <= 13:
				return 1.06       # the calf
			if face.z == 1 and cx < 1.0 and y >= 6:
				return 1.05       # the shinbone
		"head":
			if face.z == 1:
				if y == 8 and x >= 1 and x <= 8:
					return 0.84   # the brow's shadow
				if y == 5 and (x == 2 or x == 7):
					return 0.9    # under the cheekbones
				if x >= 4 and x <= 5 and y >= 4 and y <= 5:
					return 1.08   # the bridge of the nose
	return 1.0

# ---------- Armour over the look ----------

## Where an armour plate (in its part's unit cells) is drawn for the man's look: pulled in onto
## the outline by however many voxels the look has pared away under it. Drawing only: where it
## stops a blow (ArmorStyle, the fighter's armour points) is where it always was.
static func inset(p: VoxelPart, c: Array) -> Vector3:
	if p.veil.is_empty():
		return Vector3.ZERO
	var res := int(Data.body_res)
	var dims := [p.dims.x, p.dims.y, p.dims.z]
	var grid := [p.grid.x, p.grid.y, p.grid.z]
	var off := Vector3.ZERO
	for a in 3:
		var ca := int(c[a])
		var side := -1 if ca < 0 else (1 if ca >= int(dims[a]) else 0)
		if side == 0:
			continue
		var spans := []
		for b in 3:
			if b == a:
				spans.append([0])
				continue
			var cb := int(c[b])
			if cb < 0:
				spans.append([0])
			elif cb >= int(dims[b]):
				spans.append([int(grid[b]) - 1])
			else:
				spans.append(range(cb * res, mini(int(grid[b]), cb * res + res)))
		var depth := 1 << 20
		for u in spans[(a + 1) % 3]:
			for w in spans[(a + 2) % 3]:
				var k := 0
				while k < 4:
					var cell := [0, 0, 0]
					cell[a] = k if side < 0 else int(grid[a]) - 1 - k
					cell[(a + 1) % 3] = u
					cell[(a + 2) % 3] = w
					var j := p._cell(cell[0], cell[1], cell[2])
					if j >= 0 and p.veiled(j):
						k += 1
					else:
						break
				depth = mini(depth, k)
		if depth > 0 and depth < (1 << 20):
			off[a] = -float(side) * depth * p.vf * p.part_scale
	return off

# ---------- Shape (the strong man) ----------

## Across a part (x and z) the square drawn as a rounded square (a superellipse of this power:
## higher is squarer and crisper); over the top half of the torso and the head (x and y) the
## shoulders and the crown rounded the same way (0: not).
const SHAPE_ROUND := {"torso": [3.6, 5.0], "head": [5.0, 7.0], "upperArmR": [3.2, 0.0], "upperArmL": [3.2, 0.0]}
const SHAPE_ROUND_LIMB := 3.4

static func _smooth(a: float, b: float, t: float) -> float:
	return lerpf(a, b, smoothstep(0.0, 1.0, clampf(t, 0.0, 1.0)))

## The man's width across (x, z) at height t of a part (0 its bottom, 1 its top), as a factor:
## full at the hip, narrow at the knee, a calf, slim ankles and wrists, the fist and the foot their
## own size, a broad chest over a narrower waist, a big square head.
static func taper(n: String, t: float) -> Vector2:
	var k := 1.0
	var kz := 1.0
	match n:
		"thighR", "thighL":
			k = _smooth(0.86, 1.04, t) * 1.05
			kz = k
		"shinR", "shinL":
			if t < 0.22:
				k = 1.0
			elif t < 0.45:
				k = _smooth(0.8, 0.84, (t - 0.22) / 0.23)
			elif t < 0.75:
				k = _smooth(0.84, 1.0, (t - 0.45) / 0.3)
			else:
				k = _smooth(1.0, 0.86, (t - 0.75) / 0.25)
			kz = k
		"upperArmR", "upperArmL":
			k = _smooth(0.9, 1.08, t / 0.6) * 1.08
			kz = k
		"forearmR", "forearmL":
			if t < 0.22:
				k = 0.96
			elif t < 0.4:
				k = _smooth(0.78, 0.8, (t - 0.22) / 0.18)
			else:
				k = _smooth(0.8, 1.0, (t - 0.4) / 0.4)
			k *= 1.06
			kz = k
		"torso":
			if t < 0.3:
				k = 0.97
			elif t < 0.5:
				k = _smooth(0.97, 0.9, (t - 0.3) / 0.2)
			else:
				k = _smooth(0.92, 1.13, (t - 0.5) / 0.3)
			kz = 1.0 - (1.0 - k) * 0.5 if k < 1.0 else 1.0 + (k - 1.0) * 0.6
		"head":
			# A big square skull on the broad shoulders, the jaw as wide as the crown: a strong
			# man's head, not an egg.
			k = 1.1
			kz = 1.06
	return Vector2(k, kz)

## How far (in voxels) the end rows of a part are drawn into the part joined there: (bottom, top).
## Only while that part is on him: a severed limb and its stump end where they were cut.
static func reach(p: VoxelPart) -> Vector2:
	var n := String(p.part_name)
	var top := p.parent_part != null and not p.severed
	var bottom := false
	for c in p.child_parts:
		if is_instance_valid(c) and not c.severed and not c.missing:
			bottom = true
	match n:
		"upperArmR", "upperArmL":
			return Vector2(1.0 if bottom else 0.0, 1.6 if top else 0.0)   # the deltoid over the shoulder
		"thighR", "thighL":
			return Vector2(1.0 if bottom else 0.0, 1.0 if top else 0.0)
		"forearmR", "forearmL", "shinR", "shinL":
			return Vector2(0.0, 1.0 if top else 0.0)
		"head":
			return Vector2(1.5 if top else 0.0, 0.0)   # the neck
	return Vector2.ZERO

static func _norm(u: Vector2, e: float) -> float:
	return pow(pow(absf(u.x), e) + pow(absf(u.y), e), 1.0 / e)

## Where a point `q` of part `p` (its own frame) is drawn in the strong man, and how a cube there
## is sized: [position, scale]. `vox` the voxel's size for the ends drawn into the next part (0
## for an armour plate, which is only moved with the flesh under it).
static func shape_at(p: VoxelPart, q: Vector3, vox: float) -> Array:
	var n := String(p.part_name)
	var h := Vector3(p.grid) * p.vf * p.part_scale * 0.5
	var e: Array = SHAPE_ROUND.get(n, [SHAPE_ROUND_LIMB, 0.0])
	var s := Vector3.ONE
	var at := q
	var u := Vector2(q.x / h.x, q.z / h.z)
	var sq := maxf(absf(u.x), absf(u.y))
	if sq > 0.0001:
		var f := sq / _norm(u, e[0])
		at.x *= f
		at.z *= f
		s.x *= f
		s.z *= f
	if e[1] > 0.0 and q.y > 0.0:
		var v := Vector2(q.x / h.x, q.y / h.y)
		var sq2 := maxf(absf(v.x), absf(v.y))
		if sq2 > 0.0001:
			var f2 := sq2 / _norm(v, e[1])
			at.x *= f2
			at.y = q.y * f2
			s.x *= f2
	if n == "head":
		at.y = q.y * 1.06
		s.y *= 1.06
	var k := taper(n, clampf((q.y / h.y + 1.0) * 0.5, 0.0, 1.0))
	at.x *= k.x
	at.z *= k.y
	s.x *= k.x
	s.z *= k.y
	if vox > 0.0:
		var r := reach(p)
		var edge := h.y - vox
		if r.y > 0.0 and q.y > edge - 0.01 * vox:
			at.y += r.y * vox * 0.5
			s.y *= 1.0 + r.y
		elif r.x > 0.0 and q.y < -edge + 0.01 * vox:
			at.y -= r.x * vox * 0.5
			s.y *= 1.0 + r.x
	return [at, s]

## Each voxel of `p` as the strong man draws it (VoxelPart.set_shape). A cube a little larger
## than its place, so the moved voxels close over one another with no seam.
## Every man of a size is drawn the same: the shape of a whole part is worked out once and kept
## (by part, size and whether a helmet presses his hair flat); a part with a limb off at one of
## its ends, or voxels of its own, is worked out for itself.
static var _shapes := {}
static func shape_of(p: VoxelPart) -> Array:
	var vox := p.vf * p.part_scale
	var head := String(p.part_name) == "head"
	for ad in p.get_meta("armor", []):
		if not Fighter._cosmetic(String(ad.id)):
			head = false   # (under a helmet his hair lies flat inside it)
	var whole := reach(p) == _reach_whole(String(p.part_name))
	var key := "%s|%.5f|%d|%d" % [p.part_name, vox, p.fx.size(), int(head)]
	if whole and _shapes.has(key):
		return (_shapes[key] as Array).duplicate()
	var out := []
	out.resize(p.fx.size())
	for i in p.fx.size():
		out[i] = _voxel_xf(p, i, vox, head)
	if whole:
		_shapes[key] = out.duplicate()
	return out

static func _voxel_xf(p: VoxelPart, i: int, vox: float, head: bool) -> Transform3D:
	var r := shape_at(p, p.local_of(i), vox)
	var sc: Vector3 = r[1] * 1.06
	var at: Vector3 = r[0]
	if head and p.kinds[i] == 2 and p.fy[i] >= p.grid.y - 2:
		# His own hair over the crown drawn standing off the skull: it has a volume of its own.
		var out_dir := (at - Vector3(0, -p.grid.y * vox * 0.25, 0)).normalized()
		at += out_dir * vox * 0.45
		sc *= 1.15
	return Transform3D(Basis.from_scale(sc), at)

## The reach of a part with every limb on him (shape_of's kept shapes are for that man).
static func _reach_whole(n: String) -> Vector2:
	match n:
		"upperArmR", "upperArmL":
			return Vector2(1.0, 1.6)
		"thighR", "thighL":
			return Vector2(1.0, 1.0)
		"forearmR", "forearmL", "shinR", "shinL":
			return Vector2(0.0, 1.0)
		"head":
			return Vector2(1.5, 0.0)
	return Vector2.ZERO

## How an armour plate whose place on `p` is `at` is drawn: on the strong man moved with the
## flesh under it, else where it always was (with the classic looks' inset). Drawing only: where
## it stops a blow does not move.
## A hairstyle or a beard is drawn fuller than a plate: standing off the head and each lock larger,
## so every style gives the head its own outline (a crest, a mane, curls, a knot).
static func plate_xf(p: VoxelPart, c: Array, at: Vector3, id := "") -> Transform3D:
	if p.shape_xf.is_empty():
		return Transform3D(Basis(), at + inset(p, c))
	var r := shape_at(p, at, 0.0)
	var pos: Vector3 = r[0]
	var sc: Vector3 = r[1] * 1.04
	if id.begins_with("hair_"):
		var cell := p.vf * p.part_scale * float(Data.body_res)
		var centre := Vector3(0, -p.grid.y * p.vf * p.part_scale * 0.2, 0)
		pos += (pos - centre).normalized() * cell * 0.22
		sc *= 1.12
	elif id.begins_with("beard_"):
		if int(c[1]) >= 0:
			return Transform3D(Basis().scaled(Vector3.ZERO), Vector3.ZERO)   # (painted on the jaw)
		sc *= Vector3(0.8, 1.0, 0.8)   # what hangs below the chin, a braid or a long beard
	return Transform3D(Basis.from_scale(sc), pos)

## A tuft of hair burst out of a hole knocked in his helmet: drawn pushed out past the helmet
## and fluffed up big (drawing only).
static func fluff_xf(p: VoxelPart, xf: Transform3D) -> Transform3D:
	var cell := p.vf * p.part_scale * float(Data.body_res)
	var centre := Vector3(0, -p.grid.y * p.vf * p.part_scale * 0.2, 0)
	xf.origin += (xf.origin - centre).normalized() * cell * 0.6
	xf.basis = xf.basis.scaled(Vector3.ONE * 1.35)
	return xf

## The strong man's ends drawn again after a limb is cut off (the stump and the piece end where
## they were cut, not reaching into what is gone).
## Only the end rows of the cut part, the part it hung from and those that hung from it change.
static func reshape(f, part = null) -> void:
	var near: Array = f.parts if part == null else ([part, part.parent_part] + part.child_parts)
	for p in near:
		if p == null or not is_instance_valid(p) or p.shape_xf.is_empty():
			continue
		var vox: float = p.vf * p.part_scale
		var head := String(p.part_name) == "head"
		for ad in p.get_meta("armor", []):
			if not Fighter._cosmetic(String(ad.id)):
				head = false
		var rows := []
		for i in p.fx.size():
			if p.fy[i] == 0 or p.fy[i] == p.grid.y - 1:
				p.shape_xf[i] = _voxel_xf(p, i, vox, head)
				rows.append(i)
		p.set_shape(p.shape_xf, rows)

# ---------- The face: eyes and mouth ----------

## The eyes and the mouth a gladiator can have (Your gladiator), painted on the front of his own
## head in every look: only colours, nothing of him changes. The head's face (10 wide, the eyes
## two voxels each at x 2-3 and 6-7, white over the pupil at y 7 and 6, brows at y 9, teeth at y 3
## over the lips at y 2).
const FACES := {
	"eyes_wide": "Wide eyes", "eyes_side": "Side-eye", "eyes_cross": "Cross-eyed", "eyes_angry": "Angry brows",
	"eyes_sleepy": "Sleepy", "eyes_blue": "Blue eyes", "eyes_green": "Green eyes", "eyes_mad": "Mad stare",
	"eyes_wink": "Wink", "eyes_brown": "Brown eyes", "eyes_scar": "Scarred eye", "eyes_tired": "Tired",
	"mouth_gap": "Missing tooth", "mouth_grin": "Full grin", "mouth_snarl": "Snarl", "mouth_stern": "Stern",
	"mouth_shout": "War cry", "mouth_tongue": "Tongue out", "mouth_toothless": "One tooth left", "mouth_smirk": "Smirk",
	"mouth_buck": "Buck teeth", "mouth_frown": "Frown", "mouth_gold": "Gold tooth", "mouth_grimace": "Grimace",
}
const WHITE := Color(0.93, 0.91, 0.84)
const DARK := Color(0.07, 0.05, 0.05)
const MOUTH := Color(0.16, 0.05, 0.05)
const LIP := Color(0.55, 0.27, 0.24)
const TONGUE := Color(0.86, 0.36, 0.42)
const BLUE := Color(0.22, 0.42, 0.72)
const GREEN := Color(0.25, 0.52, 0.3)
const BROWN := Color(0.38, 0.22, 0.1)
const GOLDEN := Color(0.95, 0.75, 0.25)

## What each face piece paints: [x, y, colour] (colour "skin", "lid", "brow" for his own tones).
static func face_marks(id: String) -> Array:
	var eyes := [2, 3, 6, 7]
	match id:
		"eyes_wide":
			return eyes.map(func(x): return [x, 7, WHITE]) + [[2, 6, WHITE], [3, 6, DARK], [6, 6, DARK], [7, 6, WHITE]]
		"eyes_side":
			return eyes.map(func(x): return [x, 7, WHITE]) + [[2, 6, DARK], [3, 6, WHITE], [6, 6, DARK], [7, 6, WHITE]]
		"eyes_cross":
			return eyes.map(func(x): return [x, 7, WHITE]) + [[2, 6, WHITE], [3, 6, DARK], [6, 6, DARK], [7, 6, WHITE]] + [[3, 7, DARK], [6, 7, DARK]]
		"eyes_angry":
			return [[2, 9, "brow"], [3, 8, "brow"], [6, 8, "brow"], [7, 9, "brow"], [3, 9, "skin"], [6, 9, "skin"]] + eyes.map(func(x): return [x, 7, "lid"])
		"eyes_sleepy":
			return eyes.map(func(x): return [x, 7, "lid"]) + eyes.map(func(x): return [x, 8, "lid"])
		"eyes_blue":
			return [[3, 6, BLUE], [6, 6, BLUE]]
		"eyes_green":
			return [[3, 6, GREEN], [6, 6, GREEN]]
		"eyes_mad":
			# One eye wide open, the other screwed up: a mad stare.
			return [[2, 7, WHITE], [3, 7, WHITE], [2, 6, WHITE], [3, 6, DARK], [2, 8, WHITE], [3, 8, WHITE], [6, 7, "lid"], [7, 7, "lid"], [6, 9, "skin"], [7, 9, "brow"]]
		"eyes_wink":
			return [[6, 7, "lid"], [7, 7, "lid"], [6, 6, "lid"], [7, 6, "lid"], [6, 8, "brow"], [7, 8, "brow"]]
		"eyes_brown":
			return [[3, 6, BROWN], [6, 6, BROWN]]
		"eyes_scar":
			return [[2, 9, VoxelPart.SCAR], [2, 8, VoxelPart.SCAR], [2, 7, VoxelPart.SCAR], [2, 6, VoxelPart.SCAR], [2, 5, VoxelPart.SCAR], [3, 6, WHITE]]
		"eyes_tired":
			return [[2, 5, "lid"], [3, 5, "lid"], [6, 5, "lid"], [7, 5, "lid"]]
		"mouth_buck":
			return [[4, 3, WHITE], [5, 3, WHITE], [4, 2, WHITE], [5, 2, WHITE], [3, 3, LIP], [6, 3, LIP]]
		"mouth_frown":
			return _row(3, 6, 3, "skin") + _row(3, 6, 2, DARK) + [[2, 1, DARK], [7, 1, DARK], [2, 2, "skin"], [7, 2, "skin"]]
		"mouth_gold":
			return [[5, 3, GOLDEN]]
		"mouth_grimace":
			return _row(2, 7, 3, WHITE) + _row(2, 7, 2, WHITE) + [[3, 3, MOUTH], [5, 3, MOUTH], [7, 3, MOUTH], [2, 2, MOUTH], [4, 2, MOUTH], [6, 2, MOUTH]]
		"mouth_gap":
			return [[4, 3, MOUTH], [6, 3, MOUTH]]
		"mouth_grin":
			return _row(1, 8, 3, WHITE) + _row(2, 7, 2, WHITE) + [[1, 2, LIP], [8, 2, LIP], [1, 4, LIP], [8, 4, LIP]] + _row(3, 6, 1, LIP)
		"mouth_snarl":
			return _row(2, 7, 3, WHITE) + [[3, 3, MOUTH], [5, 3, MOUTH], [7, 3, MOUTH]] + [[1, 2, LIP], [8, 2, LIP], [2, 4, "brow"], [7, 4, "brow"]] + _row(2, 7, 2, MOUTH)
		"mouth_stern":
			return _row(2, 7, 3, "skin") + _row(3, 6, 2, DARK) + [[2, 2, "skin"], [7, 2, "skin"]]
		"mouth_shout":
			return _row(3, 6, 3, MOUTH) + _row(3, 6, 2, MOUTH) + _row(3, 6, 1, MOUTH) + [[4, 1, TONGUE], [5, 1, TONGUE], [3, 3, WHITE], [6, 3, WHITE]] + [[2, 3, LIP], [7, 3, LIP], [2, 1, LIP], [7, 1, LIP], [2, 2, LIP], [7, 2, LIP]]
		"mouth_tongue":
			return [[4, 2, TONGUE], [5, 2, TONGUE], [4, 1, TONGUE], [5, 1, TONGUE], [5, 0, TONGUE]]
		"mouth_toothless":
			return _row(2, 7, 3, MOUTH) + [[5, 3, WHITE]]
		"mouth_smirk":
			return _row(2, 4, 3, "skin") + _row(5, 7, 3, WHITE) + [[7, 4, LIP], [2, 2, "skin"], [3, 2, "skin"]]
	return []

static func _row(x0: int, x1: int, y: int, c) -> Array:
	var out := []
	for x in range(x0, x1 + 1):
		out.append([x, y, c])
	return out

## His face painted with the pieces he chose (f.face_ids), or for a bot one of each at random.
static func _faces(f) -> void:
	if not (f is Fighter) or f is Beast or String(f.mods.get("look", "")) != "":
		return
	var head: VoxelPart = f.head
	if head == null or head.missing:
		return
	var ids: Array = f.face_ids.duplicate()
	if f.is_bot and ids.is_empty():
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(str(f.display_name)) ^ int(f.slot) * 104729
		var eyes := FACES.keys().filter(func(k): return k.begins_with("eyes_"))
		var mouths := FACES.keys().filter(func(k): return k.begins_with("mouth_"))
		if rng.randf() < 0.45:
			ids.append(eyes[rng.randi() % eyes.size()])
		if rng.randf() < 0.55:
			ids.append(mouths[rng.randi() % mouths.size()])
	if ids.is_empty():
		return
	var g := head.grid
	var front := g.z - 1
	var at := {}
	var skin_c := Color(0.6, 0.4, 0.3)
	var brow := DARK
	for i in head.fx.size():
		if head.fz[i] != front:
			continue
		at[Vector2i(head.fx[i], head.fy[i])] = i
	if at.has(Vector2i(0, 5)):
		skin_c = head.colors[at[Vector2i(0, 5)]]
	if at.has(Vector2i(2, 9)):
		brow = head.colors[at[Vector2i(2, 9)]]
	var saved: Dictionary = head.get_meta("look_saved", {})
	var list := []
	for id in ids:
		for mk in face_marks(id):
			var k := Vector2i(int(mk[0]), int(mk[1]))
			if not at.has(k):
				continue
			var i: int = at[k]
			if head.alive[i] == 0:
				continue
			var c = mk[2]
			if c is String:
				c = skin_c if c == "skin" else (skin_c.darkened(0.25) if c == "lid" else brow)
			_keep(saved, head, i)
			head.colors[i] = c
			saved[i][2] = c
			list.append(i)
	head.set_meta("look_saved", saved)
	_redraw(head, list)
