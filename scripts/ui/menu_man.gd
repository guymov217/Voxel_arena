class_name MenuMan
extends RefCounted
## The player's gladiator standing in a menu's 3D view (the armourer's dressing room, the
## physician's table): the new look's man as the arena draws him, his build, head and hair, in
## whatever armour is given, held still. The same man the armour bench puts its plates on
## (ArmourForge._body_man), at his own size.

## Stands him under `parent` (a Stage3D's pivot) and returns him. `armour`: the ids of the pieces
## he wears. `opts`: `body` (Body.sanitize'd wounds, the physician's), `plain` (his look
## but for hat and hair: plating his head).
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
	f.build(Vector3.ZERO, 0.0, {"main": "", "off": "", "armor": armour + worn}, o)
	for p in f.parts:
		p.freeze = true
		p.collision_layer = 0
		p.collision_mask = 0
		p.reset_physics_interpolation()
	for p in f.parts:
		if p.has_method("snap_drawing"):
			p.snap_drawing()
	f.set_physics_process(false)
	return f
