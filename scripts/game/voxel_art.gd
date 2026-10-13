class_name VoxelArt
extends RefCounted
## The arena's voxel art: models made by tools/gen_voxel_art.py (art/voxel/*.glb). Each surface
## of a model is named after its material and voxel size ("stone@10"); here every surface gets
## the voxel shader with that material's settings. Models are loaded once and copied after
## (the copies share their meshes).

const DIR := "res://art/voxel/"

## Shading per material: grain (per-voxel colour noise), roughness, metallic, specular,
## emission, flicker.
const KINDS := {
	"stone": [0.07, 0.92, 0.0, 0.35, 0.0, 0.0],
	"marble": [0.04, 0.5, 0.0, 0.55, 0.0, 0.0],
	"plaster": [0.05, 0.88, 0.0, 0.3, 0.0, 0.0],
	"wood": [0.1, 0.82, 0.0, 0.3, 0.0, 0.0],
	"iron": [0.1, 0.45, 0.75, 0.5, 0.0, 0.0],
	"bronze": [0.08, 0.36, 0.85, 0.5, 0.0, 0.0],
	"gold": [0.05, 0.26, 1.0, 0.5, 0.0, 0.0],
	"cloth": [0.06, 1.0, 0.0, 0.2, 0.0, 0.0],
	"terracotta": [0.08, 0.78, 0.0, 0.35, 0.0, 0.0],
	"straw": [0.16, 1.0, 0.0, 0.2, 0.0, 0.0],
	"ember": [0.25, 0.9, 0.0, 0.2, 4.0, 1.0],
	"glow": [0.02, 0.08, 0.0, 0.8, 0.0, 0.0],
}

static var _templates := {}
static var _materials := {}

## A material by its surface name ("stone@10": stone, 10 cm voxels).
static func material(tag: String) -> ShaderMaterial:
	if _materials.has(tag):
		return _materials[tag]
	var kind := tag.get_slice("@", 0)
	var cm := float(tag.get_slice("@", 1)) if tag.contains("@") else 10.0
	var k: Array = KINDS.get(kind, KINDS.stone)
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/voxel.gdshader")
	m.set_shader_parameter("voxel_size", cm / 100.0)
	m.set_shader_parameter("grain", k[0])
	m.set_shader_parameter("roughness", k[1])
	m.set_shader_parameter("metallic", k[2])
	m.set_shader_parameter("specular", k[3])
	m.set_shader_parameter("emission", k[4])
	m.set_shader_parameter("flicker", k[5])
	_materials[tag] = m
	return m

## A fresh copy of a model, or null when its file is missing.
static func make(name_: String) -> Node3D:
	var t: Node3D = _templates.get(name_)
	if t == null:
		t = _load(name_)
		if t == null:
			return null
		_templates[name_] = t
	return t.duplicate()

## A model's meshes, by node name (for the bowl, cut into sectors).
static func meshes(name_: String) -> Array:
	var out := []
	var n := make(name_)
	if n == null:
		return out
	for mi in _mesh_instances(n):
		out.append(mi.mesh)
	n.free()
	return out

static func _load(name_: String) -> Node3D:
	var path := DIR + name_ + ".glb"
	var root: Node3D = null
	if ResourceLoader.exists(path):
		var ps: PackedScene = load(path)
		if ps:
			root = ps.instantiate() as Node3D
	if root == null:
		# A checkout never opened in the editor: read the file itself.
		var abs_path := ProjectSettings.globalize_path(path)
		if not FileAccess.file_exists(abs_path):
			push_warning("voxel art missing: " + path)
			return null
		var doc := GLTFDocument.new()
		var st := GLTFState.new()
		if doc.append_from_file(abs_path, st) != OK:
			return null
		root = doc.generate_scene(st) as Node3D
	for mi in _mesh_instances(root):
		var mesh: Mesh = mi.mesh
		for i in mesh.get_surface_count():
			var sm := mesh.surface_get_material(i)
			mi.set_surface_override_material(i, material(sm.resource_name if sm else "stone@10"))
		# Voxel silhouettes do not survive mesh simplification; keep the full model.
		mi.lod_bias = 128.0
	return root

static func _mesh_instances(n: Node) -> Array:
	var out := []
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		out.append_array(_mesh_instances(c))
	return out

## Puts a copy of a model under `parent` at `pos`, turned `yaw` about the vertical. Its front
## (+z in the model) faces the way yaw points it. Returns the copy (or null).
static func place(parent: Node, name_: String, pos: Vector3, yaw := 0.0) -> Node3D:
	var n := make(name_)
	if n == null:
		return null
	parent.add_child(n)
	n.position = pos
	n.rotation.y = yaw
	return n

## The yaw that turns a model's front (+z) toward the arena's middle from `pos`.
static func facing_centre(pos: Vector3) -> float:
	return atan2(-pos.x, -pos.z)
