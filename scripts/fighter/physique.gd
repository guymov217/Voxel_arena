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

const STYLES := ["human", "strong", "classic", "sculpted", "heroic", "anatomy", "worn", "oiled"]
## The looks a player picks between (Options, Graphics): the new one, and the gladiators as they were.
const OFFERED := ["human", "strong"]
const NAMES := {
	"human": "Detailed gladiators",
	"strong": "Strong gladiator",
	"classic": "Classic blocks",
	"sculpted": "Sculpted",
	"heroic": "Heroic",
	"anatomy": "Anatomy",
	"worn": "Arena-worn",
	"oiled": "Oiled champion",
}
const BLURB := {
	"human": "Men as they are built, in voxels half the size: muscles, hands, feet, and wounds that open on skin, fat, flesh and bone.",
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
static var fine_heads := true   # (probes: off, to see the heads as their voxels are)

## The look the player picked (Options, Graphics: the detailed men, or the strong gladiators as
## they were); the other styles are kept for the tests and the look studies (`forced`).
static func current() -> String:
	if forced != "":
		return forced
	var st = Save.get_value("settings", {})
	# (Low graphics, for the weakest cards: the classic blocks, half the new look's triangles,
	# unless he picked a look himself in Options.)
	if st is Dictionary and not st.has("physique") and str(st.get("quality", "high")) == "low":
		return "strong"
	var s := str(st.get("physique", "human")) if st is Dictionary else "human"
	return s if OFFERED.has(s) else "human"

## The build a man is drawn in by the new look (FineBody): his own choice (a player's, Your
## gladiator), else by what he is: a heavy weapon or a hard man the brute, a boss or a champion the
## hero, the rest mostly lean champions. The same on every screen (his name and place).
const HEAVY := ["warhammer", "zweihander", "executionerAxe", "plank", "ram", "meteorHammer", "hammer", "twoPersonSword", "imperialFlail"]
static func build_of(f) -> String:
	if giant_of(f) != "":
		return giant_of(f)
	var want := str(f.get("build_pref")) if f.get("build_pref") != null else ""
	if FineBody.BUILDS.has(want):
		return want
	if not f.get("is_bot"):
		return "hero"
	if HEAVY.has(str(f.get("main_id"))) or float(f.mods.get("toughness", 1.0)) >= 1.3 or float(f.mods.get("bodyScale", 1.0)) > 1.25:
		return "brute"
	if f.get("boss") or str(f.display_name).begins_with(Loc.t("Champion %s") % ""):
		return "hero"
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(f.display_name)) ^ int(f.slot) * 3571
	return "hero" if rng.randf() < 0.25 else "champion"

## Men only, in their own skins: beasts, and giants with their own heads, keep theirs; in the new
## look the giants too, each a body and a head of his own (FineBody, FineHead).
static func applies(f, style := "") -> bool:
	if not (f is Fighter) or f is Beast:
		return false
	if String(f.mods.get("look", "")) == "":
		return true
	return (style if style != "" else current()) == "human" and giant_of(f) != ""

## A giant's build and head in the new look ("" a man): the Cyclops, Polyphemus (the giant with
## the Cyclops' one eye), the Minotaur, a troll, the Titan.
const GIANTS := ["cyclops", "polyphemus", "minotaur", "troll", "titan"]
static func giant_of(f) -> String:
	var look := String(f.mods.get("look", "")) if f is Fighter else ""
	if look == "cyclops" and String(f.mods.get("voice", "")) == "giant":
		look = "polyphemus"
	return look if GIANTS.has(look) else ""

