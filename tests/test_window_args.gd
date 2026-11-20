extends Node
## `-- --keep-window` (the multiplayer test's windows, started with `--position 40,60 --resolution 1100x650`): the window
## stays as the engine's flags made it instead of the saved full-screen one. Two full-screen windows at 1440p on one
## graphics card left the one behind 17 frames a second (measured from a test video).

var t

const MenuScript := preload("res://scripts/ui/menu.gd")

func test_the_flag_that_keeps_the_window() -> void:
	t.check(MenuScript.window_asked(["--host", "--name", "Host", "--keep-window"]), "the flag, among the game's own")
	t.check(MenuScript.window_asked(["--keep-window"]), "alone")

func test_nothing_else_does() -> void:
	t.check(not MenuScript.window_asked([]), "no arguments: the saved display mode")
	t.check(not MenuScript.window_asked(["--host", "--name", "Host"]), "the game's other flags")
	t.check(not MenuScript.window_asked(["--probe", "winprobe"]), "a probe")
	t.check(not MenuScript.window_asked(["--keep"]), "half of it")
