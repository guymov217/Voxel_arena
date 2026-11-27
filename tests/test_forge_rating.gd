extends Node
## The rating on the forge's anvil (user: a real rating of the weapon against the arsenal): the button and when it cannot be pressed, how far the bouts have got as the other game writes it,
## what is shown when it is done (the score, the record, the place among the arsenal's) and that it is of the weapon it was made for, the rating given up on, and the one kept for a weapon that
## comes back. The bouts themselves are not fought here (test_weapon_rating's): the other game's file is written by hand.

var t

func _forge(d: Dictionary):
	var f = load("res://scripts/ui/forge.gd").new()
	add_child(f)
	f.free_build = true
	f.open(d.duplicate(true), 9999, func(_d, _c): pass)
	return f

func _find_button(n: Node, text: String) -> Button:
	if n is Button and (n as Button).text == text:
		return n
	for c in n.get_children():
		var r := _find_button(c, text)
		if r != null:
			return r
	return null

func _reset() -> void:
	load("res://scripts/ui/forge.gd").rated = {}
	WeaponRating._table = {}

## A table to rank against (the real one is in data/): three weapons at 20, 40 and 60.
func _use_a_table() -> void:
	WeaponRating._table = {"version": 1, "stamp": WeaponRating.stamp(), "presets": {"dagger": {"score": 20.0}, "mace": {"score": 40.0}, "gladius": {"score": 60.0}}}

func _write(path: String, v: Dictionary) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(v))
	f.close()

func test_the_rating_has_its_place_with_a_button_that_works_for_a_weapon() -> void:
	_reset()
	var f = _forge(Data.preset("gladius"))
	f._show_mode("voxels")
	await get_tree().process_frame
	t.check(f.rating_button != null and not f.rating_button.disabled, "Rate it can be pressed for a sword")
	t.check(not f.rating_stop.visible, "Stop is not shown while nothing is under way")
	f._show_mode("cards")
	await get_tree().process_frame
	t.check(f.rating_button != null, "it is there in the quick start too")
	f._show_mode("gallery")
	await get_tree().process_frame
	f.queue_free()
	_reset()

func test_what_cannot_be_rated_cannot_be_pressed_and_says_why() -> void:
	_reset()
	var f = _forge(Data.preset("roundShield"))
	f._show_mode("voxels")
	await get_tree().process_frame
	await get_tree().process_frame
	t.check(f.rating_button.disabled, "a shield cannot be rated")
	t.check(String(f.rating_label.text).contains("shield"), "and the place says so (%s)" % f.rating_label.text)
	f._rate_start()
	t.check(f.rating.is_empty(), "pressed anyway, nothing starts")
	f.queue_free()
	_reset()

func test_the_bouts_so_far_are_read_from_the_other_games_file() -> void:
	_reset()
	var f = _forge(Data.preset("gladius"))
	await get_tree().process_frame
	var out := ProjectSettings.globalize_path("user://rating_test_poll.json")
	f.rate_alive = func(_pid): return true   # (the other game is there: no game is started here)
	f.rating = {"key": WeaponRating.key(f._design_now()), "pid": 0, "job": "", "out": out, "state": "running", "done": 0, "of": 6, "t": 0.0, "result": {}}
	f._rating_refresh()
	t.check(f.rating_stop.visible and f.rating_button.disabled, "under way: Stop shows and Rate it waits")
	_write(out, {"state": "running", "of": 6, "bouts": [{"foe": "gladiator", "won": true, "dmg": 40.0, "taken": 5.0, "secs": 9.0, "hits": 3, "big": 20.0}, {"foe": "gladiator", "won": true, "dmg": 30.0, "taken": 8.0, "secs": 11.0, "hits": 2, "big": 18.0}]})
	f._rate_poll()
	t.eq(int(f.rating.done), 2, "two bouts fought")
	t.check(String(f.rating_label.text).contains("3") and String(f.rating_label.text).contains("6"), "the place says which bout it is on (%s)" % f.rating_label.text)
	t.eq(f.rating.state, "running", "and it is under way still")
	DirAccess.remove_absolute(out)
	f.rating = {}
	f.queue_free()
	_reset()