## Draws `f` in `style` (the setting when empty), from whatever look he had: at spawn, or any
## time after, wounded or not; nothing of his state changes.
static func dress(f, style := "") -> void:
	if style == "":
		style = current()
	if not applies(f, style):
		# (A giant out of the new look: his own voxels again, as he always was drawn.)
		if f is Fighter and not (f is Beast):
			for p in f.parts:
				FineHead.clear(p)
				FineBody.clear(p)
				if p.shape_xf.size() > 0:
					p.set_shape([])
			f.set_meta("physique", style)
			if f.has_method("place_armor"):
				f.place_armor()
		return
	var bn := build_of(f) if style == "human" else ""
	for p in f.parts:
		FineHead.clear(p)
		FineBody.clear(p)
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
				var hc = hair_choice(f)
				if hc != null:
					_paint_face(p, hc, false, 0, true)
				var worn := beard_worn(p)
				if worn != "":
					_paint_face(p, hc if hc != null else ArmorStyle.base_color(worn, {}, f.skin), false, BEARD_PAINT.get(worn, 2), false)
			_material(p, "classic")   # the game's own voxels: crisp, no chamfer
			p.set_shape(shape_of(p))
			continue
		if style == "human":
			# His head is the fine one (below), painted first as the strong man's is; the rest of
			# him the fine body of his build.
			p.set_look(PackedByteArray(), false)
			_material(p, "classic")
			if p == f.get("head"):
				if giant_of(f) != "":
					continue   # (his own head: FineHead below)
				_paint(p, "strong")
				if f.get("is_bot"):
					_face(p, hash(str(f.display_name)) ^ int(f.slot) * 7919)
				var hc_h = hair_choice(f)
				if hc_h != null:
					_paint_face(p, hc_h, false, 0, true)
				var worn_h := beard_worn(p)
				if worn_h != "":
					_paint_face(p, hc_h if hc_h != null else ArmorStyle.base_color(worn_h, {}, f.skin), false, BEARD_PAINT.get(worn_h, 2), false)
			else:
				FineBody.build(f, p, bn)
			continue
		p.set_look(_veil(p, style), true)
		_bare(p)
		if style == "anatomy" or style == "worn" or style == "oiled":
			_paint(p, style)
		_material(p, style)
		p.resync_later()
	_faces(f)
	# The new look's head is the fine one: a man's face, not a box (FineHead), sized to his build.
	# (The strong gladiators keep their own heads: the old men whole, the way they were.)
	if style == "human" and f.get("head") != null and fine_heads:
		FineHead.build(f, f.head, true, FineBody.head_scale(bn), giant_of(f))
	f.set_meta("physique", style)
	f.set_meta("build", bn)
	if f.has_method("place_armor"):
		f.place_armor()

## Every man in the tree under `root` drawn in the setting's look again (Options).
static func restyle_all(root: Node) -> void:
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Beast:
			FineBody.dress_beast(n, current() == "human")
			continue
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
	# The new look: on his outline there (FineBody.plate_at); on the fine head, round it (a helmet
	# sits on the head, its rim over the brow and the ears, not on top like a bowl).
	if p.fine.has("body"):
		return FineBody.plate_at(p, at)
	if p.fine.has("wtab"):
		return _plate_head(p, c, at, id)
	if p.shape_xf.is_empty():
		return Transform3D(Basis(), at + inset(p, c))
	return _plate_strong(p, c, at, id)

