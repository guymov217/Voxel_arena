extends Node
## Renders every piece of the music (`-- --probe musicprobe`), times it and, with MUSIC_OUT set,
## writes each loop to a WAV there (twice round, to hear the seam) to listen to.

func _ready() -> void:
	var out := OS.get_environment("MUSIC_OUT")
	var only := OS.get_environment("MUSIC_ONLY")
	for s in Music.STATES:
		if only != "" and not (only.split(",") as Array).has(s):
			continue
		var t0 := Time.get_ticks_msec()
		var w := Music.render(s)
		var ms := Time.get_ticks_msec() - t0
		var peak := 0
		var sumsq := 0.0
		var n := w.data.size() / 2
		for i in range(0, n, 7):
			var v := w.data.decode_s16(i * 2)
			peak = maxi(peak, absi(v))
			sumsq += float(v) * v
		var rms := sqrt(sumsq / maxf(1.0, n / 7.0))
		print("MUSIC %s %.1f s rendered in %d ms, peak %d, rms %d" % [s, n / float(Music.RATE), ms, peak, int(rms)])
		if out != "":
			var w2 := AudioStreamWAV.new()
			w2.format = w.format
			w2.mix_rate = w.mix_rate
			w2.data = w.data + w.data if w.loop_mode == AudioStreamWAV.LOOP_FORWARD else w.data
			w2.save_to_wav(out.path_join(s + ".wav"))
	get_tree().quit(0)
