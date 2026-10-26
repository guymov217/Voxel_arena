extends Node
## A small test runner: every `test_*` method of every script in res://tests/test_*.gd runs in
## turn (they may await physics frames); the process exits 0 when all pass.

var failures := 0
var passed := 0
var current := ""

func run(only: String) -> void:
	var dir := DirAccess.open("res://tests")
	var files := []
	for f in dir.get_files():
		if f.begins_with("test_") and f.ends_with(".gd"):
			files.append(f)
	files.sort()
	for f in files:
		if only != "" and not (only.split(",") as Array).any(func(o): return f.contains(o)):
			continue
		var suite = load("res://tests/" + f).new()
		suite.set("t", self)
		add_child(suite)
		for m in suite.get_method_list():
			var n: String = m.name
			if not n.begins_with("test_"):
				continue
			current = "%s.%s" % [f.get_basename(), n]
			Save.reset()
			# Each test draws the same random numbers every run (Godot seeds its generator afresh
			# at start-up): a blow's chips, a bot's whims and a wound's wander are the same each
			# time, so a test passes or fails the same way, and a failure can be run again.
			seed(hash(current))
			var before := failures
			var start := Time.get_ticks_msec()
			await suite.call(n)
			var ok := failures == before
			if ok:
				passed += 1
			print("%s %s (%d ms)" % ["ok  " if ok else "FAIL", current, Time.get_ticks_msec() - start])
			# What a test left behind (a world it did not free, its fighters, debris) goes before
			# the next one starts: left standing where the next one builds, its bodies struck
			# the next test's and made its results hang on which tests ran before it.
			for c in suite.get_children():
				c.queue_free()
			await get_tree().process_frame
			await get_tree().physics_frame
		suite.queue_free()
		await get_tree().process_frame
	print("\n%d passed, %d failed" % [passed, failures])
	get_tree().quit(1 if failures else 0)

func check(cond: bool, what: String) -> bool:
	if not cond:
		failures += 1
		print("   - %s: %s" % [current, what])
	return cond

func eq(a, b, what: String) -> bool:
	return check(a == b, "%s (got %s, want %s)" % [what, str(a), str(b)])