static func _plate_head(p: VoxelPart, c: Array, at: Vector3, id: String) -> Transform3D:
	# A giant's fine head has its horns, its tusks, its crown and its beard of its own.
	if String(p.fine.get("giant", "")) != "" and (id.begins_with("mon_") or id == "hat_crown" or id.begins_with("beard_")):
		return Transform3D(Basis().scaled(Vector3.ZERO), Vector3.ZERO)
	if id.begins_with("beard_") and int(c[1]) >= 0:
		return Transform3D(Basis().scaled(Vector3.ZERO), Vector3.ZERO)   # (drawn on the fine jaw)
	var lies := FineArmor.hair_or_hat(p, id) and not stands(p, c, id)
	var r := FineHead.wrap(p, at)
	var pos: Vector3 = r[0]
	var cell := p.vf * p.part_scale * float(Data.body_res)
	var wc: Vector3 = p.fine.wc
	var dir := (pos - wc).normalized()
	if FineArmor.hair_or_hat(p, id) and not lies:
		# A lock or a piece standing out of the shell (a topknot, a ponytail, a horn, a plume): a
		# voxel of his body's size on the shell, as far out past it as it stood out past the first
		# voxel round the box (where it stood off the box it floated over the smaller fine head).
		# (A piece standing out all of it, horns or a crest, sits a little into the head where it
		# grows from; a lock over the shell rests on the shell.)
		var fsz := p.vf * p.part_scale / float(FineHead.template().get("res", 3))
		var lay := _lay(p, c)
		var out_r := FineHead.outline(p, dir) + (float(maxi(lay, 1)) - 0.62) * cell if STANDING.has(id) else FineHead.outline(p, dir) + FineArmor.THICK * fsz + (float(lay) - 1.5) * cell
		match id:
			"hat_horns":
				# A horn: long out of the head along its way, narrowing to its point (FineArmor).
				var hup := Vector3.UP if absf(dir.y) < 0.95 else Vector3.FORWARD
				return Transform3D(Basis.looking_at(-dir, hup) * Basis.from_scale(Vector3(0.62, 0.62, 1.7)), wc + dir * (out_r + cell * 0.3))
			"hat_feather":
				# A feather: tall and thin, standing up out of the band.
				return Transform3D(Basis.from_scale(Vector3(0.3, 1.9, 0.75)), wc + dir * out_r + Vector3.UP * cell * 0.45)
		return Transform3D(Basis.from_scale(Vector3.ONE * 0.98), wc + dir * out_r)
	if not lies and (id.begins_with("hair_") or id.begins_with("beard_") or id.begins_with("hat_") or id == "cape"):
		# Hair, a beard, a hat: as full as they are, a lock standing off the head.
		var sc := Vector3.ONE * float(r[1]) * 1.04
		if id.begins_with("hair_"):
			pos += dir * cell * 0.22
			sc *= 1.12
		elif id.begins_with("beard_"):
			sc *= Vector3(0.8, 1.0, 0.8)
		return Transform3D(Basis.from_scale(sc), pos)
	# A helmet's plates: tiles turned to lie on the skull, a helmet's thickness, their inner face
	# on the head (a cube a plate drew a bowl over his head).
	var t := FineBody.PLATE_THICK
	var hp := wc + dir * (FineHead.outline(p, dir) + cell * t * 0.5 + maxf(0.0, (pos - wc).length() - FineHead.outline(p, dir) - cell * 0.5))
	var up := Vector3.UP if absf(dir.y) < 0.95 else Vector3.FORWARD
	var b := Basis.looking_at(-dir, up)
	var tang := clampf(float(r[1]) * 1.15, 0.7, 1.2)
	return Transform3D(b * Basis.from_scale(Vector3(tang, tang, t)), hp)

## Whether a cell of a hairstyle or a hat on the fine head stands out of the shell round the head
## (drawn as the fine voxels it holds) rather than lying in it: what stands two voxels off the
## head's box (a topknot, a ponytail); every cell of horns, a crest, a feather, a mohawk, spikes
## (laid in the shell they were patches on the head); a straw hat's brim, its lowest row.
const STANDING := ["hat_horns", "hat_crest", "hat_feather", "hair_mohawk", "hair_spikes"]
static func stands(p: VoxelPart, c: Array, id: String) -> bool:
	if STANDING.has(id):
		return true
	if id == "hat_straw" and int(c[1]) <= 4:
		return true
	return _lay(p, c) >= 2

## How many voxels out of the part's box a piece's cell stands (0: within it).
static func _lay(p: VoxelPart, c: Array) -> int:
	var lay := 0
	for ax in 3:
		var v := int(c[ax])
		var dm: int = p.dims[ax]
		lay = maxi(lay, -v if v < 0 else (v - dm + 1 if v >= dm else 0))
	return lay

