extends Node
class_name Health

signal changed(current: int, maximum: int)
signal died

@export var max_hp: int = 100
var hp: int

func _ready() -> void:
	hp = clampi(hp if hp != 0 else max_hp, 0, max_hp)
	emit_signal("changed", hp, max_hp)

func apply_damage(amount: int, _source: Node = null) -> void:
	if amount <= 0:
		return
	hp = maxi(0, hp - amount)
	emit_signal("changed", hp, max_hp)
	if hp == 0:
		emit_signal("died")

func heal(amount: int) -> void:
	if amount <= 0:
		return
	hp = mini(max_hp, hp + amount)
	emit_signal("changed", hp, max_hp)

func is_dead() -> bool:
	return hp <= 0
