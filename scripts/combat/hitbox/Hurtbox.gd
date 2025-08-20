extends Area2D
class_name Hurtbox

@export var owner_node: Node
signal damaged(from: Node, cfg: AttackConfig)

func _ready() -> void:
	add_to_group("hurtbox")
