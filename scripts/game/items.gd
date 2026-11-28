class_name Items
extends Node3D
## Things in flight or lying about that are not weapons (items.js): pots, arrows, bolts, darts,
## rocks, nets, food the crowd throws, banana peels, a cheese wheel. Simple ballistic objects
## outside the physics world, walked in short steps so a fast arrow cannot pass through a body.
## Events go to `on_event` (throwables.gd decides what they do).

const RADIUS := 15.0
const TYPES := {
	"bread": {"size": 0.16}, "wine": {"size": 0.18}, "tomato": {"size": 0.1}, "banana": {"size": 0.12}, "coin": {"size": 0.06},
	"rock": {"size": 0.12, "projectile": true}, "net": {"size": 0.3, "projectile": true, "net": [1.3, 5]},
	"pot_thunder": {"size": 0.16, "projectile": true, "pot": 0x6a4a8a}, "pot_nail": {"size": 0.16, "projectile": true, "pot": 0x5b5f66},
	"torch": {"size": 0.12, "projectile": true}, "gauntlet": {"size": 0.2}, "waterskin": {"size": 0.16},
	"pot_fire": {"size": 0.16, "projectile": true, "pot": 0xff7a1a},
	"pot_acid": {"size": 0.16, "projectile": true, "pot": 0x8fd43a}, "pot_bees": {"size": 0.18, "projectile": true, "pot": 0xe8b830},
	"pot_caltrops": {"size": 0.14, "projectile": true, "pot": 0x444444}, "pot_goat": {"size": 0.2, "projectile": true, "pot": 0x8b5a2b},
	"pot_bola": {"size": 0.14, "projectile": true}, "pot_oil": {"size": 0.18, "projectile": true, "pot": 0x6b7a2a},
	"pot_garum": {"size": 0.16, "projectile": true, "pot": 0x8a6a2a}, "pot_honey": {"size": 0.16, "projectile": true, "pot": 0xe8a020},
	"pot_smoke": {"size": 0.16, "projectile": true, "pot": 0x777777}, "pot_mystery": {"size": 0.2, "projectile": true, "pot": 0xd04aa0},
	"pot_chickens": {"size": 0.2, "projectile": true, "pot": 0xf7d32a}, "pot_anvil": {"size": 0.22, "projectile": true, "heavy": 30.0},
	"pot_harpoon": {"size": 0.12, "projectile": true}, "pot_dart": {"size": 0.08, "projectile": true, "dart": true},
	"pot_bolt": {"size": 0.08, "projectile": true, "dart": true}, "nail": {"size": 0.03, "projectile": true, "dart": true},
	"pot_arrow": {"size": 0.08, "projectile": true, "dart": true}, "pot_arrow_fire": {"size": 0.08, "projectile": true, "dart": true},
	"pot_arrow_poison": {"size": 0.08, "projectile": true, "dart": true}, "pot_arrow_ice": {"size": 0.08, "projectile": true, "dart": true},
	"pot_arrow_blast": {"size": 0.08, "projectile": true, "dart": true}, "pot_arrow_barb": {"size": 0.08, "projectile": true, "dart": true},
	"pot_arrow_pierce": {"size": 0.08, "projectile": true, "dart": true, "pierce": true},
	"pot_discus": {"size": 0.12, "projectile": true, "discus": true}, "pot_bignet": {"size": 0.3, "projectile": true, "net": [1.8, 6]},
	"cheese": {"size": 0.24, "rolling": true, "roll_r": 0.21},
	"arrow_loose": {"size": 0.06, "debris": true},
	"caltrop": {"size": 0.06},
}

var list: Array = []
## Items gone (a pot shattered, a dart spent): their look kept a while, hidden, for the kill cam
## to show them flying in its replay (freed at once, a thrown pot was never on its tape: user).
var ghosts: Array = []   # [node, msec gone]
const GHOST_MS := 8000
var next_id := 1
var headless := false
var on_event: Callable

static var _mats := {}

