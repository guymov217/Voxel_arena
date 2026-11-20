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
		# (A trailer is filmed in the game's own look, whatever this PC's player picked in his
		# Options: the classic blocks on low graphics filmed old men into the new trailer, user.)
		if OS.get_environment("FORCE_LOOK") != "":
			Physique.forced = OS.get_environment("FORCE_LOOK")
		var probe = load("res://tests/%s.gd" % (args[args.find("--probe") + 1] if args.size() > args.find("--probe") + 1 else "probe")).new()
		add_child(probe)
		return
	# The player's language (Options, else the system's): the tests and probes above stay in the
	# game's own English.
	Loc.apply()
	# A player's start opens with the boot splash's picture brought to life (scripts/ui/intro.gd). The menu is
	# built when it has played, behind its last still frame, which hides the stall the build makes; the tests,
	# the probes (above) and headless runs go straight on.
	var intro_script = load("res://scripts/ui/intro.gd")
	if intro_script.wanted(args):
		var intro = intro_script.new()
		add_child(intro)
		await intro.covered
	var menu = load("res://scripts/ui/menu.gd").new()
	add_child(menu)