static func _plate_strong(p: VoxelPart, c: Array, at: Vector3, id: String) -> Transform3D:
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
	if f.get_meta("physique", "") == "human":
		return   # (the new look's ends close of themselves: FineBody)
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
	"face_freckles": "Freckles", "face_stubble": "Stubble", "face_scar_cheek": "Scarred cheek", "face_scar_lip": "Split lip",
	"face_scar_brow": "Scar through the brow", "face_brows_thick": "Heavy brows", "face_unibrow": "One brow",
	"face_woad": "Blue woad", "face_warpaint": "War stripes", "face_ochre": "Red ochre band", "face_tattoo": "Tattooed cheek",
	"face_blush": "Rosy cheeks", "face_skull": "Skull paint", "face_clown": "Clown paint",
	"hc_black": "Black", "hc_dark": "Dark brown", "hc_brown": "Brown", "hc_auburn": "Auburn", "hc_ginger": "Ginger",
	"hc_blond": "Blond", "hc_platinum": "Platinum", "hc_grey": "Grey", "hc_white": "White",
	"hc_blue": "Dyed blue", "hc_green": "Dyed green", "hc_pink": "Dyed pink", "hc_purple": "Dyed purple",
	"iris_brown": "Brown", "iris_hazel": "Hazel", "iris_green": "Green", "iris_blue": "Blue", "iris_grey": "Grey",
	"iris_amber": "Amber", "iris_red": "Demon red", "iris_violet": "Violet", "iris_gold": "Gold", "iris_white": "Ghost white",
}
## His hair and beard the colour he chose (Your gladiator: "hc_"), and his eyes ("iris_").
const HAIR_DYES := {
	"hc_black": Color(0.06, 0.05, 0.05), "hc_dark": Color(0.17, 0.1, 0.06), "hc_brown": Color(0.33, 0.2, 0.1),
	"hc_auburn": Color(0.43, 0.17, 0.08), "hc_ginger": Color(0.72, 0.32, 0.1), "hc_blond": Color(0.86, 0.7, 0.38),
	"hc_platinum": Color(0.93, 0.89, 0.76), "hc_grey": Color(0.5, 0.49, 0.47), "hc_white": Color(0.9, 0.9, 0.88),
	"hc_blue": Color(0.12, 0.3, 0.75), "hc_green": Color(0.15, 0.55, 0.22), "hc_pink": Color(0.93, 0.4, 0.62), "hc_purple": Color(0.45, 0.18, 0.62),
}
const IRISES := {
	"iris_brown": Color(0.38, 0.22, 0.1), "iris_hazel": Color(0.5, 0.38, 0.16), "iris_green": Color(0.25, 0.52, 0.3),
	"iris_blue": Color(0.22, 0.42, 0.72), "iris_grey": Color(0.52, 0.56, 0.6), "iris_amber": Color(0.8, 0.52, 0.12),
	"iris_red": Color(0.85, 0.08, 0.06), "iris_violet": Color(0.5, 0.25, 0.75), "iris_gold": Color(0.95, 0.75, 0.2), "iris_white": Color(0.9, 0.92, 0.95),
}
const FRECKLE := Color(0.62, 0.36, 0.22)
const WOAD := Color(0.17, 0.29, 0.62)
const OCHRE := Color(0.6, 0.18, 0.09)
const TATTOO := Color(0.1, 0.2, 0.3)
const BONE_PAINT := Color(0.9, 0.88, 0.82)
const CLOWN_WHITE := Color(0.96, 0.95, 0.92)
const CLOWN_RED := Color(0.86, 0.1, 0.1)
const PINK := Color(0.93, 0.45, 0.5)

## The colour of hair he chose (a "hc_" piece), or null: his own, by his skin.
static func hair_choice(f) -> Variant:
	if not (f is Fighter):
		return null
	for id in f.face_ids:
		if HAIR_DYES.has(String(id)):
			return HAIR_DYES[String(id)]
	return null