## An item box's look: the voxel shader (shaders/voxel_body.gdshader) in its colour, shaded as
## what the colour says it is (grey: iron; gold: metal; browns: wood; the rest matte), with the
## box's edges a shade darker.
static func _mat(color: int, size := Vector3.ZERO) -> ShaderMaterial:
	var key := "%d:%s" % [color, size]
	if not _mats.has(key):
		var c := Color.hex(color << 8 | 0xff)
		var m := ShaderMaterial.new()
		m.shader = load("res://shaders/voxel_body.gdshader")
		m.set_shader_parameter("tint", c)
		m.set_shader_parameter("box_half", size * 0.5)
		m.set_shader_parameter("force_kind", _kind_of_color(c))
		_mats[key] = m
	return _mats[key]

static func _kind_of_color(c: Color) -> int:
	var sat := c.s
	if sat < 0.18 and c.v < 0.8:
		return 3            # iron, steel
	if c.h > 0.1 and c.h < 0.16 and sat > 0.6 and c.v > 0.85:
		return 4            # gold
	if c.h < 0.1 and sat > 0.4 and c.v < 0.7:
		return 5            # wood, clay
	return 2

## (One mesh for every box of a size and colour, as there is one material: the hundred and
## twenty nails of a pot were three hundred meshes made in the step it broke.)
static var _box_meshes := {}
static func _box(g: Node3D, w: float, h: float, d: float, color: int, x := 0.0, y := 0.0, z := 0.0) -> void:
	var mi := MeshInstance3D.new()
	var size := Vector3(w, h, d)
	var key := "%d:%s" % [color, size]
	var bm: BoxMesh = _box_meshes.get(key)
	if bm == null:
		bm = BoxMesh.new()
		bm.size = size
		bm.material = _mat(color, size)
		_box_meshes[key] = bm
	mi.mesh = bm
	mi.position = Vector3(x, y, z)
	g.add_child(mi)

## A flat round plate (a cylinder on its axis, up) in a colour, one mesh to each size and colour (a discus's).
static var _disc_meshes := {}
static func _disc_mesh(d: float, h: float, color: int) -> CylinderMesh:
	var key := "%d:%s:%s" % [color, d, h]
	var cm: CylinderMesh = _disc_meshes.get(key)
	if cm == null:
		cm = CylinderMesh.new()
		cm.top_radius = d * 0.5
		cm.bottom_radius = d * 0.5
		cm.height = h
		cm.radial_segments = 18
		cm.rings = 1
		cm.material = _mat(color, Vector3(d, h, d))
		_disc_meshes[key] = cm
	return cm

