extends RefCounted
## What the end-to-end multiplayer run's scripts share (tests/e2e_run.gd starts a host, a guest and a late guest, each its own game;
## e2e_host.gd and e2e_guest.gd are what they do). Each game writes what it saw to a file of its own in user://e2e/, line by line:
##   RESULT <ok|FAIL> <id> <what was checked> <what was seen>
##   CUE <phase>      (the host: this phase begins, guests may look at it)
##   DONE <phase>     (a guest: I have looked at it)
## The games wait for each other by reading those files (they are on one computer), so nothing of the test is in the game's own
## messages; the runner reads the same files to show the run as it goes and to write its report.

var role := ""
var node: Node
var passes := 0
var fails := 0
var _dir := ""
var _shots := ""

func _init(role_: String, node_: Node) -> void:
	role = role_
	node = node_
	_dir = ProjectSettings.globalize_path("user://e2e")
	DirAccess.make_dir_recursive_absolute(_dir)
	var f := FileAccess.open(_path(role), FileAccess.WRITE)   # (this game's file starts empty)
	if f:
		f.close()
	_shots = OS.get_environment("E2E_SHOTS")
	if _shots != "":
		DirAccess.make_dir_recursive_absolute(_shots)

func _path(who: String) -> String:
	return "%s/%s.txt" % [_dir, who]

func _append(line: String) -> void:
	var f := FileAccess.open(_path(role), FileAccess.READ_WRITE)
	if f == null:
		f = FileAccess.open(_path(role), FileAccess.WRITE)
	if f == null:
		return
	f.seek_end()
	f.store_line(line)
	f.close()

## One thing seen: written to this game's file and printed.
func check(id: String, ok: bool, what: String, seen := "") -> bool:
	if ok:
		passes += 1
	else:
		fails += 1
	var clean := seen.replace("\t", " ").replace("\n", " ").left(300)
	_append("RESULT\t%s\t%s\t%s\t%s" % ["ok" if ok else "FAIL", id, what, clean])
	print("E2E %s %s %s: %s %s" % [role, "ok  " if ok else "FAIL", id, what, clean])
	return ok

func cue(phase: String) -> void:
	_append("CUE\t" + phase)

func done(phase: String) -> void:
	_append("DONE\t" + phase)

func lines_of(who: String) -> PackedStringArray:
	if not FileAccess.file_exists(_path(who)):
		return PackedStringArray()
	return FileAccess.get_file_as_string(_path(who)).split("\n", false)

func has_line(who: String, kind: String, phase: String) -> bool:
	var want := "%s\t%s" % [kind, phase]
	for l in lines_of(who):
		if l == want:
			return true
	return false

## Frames until another game has written the line (or `secs` pass).
func wait_line(who: String, kind: String, phase: String, secs: float) -> bool:
	var t0 := Time.get_ticks_msec()
	while not has_line(who, kind, phase):
		await node.get_tree().create_timer(0.15).timeout
		if Time.get_ticks_msec() - t0 > int(secs * 1000.0):
			print("E2E %s timed out waiting for %s %s of %s" % [role, kind, phase, who])
			return false
	return true

## Frames until `cond` holds (or `secs` pass).
func until(cond: Callable, secs: float, what: String) -> bool:
	var t0 := Time.get_ticks_msec()
	while not cond.call():
		await node.get_tree().process_frame
		if Time.get_ticks_msec() - t0 > int(secs * 1000.0):
			print("E2E %s timed out waiting for %s" % [role, what])
			return false
	return true

func pause(secs: float) -> void:
	await node.get_tree().create_timer(secs).timeout

# ---------- The game's own screens, as a player meets them ----------

## A button on the screen (visible, as a player could press it) by its name.
static func button_named(root: Node, button_name: String) -> Button:
	var b = root.find_child(button_name, true, false)
	return b if b is Button and (b as Button).is_visible_in_tree() else null

## All that is written on a button: its own words and, for a card (a button with labels laid in it), theirs.
static func words_of(b: Button) -> String:
	var out := PackedStringArray([String(b.text)])
	for l in b.find_children("*", "Label", true, false):
		out.append(String((l as Label).text))
	return " ".join(out)

## A button on the screen by what is written on it (capitals or not: the title screen's plates are in capitals).
static func button_with(root: Node, text: String) -> Button:
	var want := text.to_upper()
	for b in root.find_children("*", "Button", true, false):
		if (b as Button).is_visible_in_tree() and words_of(b).to_upper().contains(want):
			return b
	return null

## A button on the screen whose words begin so (the pause menu's "The room" and its "The Arena: pick a fight for the room" both have the words).
static func button_starting(root: Node, text: String) -> Button:
	var want := text.to_upper()
	for b in root.find_children("*", "Button", true, false):
		if (b as Button).is_visible_in_tree() and String((b as Button).text).strip_edges().to_upper().begins_with(want):
			return b
	return null

## Press it as a player would (a disabled button cannot be pressed). False when there is none.
static func press(b: Button) -> bool:
	if b == null or b.disabled:
		return false
	b.pressed.emit()
	return true

## A picture of this game's window, when the run is asked for them (E2E_SHOTS=folder) and there is a window.
func shot(name: String) -> void:
	if _shots == "" or DisplayServer.get_name() == "headless":
		return
	await node.get_tree().process_frame
	await node.get_tree().process_frame
	node.get_viewport().get_texture().get_image().save_png("%s/%s_%s.png" % [_shots, role, name])
