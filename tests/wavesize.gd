extends Node
## How many foes the endless arena brings a wave of a party (`-- --probe wavesize`): the wave's foes by wave, for 1, 4 and 8 players.
func _ready() -> void:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "endless", "role": "host", "headless": true, "seed": 3, "decrees": [], "hazards": [], "loadout": {"main": "gladius", "off": ""}})
	var en: Endless = m.modes.endless
	for w in range(1, 21):
		var row := "WAVES %2d" % w
		for p in [1, 4, 8]:
			var l: Array = en.plan(w, p)
			var beasts := l.filter(func(x): return x.has("beast")).size()
			row += "   %dp: %d foes (%d beasts)" % [p, l.size(), beasts]
		print(row)
	get_tree().quit()