## A box of flame: lit from within, not by the sun.
static func _flame(g: Node3D, w: float, h: float, d: float, color: Color, x := 0.0, y := 0.0, z := 0.0) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(w, h, d)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	bm.material = mat
	mi.mesh = bm
	mi.position = Vector3(x, y, z)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.set_meta("flame", Vector3(x, y, z))   # (where it stands on the model, and how tall: it flickers)
	mi.set_meta("flame_h", h)
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
			# A net gathered up for the throw: the heap of rope, and the lead weights of its rim hanging out of it.
			var k := 1.0 if type == "net" else 1.35
			_box(g, 0.2 * k, 0.1 * k, 0.17 * k, 0x8a6a3a)
			_box(g, 0.15 * k, 0.12 * k, 0.2 * k, 0x7a5c30, 0.02, 0.03, 0)
			_box(g, 0.17 * k, 0.05 * k, 0.12 * k, 0x9b7a44, -0.02, 0.07 * k, 0.01)
			for a in 6:
				var an := float(a) * TAU / 6.0 + 0.4
				_box(g, 0.04, 0.04, 0.04, 0x4f5258, sin(an) * 0.11 * k, -0.08 * k - 0.02 * float(a % 2), cos(an) * 0.1 * k)
		"torch":
			# Burning pitch on a stick: the wooden haft, the pitch-soaked rag wound round its head,
			# and the flame standing up out of it.
			_box(g, 0.035, 0.44, 0.035, 0x6b4426, 0, 0.13, 0)
			_box(g, 0.075, 0.1, 0.075, 0x2e2218, 0, 0.36, 0)
			_box(g, 0.06, 0.02, 0.085, 0x4a3524, 0, 0.33, 0)
			_flame(g, 0.085, 0.13, 0.085, Color(1.0, 0.45, 0.08), 0, 0.46, 0)
			_flame(g, 0.055, 0.11, 0.055, Color(1.0, 0.75, 0.2), 0.005, 0.53, 0)
			_flame(g, 0.03, 0.07, 0.03, Color(1.0, 0.93, 0.6), 0, 0.59, 0)
		"waterskin":
			# A goatskin of water: the bulging bag, its tied neck and the strap.
			_box(g, 0.16, 0.2, 0.1, 0x7a5232, 0, -0.02, 0)
			_box(g, 0.12, 0.06, 0.12, 0x7a5232, 0, -0.1, 0)
			_box(g, 0.05, 0.07, 0.05, 0x5a3a22, 0, 0.11, 0)
			_box(g, 0.06, 0.015, 0.06, 0x3a2a1a, 0, 0.13, 0)
			_box(g, 0.2, 0.02, 0.02, 0x3a2a1a, 0, 0.06, 0.05)
		"gauntlet":
			# A bronze hand, open: the palm, four fingers and a thumb.
			_box(g, 0.12, 0.03, 0.12, 0xa5702b); _box(g, 0.12, 0.04, 0.06, 0x7a5220, 0, 0, -0.08)
			for i in 4:
				_box(g, 0.022, 0.03, 0.08, 0xb8803a, -0.045 + i * 0.03, 0, 0.1)
			_box(g, 0.08, 0.03, 0.022, 0xb8803a, 0.09, 0, 0.02)
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
		"pot_arrow", "pot_arrow_fire", "pot_arrow_poison", "pot_arrow_ice", "pot_arrow_blast", "pot_arrow_pierce", "pot_arrow_barb", "arrow_loose":
			var tip: int = {"pot_arrow_fire": 0xff7a1a, "pot_arrow_poison": 0x7ae04a, "pot_arrow_ice": 0xa8e8ff, "pot_arrow_blast": 0x4a2a22, "pot_arrow_pierce": 0x6c7480, "pot_arrow_barb": 0xb08a4a}.get(type, 0xc9d1d9)
			_box(g, 0.02, 0.02, 0.6, 0xc9a86a); _box(g, 0.03, 0.03, 0.07, tip, 0, 0, 0.32); _box(g, 0.06, 0.02, 0.08, 0xe04040, 0, 0, -0.26); _box(g, 0.02, 0.06, 0.08, 0xe8e8e8, 0, 0, -0.26)
			match type:
				"pot_arrow_blast":
					# A little charge lashed behind the head, its fuse alight.
					_box(g, 0.055, 0.055, 0.08, 0x4a2a22, 0, 0, 0.25); _box(g, 0.06, 0.06, 0.012, 0xd04030, 0, 0, 0.29); _box(g, 0.012, 0.012, 0.04, 0xff9a2a, 0, 0.035, 0.34)
				"pot_arrow_pierce":
					# A long, narrow iron head.
					_box(g, 0.016, 0.016, 0.1, 0x8a929e, 0, 0, 0.41)
				"pot_arrow_barb":
					# Barbs on both sides of the head.
					_box(g, 0.08, 0.012, 0.025, 0xb08a4a, 0, 0, 0.29); _box(g, 0.012, 0.08, 0.025, 0xb08a4a, 0, 0, 0.29)
		"pot_discus":
			# A bronze discus: a round plate with a raised boss at its middle (as a flat square tile it did not look like one, user).
			for k in [[0.27, 0.022, 0xc9953f], [0.15, 0.034, 0xa97a2f]]:
				var mi := MeshInstance3D.new()
				mi.mesh = _disc_mesh(float(k[0]), float(k[1]), int(k[2]))
				g.add_child(mi)
		"cheese":
			# A round wheel on its edge, its axle across (local x): a rind and a paler face.
			for k in [[0.42, 0.13, 0xd9a83a], [0.36, 0.135, 0xf2c94c]]:
				var mi := MeshInstance3D.new()
				var cm := CylinderMesh.new()
				cm.top_radius = k[0] * 0.5; cm.bottom_radius = k[0] * 0.5; cm.height = k[1]
				cm.radial_segments = 14; cm.rings = 1
				cm.material = _mat(k[2], Vector3(k[1], k[0], k[0]))
				mi.mesh = cm
				mi.rotation.z = PI * 0.5
				g.add_child(mi)
		"caltrop":
			# Four iron spikes, one always pointing up.
			_box(g, 0.014, 0.08, 0.014, 0x5b5f66, 0, 0.03, 0)
			_box(g, 0.07, 0.014, 0.014, 0x5b5f66, 0.02, -0.01, 0)
			_box(g, 0.014, 0.014, 0.07, 0x5b5f66, -0.01, -0.01, 0.02)
		"bandage":
			_box(g, 0.16, 0.12, 0.12, 0xf2ecdc); _box(g, 0.17, 0.04, 0.04, 0xd8cfb8); _box(g, 0.06, 0.012, 0.2, 0xf2ecdc, 0.03, -0.065, 0.06)
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
		"dart": def.get("dart", false), "spin": Vector3.ZERO if def.get("dart", false) else (Vector3(0, 26.0, 0) if def.get("discus", false) else Vector3(randf() * 8.0, randf() * 8.0, 0)), "node": null}
	next_id = maxi(next_id, it.id) + 1
	if def.has("net"):
		_knit(it, def.net, pos, vel)
	elif not headless:
		var n := visual(type)
		add_child(n)
		n.position = pos
		n.add_to_group("kc_item")
		it.node = n
		_face(it)
	list.append(it)
	return it

