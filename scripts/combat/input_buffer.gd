# res://combat/InputBuffer.gd
extends RefCounted
class_name InputBuffer

# espelhar teu enum para não importar CombatController (evita ciclo)
enum ActionType { NONE, ATTACK, PARRY, DODGE }

var queued_action: int = ActionType.NONE
var queued_direction: Vector2 = Vector2.ZERO
var buffer_timer: float = 0.0

# heavy específico
var queued_heavy_cfg: AttackConfig = null
var queued_heavy_dir: Vector2 = Vector2.ZERO

func push_action(action: int, dir: Vector2, duration: float) -> void:
	queued_action = action
	queued_direction = dir
	buffer_timer = maxf(duration, 0.0)

func push_heavy(cfg: AttackConfig, dir: Vector2, duration: float) -> void:
	queued_heavy_cfg = cfg
	queued_heavy_dir = dir
	buffer_timer = maxf(duration, 0.0)

func tick(delta: float) -> void:
	if buffer_timer > 0.0:
		buffer_timer -= delta
		if buffer_timer <= 0.0:
			clear_all()

func has_buffer() -> bool:
	return buffer_timer > 0.0 and (queued_action != ActionType.NONE or queued_heavy_cfg != null)

func clear_action() -> void:
	queued_action = ActionType.NONE
	queued_direction = Vector2.ZERO

func clear_heavy() -> void:
	queued_heavy_cfg = null
	queued_heavy_dir = Vector2.ZERO

func clear_all() -> void:
	clear_action()
	clear_heavy()
	buffer_timer = 0.0
