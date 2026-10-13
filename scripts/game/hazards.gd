class_name Hazards
extends Node3D
## Arena traps (hazards.js): spike plates that come up through the sand, a spinning blade, a
## chariot with scythes on its wheels. Each is a weapon nobody holds, moved by hand, so the
## ordinary combat code deals the damage when it meets a body.

const RADIUS := 15.0
var list: Array = []
var time := 0.0

static func random_specs(types: Array, rng: RandomNumberGenerator) -> Array:
	var specs := []
	if types.has("spikes"):
		for i in 6:
			var a := float(i) / 6.0 * TAU + rng.randf() * 0.6
			var r := 2.5 + rng.randf() * (RADIUS - 4.5)
			specs.append({"type": "spikes", "x": sin(a) * r, "z": cos(a) * r, "phase": rng.randf() * 5.0})
	if types.has("blade"):
		specs.append({"type": "blade", "x": 0.0, "z": 0.0, "speed": 1.5})
	if types.has("chariot"):
		specs.append({"type": "chariot", "r": 7.0, "speed": 5.0, "phase": 0.0})
	return specs

static func _vox(out: Array, x0: int, x1: int, y0: int, y1: int, z0: int, z1: int, mat: String, type: String) -> void:
	for x in range(x0, x1 + 1):
		for y in range(y0, y1 + 1):
			for z in range(z0, z1 + 1):
				out.append([x, y, z, mat, type])

func _hazard(name_: String, voxels: Array) -> Weapon:
	var w := Weapon.new()
	w.setup({"name": name_, "voxels": voxels, "sharpness": 1.0}, 1.0)
	w.is_hazard = true
	w.freeze = true
	w.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	add_child(w)
	return w

func build(specs: Array) -> void:
	clear()
	for s in specs:
		match s.type:
			"spikes": _spikes(s)
			"blade": _blade(s)
			"chariot": _chariot(s)

func clear() -> void:
	for h in list:
		if is_instance_valid(h.w):
			h.w.queue_free()
		if h.get("plate") and is_instance_valid(h.plate):
			h.plate.queue_free()
	list.clear()

func _spikes(s: Dictionary) -> void:
	# A 3 x 3 bed of steel spikes, 10 voxels (0.4 m) tall, points up.
	var vox := []
	for i in [-1, 0, 1]:
		for j in [-1, 0, 1]:
			_vox(vox, i * 8, i * 8, 0, 7, j * 8, j * 8, "steel", "blunt")
			_vox(vox, i * 8, i * 8, 8, 9, j * 8, j * 8, "steel", "point")
	var w := _hazard("Spike trap", vox)
	var plate := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.1, 0.04, 1.1)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.23, 0.21, 0.19)
	bm.material = mat
	plate.mesh = bm
	add_child(plate)
	plate.global_position = Vector3(s.x, 0.02, s.z)
	# The voxel plate sits on it; the old plate shows as a rim round it, red when the spikes come.
	if VoxelArt.place(plate, "spike_plate", Vector3(0, -0.015, 0)) != null:
		bm.size = Vector3(1.3, 0.03, 1.3)
	w.global_position = Vector3(s.x, -0.42, s.z)
	list.append({"type": "spikes", "w": w, "plate": plate, "x": s.x, "z": s.z, "phase": s.phase, "y": -0.42})

func _blade(s: Dictionary) -> void:
	var vox := []
	_vox(vox, -5, 5, 0, 21, -5, 5, "wood", "blunt")
	for sgn in [-1, 1]:
		_vox(vox, -1, 1, 7, 8, sgn * 6, sgn * 55, "iron", "blunt")
		_vox(vox, sgn * 2, sgn * 11, 8, 8, sgn * 15, sgn * 105, "steel", "edge")
	var w := _hazard("Spinning blade", vox)
	w.global_position = Vector3(s.x, 0.0, s.z)
	list.append({"type": "blade", "w": w, "speed": float(s.speed), "angle": 0.0})