## A net: knitted (NetSim), gathered up in the hand at `pos` and flung open as it leaves it with `vel`; it is drawn as a mesh of its own: one fine mesh made once, put in place by its shader
## off the knots' places and out of the bodies' boxes (two small textures, sent anew each step), and the lead of its rim as stones.
func _knit(it: Dictionary, spec: Array, pos: Vector3, vel: Vector3) -> void:
	var net := NetSim.make(float(spec[0]), int(spec[1]))
	var fwd := Vector3(vel.x, 0.0, vel.z)
	fwd = fwd.normalized() if fwd.length() > 0.1 else Vector3.FORWARD
	# (It opens a disc, flat as it flies, a little turned to its way: a net thrown comes over what it is thrown at, not edge on.)
	net.launch(pos, vel, (Vector3.UP * 0.8 + fwd * 0.3).normalized(), 1.0 if int(it.id) % 2 == 0 else -1.0)
	it.net = net
	it.spin = Vector3.ZERO
	if headless:
		return
	var root := Node3D.new()
	root.top_level = true
	var mat := ShaderMaterial.new()
	mat.shader = _net_shader()
	var side := net.grid_side()
	var gtex := ImageTexture.create_from_image(Image.create_from_data(side, side, false, Image.FORMAT_RGBAF, net.grid_bytes()))
	var btex := ImageTexture.create_from_image(Image.create_from_data(4, NetSim.MAX_BOXES, false, Image.FORMAT_RGBAF, net.box_bytes()))
	mat.set_shader_parameter("grid", gtex)
	mat.set_shader_parameter("boxes", btex)
	mat.set_shader_parameter("box_count", 0)
	var rope := MeshInstance3D.new()
	rope.mesh = net.build_mesh()
	rope.material_override = mat
	rope.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	rope.custom_aabb = net.bounds()
	var lead := MeshInstance3D.new()
	lead.mesh = ArrayMesh.new()
	lead.material_override = _lead_mat()
	root.add_child(rope)
	root.add_child(lead)
	add_child(root)
	root.add_to_group("kc_item")
	it.node = root
	it.draw = {"mat": mat, "g": gtex, "b": btex, "rope": rope, "lead": lead}
	net.fill_stones(lead.mesh)
	net.dirty = false

