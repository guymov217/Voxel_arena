extends Node
## How many foes the campaign puts against a party (`-- --probe foecount`): per stage, the first wave and the second, for 1 to 4 players.
func _ready() -> void:
	var worst := 0
	for n in range(1, 65):
		var row := "%2d" % n
		var title := ""
		var over := false
		for p in range(1, 5):
			var st: Dictionary = Data.stage(n, p)
			var first := ((st.get("rounds", [[]]) as Array)[0] as Array).size() if not (st.get("rounds", []) as Array).is_empty() else 0
			var late := (st.get("late", []) as Array).size()
			row += "  %dp: %d+%d" % [p, first, late]
			if p == 4 and first + late > worst:
				worst = first + late
			if first + late > 6:
				over = true
			title = String(st.get("title", ""))
		print("FOES %s%s  %s" % [row, "  >6" if over else "", title])
	print("FOES worst total for 4 players: %d" % worst)
	get_tree().quit()
