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

## Stands him in `new_ids` (the armour on him): now if he is not dressed so already.
func dress(new_ids: Array) -> void:
	if stage.model != null and new_ids == ids:
		return
	ids = new_ids.duplicate()
	_token += 1
	var mine := _token
	_wait.visible = true
	# (Two frames first: the screen is on the display before the man is made.)
	await get_tree().process_frame
	await get_tree().process_frame
	if mine != _token or not is_inside_tree():
		return
	var yaw := stage.yaw if stage.model != null else 0.0
	man = MenuMan.stand(stage.pivot, ids, {"body": body} if not body.is_empty() else {})
	stage.show_model(man, {"box": MAN_BOX, "centre": false, "orbit": true, "stand": "plinth", "yaw": yaw, "pitch": 0.08, "k": 1.12, "lift": -0.02, "spin": spin})
	_wait.visible = false
	built.emit()