static var _net_shader_res: Shader = null
static func _net_shader() -> Shader:
	if _net_shader_res == null:
		_net_shader_res = load("res://shaders/net.gdshader")
	return _net_shader_res

static var _lead_material: StandardMaterial3D = null
static func _lead_mat() -> StandardMaterial3D:
	if _lead_material == null:
		_lead_material = StandardMaterial3D.new()
		_lead_material.albedo_color = Color(0.3, 0.31, 0.34)
		_lead_material.metallic = 0.35
		_lead_material.roughness = 0.55
	return _lead_material

## Thrown from a hand so it lands on `target` (the flat speed given, the lob worked out).
func throw_at(type: String, from: Vector3, target: Vector3, owner_: Node, speed := 11.0, gravity := 9.81) -> Dictionary:
	var d := target - from
	var t := maxf(0.2, Vector2(d.x, d.z).length() / speed)
	return spawn(type, from, Vector3(d.x / t, (d.y + 0.5 * gravity * t * t) / t, d.z / t), owner_)

## Thrown at `speed` along the flat arc to `target` (the low one of the two), or straight along
## the line a touch above it when the target is out of reach: a pot goes where it is aimed.
func throw_flat(type: String, from: Vector3, target: Vector3, owner_: Node, speed: float, gravity := 9.81) -> Dictionary:
	return spawn(type, from, flat_shot(target - from, speed, gravity), owner_)

const NET_TRUNK := 1.35           # m: the height it is aimed at, at the most (a standing man's chest: his head is no mark for it)
const NET_OVER := 0.6             # a net is thrown to come down over its mark: its middle is aimed this far above the man's trunk
const NET_RANGE := 6.5            # m: as far as a net can be thrown
const NET_SHORT := 0.1            # of the way to him, the part it is aimed short of him (it comes on a little after it is over him)
# How the air holds a net's middle back along the ground (NET_KH, 1/s), how it holds back its fall (NET_KV) and the speed it falls at in the end (NET_VT, m/s): its flight as NetSim flies it,
# fitted to it (a net's drag is not one number: its rim is lead and its rope is not), good out to the range a net can be thrown.
const NET_KH := 1.38
const NET_KV := 1.4
const NET_VT := -7.1
const NET_FLIGHT := Vector2(0.55, 1.5)  # the least and most seconds a thrown net is in the air (it has to come open first)

## A net thrown to come down over `aim` (a man's trunk): it is in the air as long as its speed makes of the distance, and that long enough to come open, the throw worked out for the air
## that holds a net back (a pot's lob would have it fall short of the mark).
func throw_net(type: String, from: Vector3, aim: Vector3, owner_: Node, speed := 9.0) -> Dictionary:
	# (Aimed at a man's head or at his chest it is the same throw: it is meant to come down over the whole of him.)
	var to := Vector3(aim.x, minf(aim.y, NET_TRUNK), aim.z) + Vector3(0, NET_OVER, 0) - from
	var flat := Vector2(to.x, to.z) * (1.0 - NET_SHORT)
	if flat.length() > NET_RANGE:
		flat *= NET_RANGE / flat.length()   # (it falls short of a mark further off: a net is not thrown so far)
	var t := clampf(flat.length() / maxf(speed, 1.0), NET_FLIGHT.x, NET_FLIGHT.y)
	var vh := flat * (NET_KH / (1.0 - exp(-NET_KH * t)))
	var vy := NET_VT + (to.y - NET_VT * t) * (NET_KV / (1.0 - exp(-NET_KV * t)))
	return spawn(type, from, Vector3(vh.x, vy, vh.y), owner_)

