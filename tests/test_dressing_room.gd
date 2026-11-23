extends Node
## The dressing room's man (ArmourStage, MenuMan: the armourer's, the physician's and the bench's view of the player's gladiator) is made over the
## frames that follow, out of the world until whole, and a piece put on or taken off while he is being made is made when he is whole, not beside
## him: a man in one frame was a stop of a tenth of a second to a third at every click, and in a room the whole room's.

var t

func _until(cond: Callable, most := 1500) -> int:
	for i in most:
		if cond.call():
			return i
		await get_tree().process_frame
	return 0 if cond.call() else -1

## How much is drawn on him: the meshes of his plates and shells (more armour, more of them).
static func _drawn(f: Fighter) -> int:
	return f.find_children("*", "MultiMeshInstance3D", true, false).size() + f.find_children("*", "MeshInstance3D", true, false).size()

func test_the_man_is_made_over_the_frames_and_the_last_asked_for_stands() -> void:
	MenuMan.staged_always = true
	var s := ArmourStage.make("")
	add_child(s.frame)
	add_child(s)
	s.dress(["helmet"])
	t.check(s.man == null, "he is not there in the frame he is asked for")
	var took := await _until(func(): return s.man != null)
	t.check(took > 3, "he is made over the frames that follow (%d)" % took)
	var man: Fighter = s.man
	t.check(man.visible and man.parts.size() >= 10, "a whole man (%d parts)" % man.parts.size())
	t.check(man.parts.all(func(p): return p.freeze and p.collision_layer == 0), "held still, touching nothing")
	var with_helmet := _drawn(man)
	# Armour asked for three times in a row: the last stands, one man made at a time, one man on the stand.
	s.dress(["helmet", "lorica", "greaves"])
	s.dress(["lorica"])
	s.dress(["helmet", "lorica", "greaves", "manica"])
	var done := await _until(func(): return not s._busy and s.man != man)
	t.check(done >= 0, "the man stands when the last is made (%d)" % done)
	t.eq(s.ids, ["helmet", "lorica", "greaves", "manica"], "dressed as the last asked for")
	t.check(_drawn(s.man) > with_helmet, "with more on him than the helmet alone (%d against %d)" % [_drawn(s.man), with_helmet])
	await get_tree().process_frame
	await get_tree().process_frame
	t.eq(s.stage.pivot.find_children("*", "Fighter", true, false).filter(func(f): return is_instance_valid(f) and not f.is_queued_for_deletion()).size(), 1, "one man on the stand")
	MenuMan.staged_always = false
	s.queue_free()
	s.frame.queue_free()
	await get_tree().process_frame
