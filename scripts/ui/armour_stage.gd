class_name ArmourStage
extends Node
## The dressing room's view: the player's gladiator, in the new look, turning slowly on his
## plinth in whatever armour is put on him (MenuMan). He is built a moment after the screen is
## drawn, and again each time what he wears changes (a fresh man is a work of a moment, so it is
## done on a click, never while a slider is dragged).

const MAN_BOX := AABB(Vector3(-0.45, 0.0, -0.3), Vector3(0.9, 1.85, 0.6))

var stage: Stage3D
var frame: Control
var ids: Array = []
var body: Dictionary = {}   # his wounds, lost limbs and eyes (the physician's view); empty: whole
var man: Fighter = null     # the man now standing on it
var _token := 0
var spin := 0.35
var _wait: Label
var _busy := false          # a man is being made (over the frames that follow, MenuMan): what is asked meanwhile waits for him
var _again := false         # and something else was asked meanwhile: the last asked for is made when he is whole

signal built

## The view and its frame (a tag in the corner); add `frame` to the screen and this node to the tree.
static func make(tag: String) -> ArmourStage:
	var s := ArmourStage.new()
	s.stage = Stage3D.new()
	s.stage.spin = 0.35
	s.spin = 0.35
	s.frame = StationKit.stage_frame(s.stage, tag, "Drag to turn him")
	s._wait = UIStyle.label("Dressing him…", 14, UIStyle.MUTED)
	s._wait.autowrap_mode = TextServer.AUTOWRAP_OFF
	s._wait.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	s._wait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	(s.frame.get_meta("layer") as Control).add_child(s._wait)
	return s

## Stands him in `new_ids` (the armour on him): now if he is not dressed so already. A man is made over the frames that follow (MenuMan),
## and one asked for while another is being made is made when that one is whole, not beside it: the last asked for.
func dress(new_ids: Array) -> void:
	if new_ids == ids and (stage.model != null or _busy):
		return
	ids = new_ids.duplicate()
	_token += 1
	_wait.visible = true
	if _busy:
		_again = true
		return
	_busy = true
	while is_inside_tree():
		_again = false
		var mine := _token
		# (Two frames first: the screen is on the display before the man is made.)
		await get_tree().process_frame
		await get_tree().process_frame
		if not is_inside_tree():
			break
		var yaw := stage.yaw if stage.model != null else 0.0
		var made = await MenuMan.stand(stage.pivot, ids, {"body": body} if not body.is_empty() else {})
		if made != null and (_again or mine != _token or not is_inside_tree()):
			if is_instance_valid(made):
				made.queue_free()
			made = null
		if made == null:
			if _again and is_inside_tree():
				continue
			break
		man = made
		stage.show_model(man, {"box": MAN_BOX, "centre": false, "orbit": true, "stand": "plinth", "yaw": yaw, "pitch": 0.08, "k": 1.12, "lift": -0.02, "spin": spin})
		_wait.visible = false
		built.emit()
		break
	_busy = false
