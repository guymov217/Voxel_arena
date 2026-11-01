extends Node
## The blow sounds written out as WAV files to SHOT_DIR (`-- --probe sfxexport`), to be listened
## to and measured (how much of each lies under 40 Hz, how much of its low end is noise).

func _ready() -> void:
	var out := OS.get_environment("SHOT_DIR")
	var old = load("res://tests/sfx_old.gd").new() if FileAccess.file_exists("res://tests/sfx_old.gd") else null
	for kind in ["boom", "thud", "crunch", "chop", "stab", "thump"]:
		for take in [1, 2]:
			var st = Sfx._make(kind, take)
			if st == null:
				continue
			(st as AudioStreamWAV).save_to_wav(out.path_join("%s_%d.wav" % [kind, take]))
			print("saved %s_%d" % [kind, take])
			if old:
				(old._make(kind, take) as AudioStreamWAV).save_to_wav(out.path_join("old_%s_%d.wav" % [kind, take]))
	get_tree().quit()