## The colour of eyes he chose (an "iris_" piece), or null.
static func iris_choice(ids: Array) -> Variant:
	for id in ids:
		if IRISES.has(String(id)):
			return IRISES[String(id)]
	return null
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
		"bot_stubble":
			# The jaw and the chin a shade darker, round the mouth.
			return _row(1, 8, 0, "lid") + _row(1, 8, 1, "lid") + [[1, 2, "lid"], [8, 2, "lid"], [1, 3, "lid"], [8, 3, "lid"]]
		"bot_scar_cheek":
			return [[7, 5, VoxelPart.SCAR], [8, 4, VoxelPart.SCAR], [8, 3, VoxelPart.SCAR], [9, 2, VoxelPart.SCAR]]
		"bot_scar_lip":
			return [[3, 4, VoxelPart.SCAR], [3, 3, VoxelPart.SCAR], [3, 2, VoxelPart.SCAR], [3, 1, VoxelPart.SCAR]]
		"bot_brows_thick":
			return [[1, 9, "brow"], [2, 9, "brow"], [3, 9, "brow"], [6, 9, "brow"], [7, 9, "brow"], [8, 9, "brow"], [2, 8, "brow"], [7, 8, "brow"]]
		"bot_unibrow":
			return _row(2, 7, 9, "brow")
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
		# (Face paint never on (0, 5): the cheek the look reads his skin's colour off.)
		"face_freckles":
			return [[1, 4, FRECKLE], [2, 5, FRECKLE], [3, 4, FRECKLE], [4, 5, FRECKLE], [5, 4, FRECKLE], [6, 5, FRECKLE], [7, 4, FRECKLE], [8, 5, FRECKLE]]
		"face_stubble":
			return face_marks("bot_stubble")
		"face_scar_cheek":
			return face_marks("bot_scar_cheek")
		"face_scar_lip":
			return face_marks("bot_scar_lip")
		"face_brows_thick":
			return face_marks("bot_brows_thick")
		"face_unibrow":
			return face_marks("bot_unibrow")
		"face_scar_brow":
			return [[6, 10, VoxelPart.SCAR], [6, 9, VoxelPart.SCAR], [7, 8, VoxelPart.SCAR], [7, 5, VoxelPart.SCAR], [8, 4, VoxelPart.SCAR]]
		"face_woad":
			return _row(1, 8, 8, WOAD) + _row(1, 8, 5, WOAD) + [[1, 6, WOAD], [1, 7, WOAD], [4, 6, WOAD], [4, 7, WOAD], [5, 6, WOAD], [5, 7, WOAD], [8, 6, WOAD], [8, 7, WOAD]]
		"face_warpaint":
			return [[1, 5, DARK], [1, 4, DARK], [3, 5, DARK], [3, 4, DARK], [6, 5, DARK], [6, 4, DARK], [8, 5, DARK], [8, 4, DARK], [1, 3, DARK], [8, 3, DARK]]
		"face_ochre":
			return _row(0, 9, 8, OCHRE) + [[0, 6, OCHRE], [0, 7, OCHRE], [1, 6, OCHRE], [1, 7, OCHRE], [4, 6, OCHRE], [4, 7, OCHRE], [5, 6, OCHRE], [5, 7, OCHRE], [8, 6, OCHRE], [8, 7, OCHRE], [9, 6, OCHRE], [9, 7, OCHRE]]
		"face_tattoo":
			return [[8, 9, TATTOO], [9, 8, TATTOO], [8, 7, TATTOO], [9, 6, TATTOO], [8, 5, TATTOO], [9, 4, TATTOO], [8, 3, TATTOO]]
		"face_blush":
			return [[1, 4, PINK], [2, 4, PINK], [7, 4, PINK], [8, 4, PINK]]
		"face_skull":
			var sk := []
			for y in range(1, 10):
				for x in range(1, 9):
					sk.append([x, y, BONE_PAINT])
			for e in [[2, 6], [3, 6], [2, 7], [3, 7], [6, 6], [7, 6], [6, 7], [7, 7], [4, 4], [5, 4], [2, 2], [4, 2], [6, 2]]:
				sk.append([e[0], e[1], DARK])
			return sk
		"face_clown":
			var cl := []
			for y in range(1, 10):
				for x in range(1, 9):
					if (x == 2 or x == 3 or x == 6 or x == 7) and (y == 6 or y == 7):
						continue   # (his eyes stay his own)
					cl.append([x, y, CLOWN_WHITE])
			for e in [[4, 4], [5, 4], [4, 5], [5, 5]]:
				cl.append([e[0], e[1], CLOWN_RED])
			cl += _row(2, 7, 2, CLOWN_RED) + [[1, 3, CLOWN_RED], [8, 3, CLOWN_RED], [1, 4, PINK], [8, 4, PINK], [2, 8, BLUE], [7, 8, BLUE]]
			return cl
	if IRISES.has(id):
		return [[3, 6, IRISES[id]], [6, 6, IRISES[id]]]
	return []

# ---------- The mouth while he talks (the proximity voice) ----------

