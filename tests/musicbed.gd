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
	print("REC_START ", Engine.get_frames_drawn())
	for i in int(seconds * 30.0):
		await get_tree().process_frame
	print("REC_END ", Engine.get_frames_drawn())
	get_tree().quit()
