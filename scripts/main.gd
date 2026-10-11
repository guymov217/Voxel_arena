extends Node
## Entry point: the menu, or the test suite (`godot --headless --path godot -- --test [name]`).

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.has("--test"):
		var runner = load("res://tests/runner.gd").new()
		add_child(runner)
		var i := args.find("--test")
		runner.run(args[i + 1] if args.size() > i + 1 else "")
		return
	if args.has("--probe"):
		var probe = load("res://tests/%s.gd" % (args[args.find("--probe") + 1] if args.size() > args.find("--probe") + 1 else "probe")).new()
		add_child(probe)
		return
	var menu = load("res://scripts/ui/menu.gd").new()
	add_child(menu)
