# res://combat/InputBuffer.gd
extends RefCounted
class_name InputBuffer

# espelhar o enum do controller (evita ciclo)
enum ActionType { NONE, ATTACK, PARRY, DODGE }

# -------- Ação leve --------
var queued_action: int = ActionType.NONE
var queued_direction: Vector2 = Vector2.ZERO
var action_timer: float = 0.0

# -------- Heavy --------
var queued_heavy_cfg: AttackConfig = null
var queued_heavy_dir: Vector2 = Vector2.ZERO
var heavy_timer: float = 0.0

# -------- Leniência tardia (últimos inputs) --------
var last_attack_time: float = -1.0
var last_attack_dir: Vector2 = Vector2.ZERO
var last_heavy_time: float = -1.0
var last_heavy_dir: Vector2 = Vector2.ZERO

# =================== API ===================
func push_action(action: int, dir: Vector2, duration: float) -> void:
	if duration < 0.0:
		duration = 0.0
	queued_action = action
	queued_direction = dir
	action_timer = duration
	if action == ActionType.ATTACK:
		last_attack_time = _now_sec()
		last_attack_dir = dir

func push_heavy(cfg: AttackConfig, dir: Vector2, duration: float) -> void:
	if duration < 0.0:
		duration = 0.0
	queued_heavy_cfg = cfg
	queued_heavy_dir = dir
	heavy_timer = duration
	last_heavy_time = _now_sec()
	last_heavy_dir = dir

func tick(delta: float) -> void:
	if action_timer > 0.0:
		action_timer -= delta
		if action_timer <= 0.0:
			clear_action()
	if heavy_timer > 0.0:
		heavy_timer -= delta
		if heavy_timer <= 0.0:
			clear_heavy()

func has_buffer() -> bool:
	return has_action() or has_heavy()

func has_action() -> bool:
	return queued_action != ActionType.NONE and action_timer > 0.0

func has_heavy() -> bool:
	return queued_heavy_cfg != null and heavy_timer > 0.0

func was_attack_within(window_s: float) -> bool:
	if window_s <= 0.0:
		return false
	if last_attack_time < 0.0:
		return false
	var now: float = _now_sec()
	return (now - last_attack_time) <= window_s

func recent_attack_dir() -> Vector2:
	return last_attack_dir

func extend_all_timers(min_time: float) -> void:
	if min_time <= 0.0:
		return
	if action_timer > 0.0:
		if action_timer < min_time:
			action_timer = min_time
	if heavy_timer > 0.0:
		if heavy_timer < min_time:
			heavy_timer = min_time

func max_time_left() -> float:
	var a: float = (action_timer if action_timer > 0.0 else 0.0)
	var h: float = (heavy_timer if heavy_timer > 0.0 else 0.0)
	return (a if a > h else h)

func clear_action() -> void:
	queued_action = ActionType.NONE
	queued_direction = Vector2.ZERO
	action_timer = 0.0

func clear_heavy() -> void:
	queued_heavy_cfg = null
	queued_heavy_dir = Vector2.ZERO
	heavy_timer = 0.0

func clear_all() -> void:
	clear_action()
	clear_heavy()

# =================== Interno ===================
func _now_sec() -> float:
	return float(Time.get_ticks_msec()) / 1000.0
