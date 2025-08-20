extends Node
class_name CombatAnimListener

var _cc: CombatController
var _driver: AnimationDriver
var _fallback_idle: StringName = &"idle"
var _wired: bool = false

func setup(controller: CombatController, driver: AnimationDriver, fallback_idle: StringName = &"idle") -> void:
	_cc = controller
	_driver = driver
	_fallback_idle = fallback_idle

	assert(_cc != null, "CombatController nulo")
	assert(_driver != null, "AnimationDriver nulo")
	if _wired:
		return
	_wired = true

	# Controller → decide o que tocar
	_cc.state_entered.connect(_on_state_entered)
	# Driver → informa fim de partes
	_driver.body_end.connect(Callable(_cc, "_on_body_end"))
	_driver.to_idle_end.connect(Callable(_cc, "_on_to_idle_end"))

func _on_state_entered(state: int, cfg: AttackConfig) -> void:
	if state == CombatController.State.STARTUP:
		assert(cfg != null, "AttackConfig nulo em STARTUP")
		var total: float = maxf(cfg.startup + cfg.hit + cfg.recovery, 0.0)
		_driver.play_attack_body(cfg.body_clip, cfg.body_frames, cfg.body_fps, total)
	elif state == CombatController.State.IDLE:
		var idle_clip: StringName = _cc.get_idle_clip()
		if idle_clip == StringName():
			idle_clip = _fallback_idle
		if cfg != null and cfg.to_idle_clip != StringName():
			_driver.play_to_idle(cfg.to_idle_clip)
		else:
			_driver.play_idle(idle_clip)
	elif state == CombatController.State.STUN:
		var hit_clip: StringName = _cc.get_hit_clip()
		assert(hit_clip != StringName(), "Hit clip não configurado no controller")
		_driver.play_to_idle(hit_clip)