## His mouth opened by how loud he speaks (1 a crack, 2 open, 3 wide: teeth and tongue showing),
## painted over the front of his head like his face, and put back as it was when he stops (what a
## blow or blood changed on it meanwhile stays). A dead man's mouth stays shut.
static func talk(f, state: int) -> void:
	if not (f is Fighter) or f is Beast or not is_instance_valid(f):
		return
	var head: VoxelPart = f.head
	if head == null or not is_instance_valid(head) or head.missing:
		return
	if not f.alive:
		state = 0
	if state == int(head.get_meta("talk_state", 0)):
		return
	# (A grimace's teeth over the mouth come off first, or each would put back the other's.)
	if state > 0 and int(head.get_meta("expr_state", 0)) & 2:
		express(f, false, false)
	var saved: Dictionary = head.get_meta("talk_saved", {})
	var list := []
	for i in saved:
		if head.colors[i] == saved[i][1]:
			head.colors[i] = saved[i][0]
		list.append(i)
	saved = {}
	if state > 0:
		var front := head.grid.z - 1
		var at := {}
		for i in head.fx.size():
			if head.fz[i] == front:
				at[Vector2i(head.fx[i], head.fy[i])] = i
		for mk in talk_marks(state):
			var k := Vector2i(int(mk[0]), int(mk[1]))
			if not at.has(k) or head.alive[at[k]] == 0:
				continue
			var i: int = at[k]
			saved[i] = [head.colors[i], mk[2]]
			head.colors[i] = mk[2]
			list.append(i)
	head.set_meta("talk_saved", saved)
	head.set_meta("talk_state", state)
	_redraw(head, list)
	var es := int(head.get_meta("expr_state", 0))
	FineHead.mood(head, (es & 1) != 0, (es & 2) != 0, state)

# ---------- A face alive: a blink, a grimace, a breath ----------

## Drawing only, every frame (Match): he blinks every few seconds; a blow that hurts screws his
## face up for a moment (eyes squeezed, brows down, teeth bared); his chest rises and falls,
## quicker and deeper as he runs out of breath. A dead man does none of it.
static func live(f, dt: float) -> void:
	var head: VoxelPart = f.head
	if head == null or not is_instance_valid(head) or head.missing or head.severed:
		return
	var st: Dictionary = head.get_meta("life", {})
	if st.is_empty():
		st = {"blink": randf_range(0.8, 4.0), "shut": 0.0, "hurt": 0.0, "pain": float(f.pain), "ph": randf() * TAU}
		head.set_meta("life", st)
	var living: bool = f.alive and f.state != "dead"
	st.blink = float(st.blink) - dt
	if st.blink <= 0.0:
		st.shut = 0.13
		st.blink = randf_range(2.4, 5.5)
	st.shut = maxf(0.0, float(st.shut) - dt)
	# Pain leaping up is a blow that hurt.
	if float(f.pain) > float(st.pain) + 0.06:
		st.hurt = 0.8
	st.pain = float(f.pain)
	st.hurt = maxf(0.0, float(st.hurt) - dt)
	express(f, living and float(st.shut) > 0.0, living and float(st.hurt) > 0.0)
	var torso: VoxelPart = f.torso
	if torso == null or not is_instance_valid(torso):
		return
	if living:
		var winded := 1.0 - clampf(float(f.stamina) / 100.0, 0.0, 1.0)
		st.ph = fmod(float(st.ph) + dt * TAU * (0.27 + 0.5 * winded), TAU)
		var a := (0.012 + 0.022 * winded) * (0.5 + 0.5 * sin(float(st.ph)))
		torso.draw_scale = Vector3(1.0 + a * 0.45, 1.0 + a * 0.2, 1.0 + a)
		# Sweat: it comes as he tires, slowly, and stays a while after (a sheen on the skin).
		var want := clampf(winded * 1.4 - 0.15, 0.0, 1.0)
		var sw := float(st.get("sweat", 0.0))
		sw = move_toward(sw, want, dt * (0.06 if want > sw else 0.012))
		st.sweat = sw
		if absf(sw - float(st.get("sweat_drawn", 0.0))) > 0.04:
			st.sweat_drawn = sw
			for p in f.parts:
				if is_instance_valid(p) and p.mmi:
					p.mmi.set_instance_shader_parameter("sweat", sw)
	elif torso.draw_scale != Vector3.ONE:
		torso.draw_scale = Vector3.ONE

