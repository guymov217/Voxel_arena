class_name Physique
extends RefCounted
## A gladiator's look (Options, Graphics): five ways of drawing the same man besides the classic
## blocks. Drawing only. Every voxel, organ, bone, joint, collider, mass and hp is the classic
## man's: a style changes what is drawn and how, never what is there.
##
## Three things a style may do, all through VoxelPart's drawing:
## - veil: pare a shell of voxels from the outline (a neck, sloped shoulders, a waist, rounded
##   limbs). A veiled voxel is still there for every blow, cut and count; it is only not drawn.
##   Only ever over plain flesh: never an organ or a bone, nor anything that would uncover one,
##   so whatever a wound opens is what it opens on the classic man. The flesh bared under the
##   shell is drawn in the colour of the skin pared off it.
## - bevel: the body's outer edges drawn chamfered (the shader pulls in the corners where open
##   faces meet; nothing inside is uncovered).
## - paint: light and shade on the skin (muscles, wear), and an oiled sheen. Colours only.
## A man's own choices (skin, hair, beard, armour) are worn over any of them. Each player picks
## for himself; nothing of it goes over the network.

const STYLES := ["classic", "sculpted", "heroic", "anatomy", "worn", "oiled"]
const NAMES := {
	"classic": "Classic blocks",
	"sculpted": "Sculpted",
	"heroic": "Heroic",
	"anatomy": "Anatomy",
	"worn": "Arena-worn",
	"oiled": "Oiled champion",
}
const BLURB := {
	"classic": "The gladiators as they were: square blocks.",
	"sculpted": "A neck, sloped shoulders, rounded limbs, bevelled edges.",
	"heroic": "Sculpted, with a narrow waist under a broad chest.",
	"anatomy": "Sculpted, the muscles drawn in light and shade.",
	"worn": "Anatomy, with arena sand on the legs, old scars and linen-wrapped fists.",
	"oiled": "Heroic and muscled, the skin oiled to shine under the sun.",
}
const DIRS := [Vector3i(0, 0, 1), Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, -1), Vector3i(0, 1, 0), Vector3i(0, -1, 0)]

static var forced := ""   # set by tests; else the player's setting

static func current() -> String:
	if forced != "":
		return forced
	var s := str(Save.get_value("settings", {}).get("physique", "classic"))
	return s if STYLES.has(s) else "classic"

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
		p.set_look(_veil(p, style), true)
		_bare(p)
		if style == "anatomy" or style == "worn" or style == "oiled":
			_paint(p, style)
		_material(p, style)
		p.resync_later()
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
