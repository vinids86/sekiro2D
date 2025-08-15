extends RefCounted
class_name AttackTimeline

signal step(distance_px: float)

var active_clock: float = 0.0
var _prev: float = 0.0
var _step_emitted: bool = false

func start() -> void:
	active_clock = 0.0
	_prev = 0.0
	_step_emitted = false

func reset() -> void:
	active_clock = 0.0
	_prev = 0.0
	_step_emitted = false

func tick(delta: float, cfg: AttackConfig) -> void:
	_prev = active_clock
	active_clock += delta

	if cfg == null:
		return
	if _step_emitted:
		return
	if cfg.step_distance_px == 0.0:
		return

	var crossed: bool = (_prev < cfg.step_time_in_active and active_clock >= cfg.step_time_in_active)
	if crossed:
		_step_emitted = true
		step.emit(cfg.step_distance_px)