func _chariot(s: Dictionary) -> void:
	var vox := []
	_vox(vox, -13, 13, 11, 25, -30, 0, "wood", "blunt")
	for sx in [-9, 9]:
		_vox(vox, sx - 4, sx + 4, 18, 35, 16, 50, "wood", "blunt")
	for sgn in [-1, 1]:
		_vox(vox, sgn * 16, sgn * 16, 0, 22, -26, -4, "wood", "blunt")
		_vox(vox, sgn * 17, sgn * 38, 11, 12, -17, -13, "steel", "edge")
	var w := _hazard("Chariot scythe", vox)
	var a := float(s.get("phase", 0.0))
	var r := float(s.get("r", 7.0))
	w.global_position = Vector3(sin(a) * r, 0, cos(a) * r)
	list.append({"type": "chariot", "w": w, "r": r, "speed": float(s.get("speed", 5.0)), "angle": a})

## True when a spinning blade arm is about to sweep through `pos` (bots jump it).
func blade_incoming(pos: Vector3, lead := 0.45) -> bool:
	for h in list:
		if h.type != "blade":
			continue
		var w: Weapon = h.w
		var dx := pos.x - w.global_position.x
		var dz := pos.z - w.global_position.z
		var r := Vector2(dx, dz).length()
		if r < 0.5 or r > 4.8:
			continue
		var me := atan2(dx, dz)
		for arm in [0.0, PI]:
			var ahead := wrapf(me - (h.angle + arm), -PI, PI)
			if ahead > 0.0 and ahead < lead:
				return true
	return false

## Host: move the traps (their speed is kept for the combat code, a frozen body has none).
func update(dt: float) -> void:
	time += dt
	for h in list:
		var w: Weapon = h.w
		if not is_instance_valid(w):
			continue
		var before := w.global_position
		match h.type:
			"spikes":
				var cycle := fmod(time + h.phase, 6.0)
				var target := 0.0 if cycle > 4.8 and cycle < 5.6 else -0.42
				var warn := cycle > 4.0 and cycle < 4.8
				h.plate.mesh.material.albedo_color = Color(0.61, 0.16, 0.1) if warn else Color(0.23, 0.21, 0.19)
				h.y = move_toward(h.y, target, dt * (5.0 if target > h.y else 2.0))
				w.global_position = Vector3(h.x, h.y, h.z)
			"blade":
				h.angle += h.speed * dt
				w.global_transform = Transform3D(Basis(Vector3.UP, h.angle), w.global_position)
			"chariot":
				h.angle += h.speed / h.r * dt
				var p := Vector3(sin(h.angle) * h.r, 0, cos(h.angle) * h.r)
				w.global_transform = Transform3D(Basis(Vector3.UP, h.angle + PI / 2.0 * signf(h.speed)), p)
		w.hazard_vel = (w.global_position - before) / dt
		if h.type == "blade":
			w.hazard_spin = Vector3(0, h.speed, 0)

func snapshot() -> Array:
	var out := []
	for h in list:
		var t: Transform3D = h.w.global_transform
		var q := t.basis.get_rotation_quaternion()
		out.append([snappedf(t.origin.x, 0.001), snappedf(t.origin.y, 0.001), snappedf(t.origin.z, 0.001), snappedf(q.x, 0.001), snappedf(q.y, 0.001), snappedf(q.z, 0.001), snappedf(q.w, 0.001)])
	return out

func apply_snapshot(rows: Array) -> void:
	for i in mini(rows.size(), list.size()):
		var r = rows[i]
		if r is Array and r.size() >= 7:
			list[i].w.global_transform = Transform3D(Basis(Quaternion(r[3], r[4], r[5], r[6]).normalized()), Vector3(r[0], r[1], r[2]))
			if list[i].type == "spikes":
				list[i].plate.mesh.material.albedo_color = Color(0.61, 0.16, 0.1) if float(r[1]) > -0.3 else Color(0.23, 0.21, 0.19)
