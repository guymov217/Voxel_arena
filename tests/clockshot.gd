extends Node
## The contest's clock as it is drawn (`-- --probe clockshot`, with a renderer: Xvfb and lavapipe where there is no card). VARIANT=old draws it as it was (a label with no width stood a
## letter to a line), new as UIStyle.clock_pill makes it. SHOT=<path>.png.
func _ready() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var bg := ColorRect.new()
	bg.color = Color(0.18, 0.12, 0.09)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(bg)
	# (A stand-in for the forge's own top bar, the button the old clock sat over.)
	var bar := Button.new()
	bar.text = "BUILD"
	bar.position = Vector2(500, 24)
	bar.custom_minimum_size = Vector2(110, 44)
	layer.add_child(bar)
	var clock: Label
	if OS.get_environment("VARIANT") == "old":
		clock = UIStyle.label("", 30, UIStyle.GOLD_LIGHT)
		clock.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
		clock.position.y = 8
		clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	else:
		clock = UIStyle.clock_pill()
	layer.add_child(clock)
	clock.visible = true
	clock.text = "Weapons  1:37"
	for i in 6:
		await get_tree().process_frame
	var r := clock.get_global_rect()
	print("CLOCKSHOT rect %s size %s (the screen %s)" % [str(r.position), str(r.size), str(get_viewport().get_visible_rect().size)])
	get_viewport().get_texture().get_image().save_png(OS.get_environment("SHOT"))
	get_tree().quit()
