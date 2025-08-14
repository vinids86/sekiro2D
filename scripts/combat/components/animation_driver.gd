extends Node
class_name AnimationDriver

@export var sprite_path: NodePath
@export var flip_left_is_true := true
@export var exhausted_suffix := "_exhausted"

var _sprite: AnimatedSprite2D
var _last_dir_label := "right"
var _is_exhausted := false

func _ready() -> void:
	_sprite = get_node_or_null(sprite_path) as AnimatedSprite2D
	assert(_sprite, "AnimationDriver: sprite_path inválido")

func set_direction_from_vector(v: Vector2) -> void:
	if v == Vector2.ZERO:
		return
	_last_dir_label = "right" if v.x >= 0.0 else "left"
	_apply_flip()

func set_direction_label(label: String) -> void:
	if label == "" or label == _last_dir_label:
		return
	_last_dir_label = label
	_apply_flip()

func set_exhausted(exh: bool) -> void:
	_is_exhausted = exh

func play_state_anim(base: String) -> void:
	var anim := base + (exhausted_suffix if _is_exhausted and (base == "idle" or base == "walk") else "")
	if _sprite.animation != anim:
		_sprite.play(anim)

func play_exact(anim: String) -> void:
	if anim != "" and _sprite.animation != anim:
		_sprite.play(anim)

func _apply_flip() -> void:
	_sprite.flip_h = (_last_dir_label == "left")
