class_name TestWorld
extends Node3D
## A headless arena for tests: ground and wall, combat, fighters stepped by hand.

var arena: Arena
var combat: Combat
var fighters: Array = []

func _init() -> void:
	arena = Arena.new()
	add_child(arena)
	combat = Combat.new()
	add_child(combat)

func ready_arena() -> void:
	arena.build("colosseum", false)

func fighter(pos: Vector3, yaw: float, loadout: Dictionary, opts := {}) -> Fighter:
	var f := Fighter.new()
	add_child(f)
	f.build(pos, yaw, loadout, opts)
	fighters.append(f)
	combat.fighters.append(f)
	return f