## The velocity, at `speed`, that lands on `d` (from the shooter) by the low arc; out of range,
## the arc that goes farthest, lifted a little.
static func flat_shot(d: Vector3, speed: float, gravity := 9.81) -> Vector3:
	var dx := maxf(0.01, Vector2(d.x, d.z).length())
	var v2 := speed * speed
	var disc := v2 * v2 - gravity * (gravity * dx * dx + 2.0 * d.y * v2)
	var pitch := atan2(v2 - sqrt(disc), gravity * dx) if disc >= 0.0 else atan2(d.y, dx) + 0.04
	var yaw := atan2(d.x, d.z)
	return Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * speed

## Thrown in from the stands to land at `target` after `t` seconds.
func throw_from_stands(type: String, target: Vector3, t := 1.2, gravity := 9.81) -> Dictionary:
	var a := randf() * TAU
	var from := Vector3(sin(a) * (RADIUS + 3.0), 4.5, cos(a) * (RADIUS + 3.0))
	var v := Vector3((target.x - from.x) / t, 0, (target.z - from.z) / t)
	v.y = (target.y - from.y + 0.5 * gravity * t * t) / t
	return spawn(type, from, v)

func remove(it: Dictionary) -> void:
	if it.node and is_instance_valid(it.node):
		it.node.visible = false
		ghosts.append([it.node, Time.get_ticks_msec()])
	list.erase(it)

func clear() -> void:
	for it in list.duplicate():
		remove(it)
	for g in ghosts:
		if is_instance_valid(g[0]):
			g[0].queue_free()
	ghosts.clear()

func _free_ghosts() -> void:
	var now := Time.get_ticks_msec()
	while not ghosts.is_empty() and now - int(ghosts[0][1]) > GHOST_MS:
		if is_instance_valid(ghosts[0][0]):
			ghosts[0][0].queue_free()
		ghosts.pop_front()

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
		# Nowhere near this body at all: no part of it to test (a hail of nails tested every
		# part of every body at every sub-step).
		if c.torso.global_position.distance_squared_to(p) > pow(3.2 * float(c.S) + r, 2.0):
			continue
		var parts: Array = c.parts if any_part else [c.head, c.torso]
		for part in parts:
			if part == null or part.severed:
				continue
			if any_part:
				if Social.box_reaches(part, p, r):
					return {"char": c, "part": Social.struck_part(part, p)}
				continue
			var d := Social.box_distance(part, p)
			if d <= 0.0 or (r > 0.17 and d < r) or part.global_position.distance_to(p) < r + 0.1 * c.S:
				return {"char": c, "part": part}
	return null

