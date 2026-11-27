extends Node
## A weapon's rating (user, forge: a real rating of a weapon by duels, ranked among the arsenal's own): the battery and what it is made of, the scores, the place among the arsenal's, what the files
## between the forge and the game that fights the bouts carry (and survive of a hostile one), the runner's bouts, and the game itself started for a bout.

var t

func _table() -> Dictionary:
	return {"version": 1, "stamp": "x", "presets": {"a": {"score": 20.0}, "b": {"score": 40.0}, "c": {"score": 60.0}}}

func test_the_battery_is_every_foe_for_so_many_bouts_each_with_a_seed_of_its_own() -> void:
	var bat := WeaponRating.battery()
	t.eq(bat.size(), WeaponRating.FOES.size() * WeaponRating.BOUTS_PER_FOE, "a few bouts for each foe")
	var seeds := {}
	for b in bat:
		seeds[b.seed] = true
	t.eq(seeds.size(), bat.size(), "each bout has a seed of its own")
	for foe in WeaponRating.FOES:
		t.check(not Data.preset(String(foe.main)).is_empty(), "%s: a weapon the game knows" % foe.key)
		t.check(String(foe.off) == "" or not Data.preset(String(foe.off)).is_empty(), "%s: and a shield" % foe.key)
		for a in foe.armor:
			t.check(Data.armor.has(String(a)), "%s: armour the game has (%s)" % [foe.key, a])
	t.check(WeaponRating.stamp().begins_with("%d-" % WeaponRating.VERSION), "the stamp names the version")

func test_a_bout_scores_by_the_result_and_the_share_of_the_harm_done() -> void:
	t.check(is_equal_approx(WeaponRating.bout_score({"won": true, "dmg": 100.0, "taken": 0.0}), 100.0), "won with no harm taken: the most")
	t.check(is_equal_approx(WeaponRating.bout_score({"won": false, "dmg": 0.0, "taken": 80.0}), 0.0), "lost and no harm done: nothing")
	t.check(is_equal_approx(WeaponRating.bout_score({"draw": true, "dmg": 50.0, "taken": 50.0}), 50.0), "a draw and an even share: half")
	t.check(is_equal_approx(WeaponRating.bout_score({"won": false, "dmg": 0.0, "taken": 0.0}), 100.0 * WeaponRating.W_SHARE * 0.5), "no blow struck by either: the share is even")
	var win := WeaponRating.bout_score({"won": true, "dmg": 60.0, "taken": 40.0})
	var loss := WeaponRating.bout_score({"won": false, "dmg": 60.0, "taken": 40.0})
	t.check(win > loss, "a win scores over a loss of the same share")
	t.check(WeaponRating.bout_score({"won": false, "dmg": 90.0, "taken": 10.0}) > WeaponRating.bout_score({"won": false, "dmg": 10.0, "taken": 90.0}), "a loss that hurt him more than it hurt me scores over one that did not")

func test_a_weapons_score_is_the_mean_of_its_bouts_and_its_record_counts_the_wins() -> void:
	var bouts := [{"won": true, "dmg": 100.0, "taken": 0.0, "hits": 5, "big": 30.0, "secs": 10.0}, {"won": false, "dmg": 0.0, "taken": 100.0, "hits": 0, "big": 0.0, "secs": 40.0}, {"draw": true, "dmg": 10.0, "taken": 10.0, "hits": 2, "big": 8.0, "secs": 40.0}]
	t.check(is_equal_approx(WeaponRating.score(bouts), (100.0 + 0.0 + 50.0) / 3.0), "the mean of the three")
	t.eq(WeaponRating.score([]), 0.0, "no bouts, no score")
	var rec := WeaponRating.record(bouts)
	t.check(is_equal_approx(float(rec.won), 1.5) and rec.of == 3, "a win and half a draw of three")
	var sm := WeaponRating.summary(bouts)
	t.eq(sm.hits, 7, "its hits are summed")
	t.eq(sm.big, 30, "its best blow is the best")
	t.eq(sm.dmg, 110, "its harm done")
	t.eq(sm.taken, 110, "and taken")

