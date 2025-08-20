extends Area2D
class_name Hurtbox

@export var owner_node: Node
@export var health: Health
@export var controller: CombatController

func _ready() -> void:
	add_to_group("hurtbox")

func get_health() -> Health:
	return health
