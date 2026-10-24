extends Node
## The game's own music, for the trailer's sound (`-- --probe musicbed`, run with the movie maker
## on: only its .wav is used). Nothing is drawn; the band plays the boss fight for MUSIC_SECONDS.

func _ready() -> void:
	get_viewport().disable_3d = true
	var seconds := float(OS.get_environment("MUSIC_SECONDS")) if OS.get_environment("MUSIC_SECONDS") != "" else 45.0
	for i in 10:
		await get_tree().process_frame
	if Sfx.music:
		Sfx.music.set_state(OS.get_environment("MUSIC_STATE") if OS.get_environment("MUSIC_STATE") != "" else "boss")
	_tag("REC_START %d" % Engine.get_frames_drawn())
	for i in int(seconds * 30.0):
		await get_tree().process_frame
	_tag("REC_END %d" % Engine.get_frames_drawn())
	get_tree().quit()

## Each timing tag goes to stdout and, when TAG_LOG names a file, there too: the window build of
## Godot on Windows (not the *_console.exe) prints nothing to a pipe, and the trailer kit reads
## the shots' frames from these lines.
var _tags := PackedStringArray()
func _tag(line: String) -> void:
	print(line)
	var path := OS.get_environment("TAG_LOG")
	if path == "":
		return
	_tags.append(line)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string("\n".join(_tags) + "\n")