func test_a_score_has_its_place_among_the_arsenals() -> void:
	var tab := _table()
	var r := WeaponRating.rank(50.0, tab)
	t.eq(r.better, 2, "50 beats two of three")
	t.eq(r.of, 3, "of three")
	t.eq(r.rank, 2, "second")
	t.eq(r.below, "b", "the best it beats is b")
	t.eq(r.above, "c", "the weakest that beats it is c")
	r = WeaponRating.rank(10.0, tab)
	t.check(r.better == 0 and r.rank == 4 and r.below == "" and r.above == "a", "under them all: last of four with them")
	r = WeaponRating.rank(75.0, tab)
	t.check(r.better == 3 and r.rank == 1 and r.above == "" and r.below == "c", "over them all")
	r = WeaponRating.rank(40.0, tab)
	t.check(r.better == 2 and r.below == "b", "level with one is not under it")
	t.check(WeaponRating.rank(50.0, {"presets": {}}).is_empty(), "an empty table gives no place")
	t.eq(WeaponRating.scores(tab), [20.0, 40.0, 60.0], "the arsenal's scores in order")

func test_a_design_is_known_by_what_it_is_however_it_is_listed() -> void:
	var d := Data.preset("gladius").duplicate(true)
	var k0 := WeaponRating.key(d)
	var shuffled := d.duplicate(true)
	(shuffled.voxels as Array).reverse()
	t.eq(WeaponRating.key(shuffled), k0, "the blocks listed the other way round: the same weapon")
	var other := d.duplicate(true)
	other.voxels[3] = [other.voxels[3][0], other.voxels[3][1], other.voxels[3][2], "gold", other.voxels[3][4]]
	t.check(WeaponRating.key(other) != k0, "one block of another stuff: another weapon")
	var honed := d.duplicate(true)
	honed.sharpness = 0.3
	t.check(WeaponRating.key(honed) != k0, "honed another way: another weapon")
	var held := d.duplicate(true)
	held.twoHanded = true
	t.check(WeaponRating.key(held) != k0, "held in two hands: another weapon")
	t.eq(WeaponRating.key(d.duplicate(true)), k0, "a copy is the same")

func test_what_cannot_be_rated_says_why() -> void:
	t.eq(WeaponRating.unrateable(Data.preset("gladius")), "", "a sword can")
	t.eq(WeaponRating.unrateable(Data.preset("warhammer")), "", "so can a hammer")
	t.check(WeaponRating.unrateable(Data.preset("roundShield")) != "", "a shield cannot")
	t.check(WeaponRating.unrateable(Data.preset("crossbow")) != "", "nor a crossbow")
	t.check(WeaponRating.unrateable({"voxels": []}) != "", "nor a blank anvil")
	var bald := {"name": "x", "kind": "weapon", "voxels": [[0, 0, 0, "iron", "blunt"], [0, 1, 0, "iron", "blunt"]]}
	t.check(WeaponRating.unrateable(bald) != "", "nor a weapon with nowhere to hold it")

func test_a_result_file_is_taken_as_it_is_only_where_it_is_sensible() -> void:
	t.eq(WeaponRating.clean_result("nonsense").state, "running", "what is not a verdict is no verdict")
	t.eq(WeaponRating.clean_result(null).bouts, [], "nothing at all: no bouts")
	var r := WeaponRating.clean_result({"state": "done", "of": 6, "bouts": [{"foe": "gladiator", "won": true, "dmg": 50.0, "taken": 20.0, "secs": 12.0, "hits": 4, "big": 20.0}, "junk", {"foe": "x", "won": "yes", "dmg": 1e30, "taken": -5.0, "secs": INF, "hits": "many", "big": NAN}]})
	t.eq(r.state, "done", "a verdict")
	t.eq(r.bouts.size(), 2, "the bout that is not one is dropped")
	t.check(r.bouts[1].won == false, "a 'yes' is not a win")
	t.check(float(r.bouts[1].dmg) <= WeaponRating.NUM_MAX and float(r.bouts[1].taken) == 0.0, "figures kept within the sensible")
	t.check(is_finite(float(r.bouts[1].secs)) and is_finite(float(r.bouts[1].big)), "and finite")
	t.check(r.has("summary") and r.summary.of == 2, "a summary of the bouts there are")
	t.eq(WeaponRating.clean_result({"state": "weird"}).state, "running", "an unknown state is the running one")
	var many := []
	for i in 200:
		many.append({"foe": "g", "won": true})
	t.check(WeaponRating.clean_result({"state": "running", "bouts": many}).bouts.size() <= WeaponRating.MAX_BOUTS, "no more bouts than the wire allows")
	t.check(WeaponRating.clean_result({"error": "x".repeat(1000)}).error.length() <= 160, "an error is a line")

