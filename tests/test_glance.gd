extends Node
## A blow meets armour square and bites, or at a slant (or with the flat of the blade) and
## skids off: little harm, little wear on the plate, a scrape and sparks. And every blow sounds
## like what it did: a chop, a slap of the flat, bone giving, a plate ringing.

var t

func _cut_on_lorica(w: TestWorld, x: float, slant: float, flat := false) -> Dictionary:
	var f := w.fighter(Vector3(x, 1.2, 0), 0.0, {"armor": ["steelLorica"]})
	var tor: VoxelPart = f.torso
	var b := tor.global_transform.basis
	var at: Vector3 = tor.global_transform * Vector3(0, 0.05, tor.half_ext.z)
	# Into the chest, leaning over toward its side by `slant` (0 square, 1 along the surface).
	var dir := (b * Vector3(slant, 0, -(1.0 - slant))).normalized()
	var edge := dir if not flat else (b * Vector3.UP).normalized()
	var ad: Dictionary = tor.get_meta("armor")[0]
	var before: int = ad.alive
	var res := f.apply_hit(tor, {"point": at, "dir": dir, "type": "edge", "hardness": 0.9, "sharpness": 0.9, "impulse": 45.0, "heavy": 0.3, "axis": (b * Vector3.UP).normalized(), "edge": edge, "weapon": true})
	res.plates = before - int(ad.alive)
	return res

func test_a_slanted_blow_skids_off_a_plate() -> void:
	var w := TestWorld.new()
	add_child(w)
	w.ready_arena()
	var square := _cut_on_lorica(w, 0.0, 0.0)
	var slant := _cut_on_lorica(w, 3.0, 0.93)
	t.check(not square.has("glance"), "a square cut bites into the lorica")
	t.check(slant.has("glance") and slant.get("glance_n") is Vector3, "one along its curve skids off it")
	t.check(float(slant.dmg) < float(square.dmg) * 0.6, "and does far less (%.1f against %.1f)" % [float(slant.dmg), float(square.dmg)])
	t.check(int(slant.plates) <= int(square.plates), "nor knocks more plates off (%d against %d)" % [slant.plates, square.plates])
	var flat := _cut_on_lorica(w, 6.0, 0.0, true)
	t.check(flat.has("glance"), "the flat of the blade on a plate skids off too")
	# A blow from a fist or a beast is not a weapon on a plate: no glance there.
	var f := w.fighter(Vector3(9, 1.2, 0), 0.0, {"armor": ["steelLorica"]})
	var b := f.torso.global_transform.basis
	var r := f.apply_hit(f.torso, {"point": f.torso.global_transform * Vector3(0, 0.05, f.torso.half_ext.z), "dir": (b * Vector3(0.93, 0, -0.07)).normalized(), "type": "blunt", "hardness": 0.5, "impulse": 20.0})
	t.check(not r.has("glance"), "a fist's knock does not glance")
	w.queue_free()

func test_blows_sound_like_what_they_did() -> void:
	var kinds := func(h: Dictionary) -> Array:
		return Match.hit_sounds(h).map(func(s): return s[0])
	t.eq(kinds.call({"type": "edge", "J": 20.0, "res": {"glance": 0.8}}), ["scrape"], "a glance scrapes")
	t.eq(kinds.call({"type": "edge", "J": 20.0, "res": {"slid": true}}), ["flat"], "the flat of a blade on flesh smacks")
	t.eq(kinds.call({"type": "edge", "J": 20.0, "res": {}}), ["chop"], "a clean cut chops in")
	t.eq(kinds.call({"type": "edge", "J": 5.0, "res": {}}), ["slash"], "a light one only slashes")
	t.check(kinds.call({"type": "edge", "J": 30.0, "res": {"bone": true}}).has("crunch"), "bone gives with a crunch")
	t.check(kinds.call({"type": "blunt", "J": 30.0, "res": {"broke": "ribs"}}).has("crunch"), "ribs too")
	var arm: Array = kinds.call({"type": "blunt", "J": 30.0, "res": {"armor": true}})
	t.check(arm.has("thud") and arm.has("clang"), "a club on a plate knocks and rings (%s)" % [arm])
	for k in ["scrape", "chop", "crunch", "flat"]:
		t.check(Match.HIT_SOUNDS.has(k) and Sfx.LENGTH.has(k), "%s is a sound a guest may play" % k)

func test_blow_sounds_are_clean_and_levelled() -> void:
	for k in Sfx.BLOWS:
		for take in 3:
			var d: PackedByteArray = Sfx._make(k, take).data
			var peak := 0
			var e := 0.0
			var steps := 0.0
			var prev := 0
			for i in d.size() / 2:
				var v := d.decode_s16(i * 2)
				peak = maxi(peak, absi(v))
				e += float(v) * v
				steps += float(v - prev) * (v - prev)
				prev = v
			t.check(peak < 26000, "%s %d stays under the ceiling (%d)" % [k, take, peak])
			t.check(steps < 1.0 * e, "%s %d has no raw-noise hiss (%.2f)" % [k, take, steps / maxf(e, 1.0)])
