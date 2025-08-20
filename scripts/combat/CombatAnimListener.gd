extends Node
class_name CombatAnimListener

var _cc: CombatController
var _driver: AnimationDriver
var _profile: AnimProfile

func setup(controller: CombatController, driver: AnimationDriver, profile: AnimProfile) -> void:
	_cc = controller
	_driver = driver
	_profile = profile
	assert(_cc != null)
	assert(_driver != null)
	assert(_profile != null)

	_cc.state_entered.connect(_on_state_entered)

func _on_state_entered(state: int, cfg: AttackConfig) -> void:
	if state == CombatController.State.STARTUP:
		assert(cfg != null)
		var total: float = maxf(cfg.startup + cfg.hit + cfg.recovery, 0.0)
		_driver.play_attack_body(cfg.body_clip, cfg.body_frames, cfg.body_fps, total)
	elif state == CombatController.State.IDLE:
		# prioriza to_idle do ataque anterior; senão, idle do profile
		if cfg != null and cfg.to_idle_clip != StringName():
			_driver.play_to_idle(cfg.to_idle_clip)
		else:
			_driver.play_idle(_profile.idle_clip)
	elif state == CombatController.State.STUN:
		_driver.play_to_idle(_profile.hit_clip)
