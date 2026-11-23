class_name MenuMan
extends RefCounted
## The player's gladiator standing in a menu's 3D view (the armourer's dressing room, the
## physician's table): the new look's man as the arena draws him, his build, head and hair, in
## whatever armour is given, held still. The same man the armour bench puts its plates on
## (ArmourForge._body_man), at his own size.

## (A test's: made over the frames that follow without a screen too.)
static var staged_always := false

## Stands him under `parent` (a Stage3D's pivot) and returns him (`await` it: with a screen he is made over the
## frames that follow, out of the world until whole, not in one frame, which was a stop of a tenth of a second to
## a third each time a piece was put on him or taken off, and in a room the whole room's; null if he was dropped
## meanwhile). `armour`: the ids of the pieces he wears. `opts`: `body` (Body.sanitize'd wounds, the physician's),
## `plain` (his look but for hat and hair: plating his head).
static func stand(parent: Node3D, armour: Array, opts := {}) -> Fighter:
	var lk: Dictionary = Save.get_value("look", {}) if Save.get_value("look", {}) is Dictionary else {}
	var menu_s = load("res://scripts/ui/menu.gd")
	var cloths: Array = menu_s.CLOTH
	var slots: Dictionary = menu_s.LOOK_SLOTS
	var covers_head := armour.any(func(id): return Armory.parts_of(String(id)).has("head"))
	var worn: Array = []
	for k in slots:
		var arr: Array = slots[k]
		var id := String(arr[clampi(int(lk.get(k, 0)), 0, arr.size() - 1)])
		if covers_head and (id.begins_with("hat_") or id.begins_with("hair_")):
			continue
		if id != "" and not menu_s.look_locked(id):
			worn.append(id)
	var f := Fighter.new()
	parent.add_child(f)
	var o := {"name": "Menu", "slot": 7, "team": 9, "bot": false,
		"team_color": Color.hex(int(cloths[clampi(int(lk.get("cloth", 0)), 0, cloths.size() - 1)]) << 8 | 0xff),
		"skin": int(Fighter.SKINS[clampi(int(lk.get("skin", 0)), 0, Fighter.SKINS.size() - 1)]),
		"build": FineBody.BUILDS[clampi(int(lk.get("build", 0)), 0, FineBody.BUILDS.size() - 1)],
		"mods": {}}
	if opts.get("body") is Dictionary:
		o["body"] = opts.body
	var staged := staged_always or DisplayServer.get_name() != "headless"   # (no screen, no stop to spare: the tests and the benchmarks build him as before)
	if staged:
		f.process_mode = Node.PROCESS_MODE_DISABLED
		f.visible = false
		o["staged"] = true
	await f.build(Vector3.ZERO, 0.0, {"main": "", "off": "", "armor": armour + worn}, o)
	if not is_instance_valid(f) or not f.is_inside_tree():
		return null
	for p in f.parts:
		p.freeze = true
		p.collision_layer = 0
		p.collision_mask = 0
		p.reset_physics_interpolation()
	for p in f.parts:
		if p.has_method("snap_drawing"):
			p.snap_drawing()
	f.set_physics_process(false)
	if staged:
		f.process_mode = Node.PROCESS_MODE_INHERIT
		f.visible = true
	return f
