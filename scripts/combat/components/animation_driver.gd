extends Node
class_name AnimationDriver

@export var sprite_path: NodePath
@export var flip_left_is_true: bool = true
@export var exhausted_suffix: String = "_exhausted"

var _sprite: AnimatedSprite2D
var _last_dir_label: String = "right"
var _is_exhausted: bool = false

func _ready() -> void:
	_sprite = get_node_or_null(sprite_path) as AnimatedSprite2D
	assert(_sprite != null, "AnimationDriver: sprite_path inválido")

func set_direction_from_vector(v: Vector2) -> void:
	if v == Vector2.ZERO:
		return
	if v.x >= 0.0:
		_last_dir_label = "right"
	else:
		_last_dir_label = "left"
	_apply_flip()

func set_direction_label(label: String) -> void:
	if label == "" or label == _last_dir_label:
		return
	_last_dir_label = label
	_apply_flip()

func set_exhausted(exh: bool) -> void:
	_is_exhausted = exh

func play_state_anim(base: String) -> void:
	var anim: String = base
	if _is_exhausted and (base == "idle" or base == "walk"):
		anim = base + exhausted_suffix
	if _sprite.animation != anim:
		_sprite.play(anim)

func play_exact(anim: String) -> void:
	if anim != "" and _sprite.animation != anim:
		_sprite.play(anim)

func _apply_flip() -> void:
	# Se flip_left_is_true, virar ao olhar para a esquerda; senão, inverter a lógica
	var flip: bool = false
	if flip_left_is_true:
		flip = (_last_dir_label == "left")
	else:
		flip = (_last_dir_label == "right")
	_sprite.flip_h = flip
