extends Node
## The forge's toolbar after the clear-out on screen (`-- --probe forgeshots3`, needs a display): the build tool, the select tool with nothing and with a pick, the hand tool of a two-handed weapon, the open
## pull-downs (mirror, more, turn), quick start and My designs, saved to SHOT_DIR (forge3_<name>.png). FS_LANG: a language code (Loc.LANGS).

func _shot(name_: String) -> void:
	for i in 10:
		await get_tree().process_frame
	RenderingServer.render_loop_enabled = true
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OS.get_environment("SHOT_DIR").path_join("forge3_%s.png" % name_))
	RenderingServer.render_loop_enabled = false
	print("saved ", name_)

func _ready() -> void:
	if OS.get_environment("FS_LANG") != "":
		Loc.apply(OS.get_environment("FS_LANG"))
	var F = load("res://scripts/ui/forge.gd")
	F.pinned = {}
	var f = F.new()
	add_child(f)
	f.free_build = true
	f.open(Data.preset("gladius").duplicate(true), 0, func(_d, _c): pass)
	f._show_mode("voxels")
	await _shot("build")
	var ob: OptionButton = f.tool_bar.find_children("*", "OptionButton", true, false)[0]
	ob.show_popup()
	await _shot("mirror_open")
	ob.get_popup().hide()
	var more: MenuButton = f.tool_bar.find_children("*", "MenuButton", true, false)[0]
	more.get_popup().position = Vector2i(more.get_screen_position() + Vector2(0, more.size.y))
	more.show_popup()
	await _shot("more_open")
	more.get_popup().hide()
	f.tool = "select"
	f._toolbar_ui()
	await _shot("select_none")
	var top := -100
	for k in f.cells:
		top = maxi(top, k.y)
	var pick := {}
	for k in f.cells:
		if k.y >= top - 10 and String(f.cells[k][1]) != "grip":
			pick[k] = true
	f._set_sel(pick)
	await _shot("select")
	await get_tree().process_frame
	var turn: MenuButton = null
	for b in f.tool_bar.find_children("*", "MenuButton", true, false):
		if String(b.text).begins_with(Loc.t("Turn")):
			turn = b
	if turn:
		turn.show_popup()
		await _shot("turn_open")
		turn.get_popup().hide()
	f.queue_free()
	await get_tree().process_frame
	var g = F.new()
	add_child(g)
	g.free_build = true
	g.open(Data.preset("longsword").duplicate(true), 0, func(_d, _c): pass)
	g._show_mode("voxels")
	g.tool = "hand"
	g._toolbar_ui()
	await _shot("hand")
	g._show_mode("cards")
	await _shot("cards")
	g._show_mode("gallery")
	await _shot("gallery")
	get_tree().quit()