func test_a_finished_rating_shows_its_score_its_record_and_its_place_among_the_arsenal() -> void:
	_reset()
	_use_a_table()
	var f = _forge(Data.preset("gladius"))
	await get_tree().process_frame
	var out := ProjectSettings.globalize_path("user://rating_test_done.json")
	f.rating = {"key": WeaponRating.key(f._design_now()), "pid": 0, "job": "", "out": out, "state": "running", "done": 5, "of": 6, "t": 0.0, "result": {}}
	var bouts := []
	for i in 6:
		bouts.append({"foe": "gladiator", "won": i < 4, "dmg": 60.0, "taken": 30.0 if i < 4 else 90.0, "secs": 15.0, "hits": 5, "big": 22.0})
	_write(out, {"state": "done", "of": 6, "bouts": bouts})
	f._rate_poll()
	t.eq(f.rating.state, "done", "done")
	var text := String(f.rating_label.text)
	t.check(text.contains("Rated") and text.contains("out of 100"), "it says what it rated (%s)" % text)
	t.check(text.contains("Won 4 of 6"), "and the record (%s)" % text)
	t.check(text.contains("Better than") and text.contains("of the arsenal's 3"), "and where it stands (%s)" % text)
	t.check(f.rating_strip.visible and f.rating_strip.arsenal.size() == 3 and f.rating_strip.score > 0.0, "with the strip drawn")
	t.check(not f.rating_button.disabled and not f.rating_stop.visible, "and Rate it can be pressed again")
	t.check(not FileAccess.file_exists(out), "the other game's file is taken away")
	t.check(f.rated.has(f.rating.key), "kept for the game")
	f.queue_free()
	_reset()

func test_a_rating_is_of_the_weapon_it_was_made_for() -> void:
	_reset()
	_use_a_table()
	var f = _forge(Data.preset("gladius"))
	await get_tree().process_frame
	var out := ProjectSettings.globalize_path("user://rating_test_stale.json")
	f.rating = {"key": WeaponRating.key(f._design_now()), "pid": 0, "job": "", "out": out, "state": "running", "done": 5, "of": 6, "t": 0.0, "result": {}}
	_write(out, {"state": "done", "of": 1, "bouts": [{"foe": "gladiator", "won": true, "dmg": 60.0, "taken": 10.0, "secs": 15.0, "hits": 5, "big": 22.0}]})
	f._rate_poll()
	t.check(not String(f.rating_label.text).contains("as it was"), "for the weapon on the anvil, it says nothing of the sort")
	# The weapon is changed.
	f.mirror = false
	f.mirror_z = false
	f.mat = "gold"
	f.job = "blunt"
	f.tool = "build"
	var top: Vector3i = f.cells.keys().reduce(func(a, b): return a if a.y > b.y else b)
	f._place([top + Vector3i(0, 1, 0)])
	await get_tree().process_frame
	await get_tree().process_frame
	t.check(String(f.rating_label.text).contains("as it was"), "changed, it says the rating is of the weapon as it was (%s)" % f.rating_label.text)
	t.check(f.rating_strip.stale, "and the strip is greyed")
	f.queue_free()
	_reset()

func test_a_rating_that_stops_without_a_verdict_is_a_failure_with_a_word() -> void:
	_reset()
	var f = _forge(Data.preset("gladius"))
	await get_tree().process_frame
	f.rating = {"key": "x", "pid": 0, "job": "", "out": ProjectSettings.globalize_path("user://rating_nothing.json"), "state": "running", "done": 1, "of": 6, "t": 0.0, "result": {}}
	f._rate_poll()
	t.eq(f.rating.state, "failed", "no game, no file: failed")
	t.check(String(f.rating_label.text).contains("failed"), "and it says so (%s)" % f.rating_label.text)
	t.check(not f.rating_button.disabled, "and it can be tried again")
	f.queue_free()
	_reset()

func test_giving_up_ends_the_other_game_and_clears_the_place() -> void:
	_reset()
	var f = _forge(Data.preset("gladius"))
	await get_tree().process_frame
	var out := ProjectSettings.globalize_path("user://rating_test_stop.json")
	_write(out, {"state": "running", "bouts": []})
	f.rating = {"key": "x", "pid": 0, "job": "", "out": out, "state": "running", "done": 1, "of": 6, "t": 0.0, "result": {}}
	f._rate_stop()
	t.check(f.rating.is_empty(), "nothing is under way")
	t.check(not FileAccess.file_exists(out), "and its file is gone")
	t.check(not f.rating_stop.visible, "Stop is not shown")
	f.queue_free()
	_reset()

func test_a_weapon_rated_before_comes_back_to_the_anvil_with_its_rating() -> void:
	_reset()
	_use_a_table()
	var a = _forge(Data.preset("gladius"))
	await get_tree().process_frame
	var key: String = WeaponRating.key(a._design_now())
	a.rated[key] = {"key": key, "pid": 0, "state": "done", "done": 1, "of": 1, "result": WeaponRating.clean_result({"state": "done", "bouts": [{"foe": "gladiator", "won": true, "dmg": 50.0, "taken": 10.0, "secs": 12.0, "hits": 4, "big": 20.0}]})}
	a.queue_free()
	await get_tree().process_frame
	var b = _forge(Data.preset("gladius"))
	await get_tree().process_frame
	await get_tree().process_frame
	t.check(String(b.rating_label.text).contains("Rated"), "the same weapon on a new forge shows it (%s)" % b.rating_label.text)
	b.queue_free()
	var c = _forge(Data.preset("axe"))
	await get_tree().process_frame
	await get_tree().process_frame
	t.check(not String(c.rating_label.text).contains("Rated"), "another weapon does not")
	c.queue_free()
	_reset()