func test_the_arsenals_table_was_made_with_this_battery_and_has_every_weapon_that_can_be_rated() -> void:
	var tab := WeaponRating.table()
	t.check(not tab.is_empty(), "a table of the arsenal's ratings (tools/rate_presets.sh makes it)")
	if tab.is_empty():
		return
	t.eq(str(tab.get("stamp")), WeaponRating.stamp(), "made with this battery: if the battery changed, make it again (tools/rate_presets.sh)")
	var missing := []
	for k in Data.presets:
		if WeaponRating.unrateable(Data.preset(k)) == "" and not (tab.presets as Dictionary).has(k):
			missing.append(k)
	t.check(missing.is_empty(), "every weapon that can be rated is in it (missing: %s)" % ", ".join(missing))
	for k in tab.presets:
		var sc := float(tab.presets[k].score)
		t.check(sc >= 0.0 and sc <= 100.0, "%s: a score on the scale (%.1f)" % [k, sc])

func test_a_rating_job_for_a_bad_weapon_is_refused_not_fought() -> void:
	var path := ProjectSettings.globalize_path("user://rating_test_bad.json")
	var r := RatingRunner.new()
	add_child(r)
	r.out_path = path
	r.job = {"design": {"voxels": "nonsense"}}
	await r._run_design()
	var res := WeaponRating.clean_result(JSON.parse_string(FileAccess.get_file_as_string(path)))
	t.eq(res.state, "failed", "refused")
	t.check(res.error != "", "with a word")
	DirAccess.remove_absolute(path)
	r.queue_free()

func test_the_runner_fights_a_bout_and_writes_how_far_it_has_got() -> void:
	var path := ProjectSettings.globalize_path("user://rating_test_out.json")
	var r := RatingRunner.new()
	add_child(r)
	r.out_path = path
	r.started_ms = Time.get_ticks_msec()
	r.job = {"design": Data.preset("gladius"), "bouts": 1, "secs": 3.0}
	await r._run_design()
	var res := WeaponRating.clean_result(JSON.parse_string(FileAccess.get_file_as_string(path)))
	t.eq(res.state, "done", "done")
	t.eq(res.bouts.size(), 1, "the one bout asked for")
	var b: Dictionary = res.bouts[0]
	t.eq(b.foe, "gladiator", "against the first foe")
	t.check(float(b.secs) > 0.0 and float(b.secs) <= 3.1, "for as long as it was given (%.1f s)" % float(b.secs))
	t.check(res.has("summary") and float(res.summary.score) >= 0.0 and float(res.summary.score) <= 100.0, "and a score")
	DirAccess.remove_absolute(path)
	r.queue_free()

## The game itself, started as the forge starts it, for one short bout: the whole way from a job file to a verdict.
func test_the_game_started_for_a_rating_brings_back_a_verdict() -> void:
	var dir := ProjectSettings.globalize_path("user://rating")
	DirAccess.make_dir_recursive_absolute(dir)
	var job_path := dir.path_join("job_test.json")
	var out_path := dir.path_join("out_test.json")
	DirAccess.remove_absolute(out_path)
	var f := FileAccess.open(job_path, FileAccess.WRITE)
	f.store_string(JSON.stringify({"design": Data.preset("axe"), "out": out_path, "bouts": 1, "secs": 2.0}))
	f.close()
	var args := PackedStringArray(["--headless", "--fixed-fps", "120", "--path", ProjectSettings.globalize_path("res://"), "--", "--rate", job_path])
	var pid := OS.create_process(OS.get_executable_path(), args)
	t.check(pid > 0, "the game started")
	var t0 := Time.get_ticks_msec()
	var state := ""
	while pid > 0 and Time.get_ticks_msec() - t0 < 90000:
		await get_tree().process_frame
		OS.delay_msec(100)
		if FileAccess.file_exists(out_path):
			state = WeaponRating.clean_result(JSON.parse_string(FileAccess.get_file_as_string(out_path))).state
			if state == "done" or state == "failed":
				break
	t.eq(state, "done", "it fought its bout and said so (%d s)" % int((Time.get_ticks_msec() - t0) / 1000))
	if pid > 0 and OS.is_process_running(pid):
		OS.kill(pid)
	DirAccess.remove_absolute(job_path)
	DirAccess.remove_absolute(out_path)