## His eyes shut (a blink) and his face screwed up (hurt), painted over his face as his talking
## mouth is; what was there put back when it is over (what a blow or blood changed meanwhile
## stays). The teeth only while he is not talking.
static func express(f, shut: bool, hurt: bool) -> void:
	var head: VoxelPart = f.head
	var state := (1 if shut else 0) + (2 if hurt else 0)
	if state == int(head.get_meta("expr_state", 0)):
		return
	var saved: Dictionary = head.get_meta("expr_saved", {})
	var list := []
	for i in saved:
		if head.colors[i] == saved[i][1]:
			head.colors[i] = saved[i][0]
		list.append(i)
	saved = {}
	if state > 0:
		var at := _face_at(head)
		var lid: Color = head.get_meta("lid_c", Color(0.5, 0.33, 0.25))
		var marks := []
		for x in [2, 3, 6, 7]:
			marks.append([x, 7, lid])
			marks.append([x, 6, lid if shut else DARK])
		if hurt:
			marks += [[2, 8, DARK], [3, 8, DARK], [6, 8, DARK], [7, 8, DARK]]
			if int(head.get_meta("talk_state", 0)) == 0:
				# Teeth gritted: the upper row wide, the lower under it, the corners of the mouth dark.
				marks += _row(2, 7, 3, WHITE) + _row(3, 6, 2, WHITE) + [[2, 2, MOUTH], [7, 2, MOUTH]]
		for mk in marks:
			var k := Vector2i(int(mk[0]), int(mk[1]))
			if not at.has(k):
				continue
			var i: int = at[k]
			if head.alive[i] == 0:
				continue
			# (A later mark over an earlier one wins, as on the face itself: the gaps between the
			# teeth; what is put back is still what was there first.)
			if saved.has(i):
				saved[i][1] = mk[2]
			else:
				saved[i] = [head.colors[i], mk[2]]
				list.append(i)
			head.colors[i] = mk[2]
	head.set_meta("expr_saved", saved)
	head.set_meta("expr_state", state)
	_redraw(head, list)
	FineHead.mood(head, shut, hurt, int(head.get_meta("talk_state", 0)))

## The front of his head: face grid (x, y) -> voxel, kept; and the colour of his eyelids (his
## skin there, a shade darker).
static func _face_at(head: VoxelPart) -> Dictionary:
	if head.has_meta("face_at"):
		return head.get_meta("face_at")
	var front := head.grid.z - 1
	var at := {}
	for i in head.fx.size():
		if head.fz[i] == front:
			at[Vector2i(head.fx[i], head.fy[i])] = i
	head.set_meta("face_at", at)
	if at.has(Vector2i(0, 5)):
		head.set_meta("lid_c", (head.colors[at[Vector2i(0, 5)]] as Color).darkened(0.18))
	return at

## The mouth's shapes while he talks, on the face's grid (lips at y 2, teeth at y 3).
static func talk_marks(state: int) -> Array:
	match state:
		1:
			return [[4, 2, MOUTH], [5, 2, MOUTH]]
		2:
			return _row(3, 6, 2, MOUTH) + [[4, 1, MOUTH], [5, 1, MOUTH]]
		3:
			return _row(3, 6, 3, WHITE) + _row(3, 6, 2, MOUTH) + [[3, 1, MOUTH], [6, 1, MOUTH], [4, 1, TONGUE], [5, 1, TONGUE]]
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
		# A face that has lived: stubble, a scar on the cheek, heavy brows (not on the editor's list:
		# a bot's only, drawn after the rest).
		if rng.randf() < 0.4:
			ids.append("bot_stubble")
		if rng.randf() < 0.22:
			ids.append("bot_scar_cheek" if rng.randf() < 0.5 else "bot_scar_lip")
		if rng.randf() < 0.3:
			ids.append("bot_brows_thick" if rng.randf() < 0.7 else "bot_unibrow")
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
