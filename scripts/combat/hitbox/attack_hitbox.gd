extends Area2D

@onready var shape: CollisionShape2D = $CollisionShape2D
var _already_applied := {}

func _ready():
	monitoring = false
	shape.disabled = true
	connect("area_entered", Callable(self, "_on_area_entered"))
	connect("body_entered", Callable(self, "_on_body_entered"))

func enable():
	_already_applied.clear()
	monitoring = true
	shape.disabled = false
	visible = true
	call_deferred("_emit_existing_overlaps")

func disable():
	monitoring = false
	shape.disabled = true
	visible = false
	_already_applied.clear()

func _emit_existing_overlaps() -> void:
	await get_tree().physics_frame
	for area in get_overlapping_areas():
		_on_area_entered(area)
	for body in get_overlapping_bodies():
		_on_body_entered(body)

func _resolve_actor_root(node: Node) -> Node:
	var cur := node
	while cur and not cur.has_method("get_combat_controller") and cur.get_parent():
		cur = cur.get_parent()
	return cur

func _hit(defender: Node, attacker: Node) -> void:
	if defender == attacker: return
	if _already_applied.has(defender): return
	if defender and defender.has_method("receive_attack"):
		_already_applied[defender] = true
		defender.receive_attack(attacker)

func _on_area_entered(area: Area2D) -> void:
	_hit(_resolve_actor_root(area), _resolve_actor_root(self))

func _on_body_entered(body: Node) -> void:
	_hit(_resolve_actor_root(body), _resolve_actor_root(self))