## One step: flight, landing, hits. `chars` are the fighters and beasts in the arena.
func update(dt: float, chars: Array, gravity := 9.81) -> void:
	_free_ghosts()
	for it in list.duplicate():
		if not list.has(it):
			continue
		it.age += dt
		if it.has("net"):
			_update_net(it, dt, chars, true)
			continue
		var def: Dictionary = TYPES.get(it.type, {"size": 0.15})
		var size: float = def.get("size", 0.15)
		if not it.grounded:
			if def.get("discus", false):
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
					var r: float = 0.16 if it.dart else size * 0.6 + 0.04
					hit = hit_char(it.p, chars, r, null if it.get("bounced", false) else it.owner, true)
					if hit and it.get("struck", {}).has(hit.char):
						hit = null   # a heavy thing hits a man once, then drops off him
					if hit:
						break
			if it.node:
				_face(it)
				if not it.dart:
					it.node.rotation += it.spin * dt
			if hit and def.has("heavy"):
				# Something heavy (an anvil) does not burst: it strikes with its weight and speed,
				# loses most of its way in the man and falls off him to the sand.
				_emit({"kind": "strike", "type": it.type, "char": hit.char, "part": hit.part, "item": it, "p": it.p, "dir": it.vel.normalized(), "speed": it.vel.length(), "mass": def.heavy})
				if not it.has("struck"):
					it.struck = {}
				it.struck[hit.char] = true
				it.vel = it.vel * 0.15
				continue
			if hit and def.get("discus", false):
				# A discus is a hard plate at speed: it strikes the part it meets (the blow is Throwables' own, on_item "discus") and glances off him the way a plate
				# does, a ricochet, to come back round off the wall or the next man; each man it hits once in a flight.
				var away: Vector3 = it.p - (hit.part as Node3D).global_position
				away.y = 0.0
				away = away.normalized() if away.length() > 0.01 else -it.vel.normalized()
				_emit({"kind": "discus", "type": it.type, "char": hit.char, "part": hit.part, "item": it, "p": it.p, "dir": it.vel.normalized(), "speed": it.vel.length(), "ricochet": bool(it.get("bounced", false))})
				if not it.has("struck"):
					it.struck = {}
				it.struck[hit.char] = true
				it.vel = (it.vel - away * 1.7 * it.vel.dot(away)) * 0.6
				it.vel.y = maxf(it.vel.y, 0.8)
				it.bounced = true
				continue
			if hit:
				# (A bodkin stays in the man it has struck, through and through, the point out of his far side and
				# the fletching out of the near: "pierced". What it is made to go through is his armour, Fighter.apply_hit.)
				_emit({"kind": "splat", "type": it.type, "char": hit.char, "part": hit.part, "item": it, "p": it.p, "dir": it.vel.normalized(), "pierced": bool(def.get("pierce", false))})
				remove(it)
				continue
			if it.p.y <= size / 2.0 and def.has("heavy"):
				it.p.y = size / 2.0
				if it.vel.length() > 2.0:
					_emit({"kind": "land", "type": it.type, "char": null, "item": it, "p": it.p, "speed": it.vel.length()})
				it.vel = Vector3.ZERO
				it.grounded = true
				if it.node:
					it.node.position = it.p
					it.node.rotation = Vector3(0, it.node.rotation.y, 0)
				continue
			if it.p.y <= size / 2.0 and def.get("discus", false):
				# Down on the sand a discus skips (a plate does not burst), and lies where it stops.
				it.p.y = size / 2.0
				if it.vel.y < -1.2:
					it.vel.y = -it.vel.y * 0.45
					it.vel.x *= 0.72
					it.vel.z *= 0.72
					it.bounced = true
					_emit({"kind": "bounce", "type": it.type, "char": null, "item": it, "p": it.p})
				else:
					it.vel = Vector3.ZERO
					it.grounded = true
					it.rest_at = it.age
					if it.node:
						it.node.rotation = Vector3(0, it.node.rotation.y, 0)
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
		if it.age > 60.0 or (def.get("discus", false) and it.age - float(it.get("rest_at", it.age)) > 5.0):
			remove(it)
			continue
		if def.get("discus", false):
			continue   # (lying there: nobody eats it)
		if def.get("rolling", false) and it.vel.length_squared() > 0.05:
			it.vel *= pow(0.4, dt)
			it.p += it.vel * dt
			if it.node:
				it.node.position = it.p
				# Turned to where it rolls, then spun about its axle (Euler order YXZ: the yaw
				# first, the spin about the turned axle): it rolled sideways along its face.
				if Vector2(it.vel.x, it.vel.z).length_squared() > 0.01:
					it.node.rotation.y = atan2(it.vel.x, it.vel.z)
				it.node.rotation.x += Vector2(it.vel.x, it.vel.z).length() * dt / float(def.get("roll_r", size / 2.0))
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
			elif it.type == "caltrop":
				# A sole coming down on it (the man's weight drives the spike in and it stays in
				# his foot), or a body lying on it.
				var sp = _foot_on(c, it.p)
				if sp != null:
					_emit({"kind": "caltrop", "type": it.type, "char": c, "part": sp, "item": it, "p": it.p})
					remove(it)
					break
			elif c.kind != "beast":
				var t: Vector3 = c.torso.global_position
				if Vector2(t.x - it.p.x, t.z - it.p.z).length() < 0.55:
					_emit({"kind": "eat", "type": it.type, "char": c, "item": it, "p": it.p})
					remove(it)
					break

