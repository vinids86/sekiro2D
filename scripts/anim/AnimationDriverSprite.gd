extends AnimationDriver
class_name AnimationDriverSprite

var sprite: AnimatedSprite2D
var _current_body: StringName = StringName()
var _current_to_idle: StringName = StringName()

func _init(p_sprite: AnimatedSprite2D) -> void:
	sprite = p_sprite
	assert(sprite != null, "AnimatedSprite2D nulo no AnimationDriverSprite")
	sprite.animation_finished.connect(Callable(self, "_on_sprite_finished"))

func _play_attack_body_impl(clip: StringName, frames: int, fps: float, total_seconds: float) -> void:
	var clip_seconds: float = float(frames) / fps
	var speed: float = clip_seconds / total_seconds # dura exatamente total_seconds
	_current_body = clip
	_current_to_idle = StringName()
	sprite.speed_scale = speed
	sprite.play(clip)

func _play_to_idle_impl(clip: StringName) -> void:
	_current_to_idle = clip
	sprite.speed_scale = 1.0
	sprite.play(clip)

func _play_idle_impl(clip: StringName) -> void:
	_current_body = StringName()
	_current_to_idle = StringName()
	sprite.speed_scale = 1.0
	sprite.play(clip)

func _on_sprite_finished() -> void:
	var finished: StringName = sprite.animation
	if finished == _current_body:
		emit_signal("body_end", _current_body)
	elif finished == _current_to_idle:
		emit_signal("to_idle_end", _current_to_idle)
