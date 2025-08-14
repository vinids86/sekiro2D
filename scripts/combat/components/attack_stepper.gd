extends Node
class_name AttackStepper

@export var body_path: NodePath
@export var step_duration := 0.06

var _body: CharacterBody2D
var _timer := 0.0
var _speed := 0.0

func _ready() -> void:
	_body = get_node_or_null(body_path) as CharacterBody2D
	assert(_body, "AttackStepper: body_path inválido")

func start_step(distance_px: float, face_left: bool) -> void:
	_timer = step_duration
	var dir := -1.0 if face_left else 1.0
	_speed = (distance_px / step_duration) * dir

func physics_tick(delta: float) -> void:
	if _timer > 0.0:
		_timer -= delta
		_body.velocity.x = _speed
