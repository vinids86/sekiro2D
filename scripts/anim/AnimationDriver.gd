extends RefCounted
class_name AnimationDriver

signal body_end(clip: StringName)
signal to_idle_end(clip: StringName)

func play_attack_body(clip: StringName, frames: int, fps: float, total_seconds: float) -> void:
	assert(clip != StringName(), "clip do body vazio")
	assert(frames > 0, "frames do body deve ser > 0")
	assert(fps > 0.0, "fps do body deve ser > 0")
	assert(total_seconds > 0.0, "total_seconds do body deve ser > 0")
	_play_attack_body_impl(clip, frames, fps, total_seconds)

func play_to_idle(clip: StringName) -> void:
	assert(clip != StringName(), "clip do to_idle vazio")
	_play_to_idle_impl(clip)

func play_idle(clip: StringName) -> void:
	assert(clip != StringName(), "clip de idle vazio")
	_play_idle_impl(clip)

func connect_body_end(target: Object, method: StringName) -> void:
	body_end.connect(Callable(target, method))

func connect_to_idle_end(target: Object, method: StringName) -> void:
	to_idle_end.connect(Callable(target, method))

# ---- virtuais (as implementações concretas devem sobrescrever) ----
func _play_attack_body_impl(clip: StringName, frames: int, fps: float, total_seconds: float) -> void:
	assert(false, "AnimationDriver._play_attack_body_impl não implementado")

func _play_to_idle_impl(clip: StringName) -> void:
	assert(false, "AnimationDriver._play_to_idle_impl não implementado")

func _play_idle_impl(clip: StringName) -> void:
	assert(false, "AnimationDriver._play_idle_impl não implementado")
