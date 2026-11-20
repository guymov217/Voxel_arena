extends Node
## `-- --probe licenses_dump`, with LICENSES_OUT=<file>: writes THIRD_PARTY_LICENSES.txt, the whole of the credits
## (scripts/game/credits.gd). tools/package.py runs it with the Godot it exports with, so the file carries the licence
## terms of that very engine, and puts the file into every package.

func _ready() -> void:
	var out := OS.get_environment("LICENSES_OUT")
	if out == "":
		push_error("licenses_dump: LICENSES_OUT is not set")
		get_tree().quit(2)
		return
	var f := FileAccess.open(out, FileAccess.WRITE)
	if f == null:
		push_error("licenses_dump: cannot write %s" % out)
		get_tree().quit(2)
		return
	f.store_string(Credits.full_text())
	f.close()
	print("LICENSES ", out)
	get_tree().quit(0)
