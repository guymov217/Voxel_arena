extends Node
## Probe: every made-on-the-fly sound (each take) written out as a WAV to SND_DIR, to be checked
## for clipping, clicks and hiss (tools/sound_audit.py).

func _ready() -> void:
	var out := OS.get_environment("SND_DIR")
	var kinds: Array = Sfx.LENGTH.keys()
	for k in ["slash", "stab", "thud"]:
		if not kinds.has(k):
			kinds.append(k)
	for k in kinds:
		for take in Sfx.TAKES:
			var w: AudioStreamWAV = Sfx._make(k, take)
			w.save_to_wav(out.path_join("%s_%d.wav" % [k, take]))
	Sfx._murmur().save_to_wav(out.path_join("murmur_0.wav"))
	print("dumped %d kinds" % kinds.size())
	get_tree().quit()
