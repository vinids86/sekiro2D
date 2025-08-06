extends Area2D

@onready var shape: CollisionShape2D = $CollisionShape2D

func _ready():
	monitoring = false
	shape.disabled = true
	connect("area_entered", Callable(self, "_on_area_entered"))

func enable():
	monitoring = true
	shape.disabled = false
	visible = true

func disable():
	monitoring = false
	shape.disabled = true
	visible = false

func _on_area_entered(area: Area2D) -> void:
	var defender = area.get_parent()
	var attacker = get_parent()

	if defender == attacker:
		return

	if defender.has_method("receive_attack"):
		defender.receive_attack(attacker)