## A net's step: its ropes in the world (NetSim), its mesh drawn anew, and (on the host, where the fight is) the men it has come down over told to whoever acts on it, the men who are
## out of it let go, and the net gone a while after it lies still on the sand.
func _update_net(it: Dictionary, dt: float, chars: Array, host: bool) -> void:
	var net: NetSim = it.net
	var thrower = it.get("owner")
	var got: Array = net.advance(dt, chars, thrower if thrower != null and is_instance_valid(thrower) else null)
	it.p = net.center
	it.vel = net.velocity
	if net.dirty and it.node and is_instance_valid(it.node):
		var dr: Dictionary = it.draw
		var side := net.grid_side()
		(dr.g as ImageTexture).update(Image.create_from_data(side, side, false, Image.FORMAT_RGBAF, net.grid_bytes()))
		(dr.b as ImageTexture).update(Image.create_from_data(4, NetSim.MAX_BOXES, false, Image.FORMAT_RGBAF, net.box_bytes()))
		(dr.mat as ShaderMaterial).set_shader_parameter("box_count", net.box_count)
		(dr.rope as MeshInstance3D).custom_aabb = net.bounds()
		if net.stones_dirty:
			net.fill_stones(((dr.lead as MeshInstance3D).mesh) as ArrayMesh)
			net.stones_dirty = false
		net.dirty = false
	if not host:
		# (A guest is not told when the man is out of it: it lets him go when the time of such a net is out, as the host does by the man's own clock.)
		for c in net.caught.duplicate():
			if not is_instance_valid(c) or not c.alive or float(net.held_for.get(c, 0.0)) >= float(Throwables.NET_HOLD.get(String(it.type), 3.0)):
				net.release(c)
		return
	for c in got:
		_emit({"kind": "net", "type": it.type, "char": c, "part": c.torso, "item": it, "p": it.p, "dir": Vector3.DOWN, "speed": net.velocity.length()})
	for c in net.caught.duplicate():
		if not is_instance_valid(c) or not c.alive or c.net_timer <= 0.0:
			net.release(c)
	if net.rest_t > 3.0 or it.age > 25.0:
		remove(it)

## On a guest: the nets in the air are drawn as they fall over the men there (the host says where each is: apply_snapshot).
func update_guest_nets(dt: float, chars: Array) -> void:
	for it in list:
		if it.has("net"):
			_update_net(it, dt, chars, false)

func has_nets() -> bool:
	for it in list:
		if it.has("net"):
			return true
	return false

func _foot_on(c, p: Vector3):
	var s: float = c.S
	if c.state == "stand":
		for so in c.soles():
			var foot: Vector3 = so[1]
			if Vector2(foot.x - p.x, foot.z - p.z).length() < 0.1 * s and foot.y < 0.2 * s:
				return so[0]
		return null
	for q in c.parts:
		if not q.severed and q.global_position.distance_to(p) < q.half_ext.length() * 0.8:
			return q
	return null

## A sole of his (a man's, a beast's: Fighter.soles) coming down within `r` of `p` (a big body's
## feet the wider apart, its reach the wider).
func _near_feet(c, p: Vector3, r: float) -> bool:
	var s: float = float(c.S)
	var rr: float = r * maxf(1.0, sqrt(s))
	for so in c.soles():
		var sole: Vector3 = so[1]
		if Vector2(sole.x - p.x, sole.z - p.z).length() < rr and sole.y < p.y + 0.25 * s:
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
		if it.has("net"):
			# (Its ropes are this guest's own, falling over the men he sees: the host's word of where its middle is draws it back to where it should be.)
			var off: Vector3 = p - (it.net as NetSim).center
			(it.net as NetSim).shift(off if off.length() > 2.0 else off * 0.35)
			continue
		it.p = p
		it.vel = Vector3(r[5], r[6], r[7])
		_face(it)
	for it in list.duplicate():
		if not seen.has(it.id):
			remove(it)
