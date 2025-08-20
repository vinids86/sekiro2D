extends Node2D
class_name FacingDriver

@export var auto_find_opponent: bool = true
@export var opponent_node: Node  # opcional: se quiser setar manualmente

var opponent: Node2D
var sign: int = 1  # +1 direita, -1 esquerda

func _ready() -> void:
	# O root do personagem (pai do Facing) deve estar no grupo "fighter"
	if opponent_node != null:
		opponent = opponent_node as Node2D
	elif auto_find_opponent:
		opponent = _find_opponent()
	set_process(true)

func _process(_dt: float) -> void:
	if opponent == null or not is_instance_valid(opponent):
		if auto_find_opponent:
			opponent = _find_opponent()
		return

	var me_x: float = get_parent().global_position.x   # root do personagem
	var opp_x: float = opponent.global_position.x
	var new_sign: int = 1
	if opp_x < me_x:
		new_sign = -1
	if new_sign != sign:
		sign = new_sign
		scale = Vector2(float(sign), 1.0)  # espelha AnimatedSprite2D e AttackHitbox

func _find_opponent() -> Node2D:
	var root_char: Node = get_parent()
	var nodes: Array = get_tree().get_nodes_in_group("fighter")
	for n in nodes:
		if n != root_char and n is Node2D:
			return n
	return null

func get_facing_sign() -> int:
	return sign
