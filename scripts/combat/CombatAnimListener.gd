extends Node
class_name CombatAnimListener

var _cc: CombatController
var _driver: AnimationDriver
var _anim: AnimProfile

var _parry_flip: bool = false  # alterna A/B no success

func setup(controller: CombatController, driver: AnimationDriver, anim_profile: AnimProfile) -> void:
	_cc = controller
	_driver = driver
	_anim = anim_profile

	assert(_cc != null, "CombatController nulo")
	assert(_driver != null, "AnimationDriver nulo")
	assert(_anim != null, "AnimProfile nulo")

	_cc.state_entered.connect(_on_state_entered)
	_driver.body_end.connect(Callable(_cc, "on_body_end"))
	_driver.to_idle_end.connect(Callable(_cc, "on_to_idle_end"))
	_driver.to_idle_end.connect(Callable(self, "_on_to_idle_end_local"))
	
	# Estado visual inicial
	_driver.play_idle(_anim.idle_clip)

func _on_to_idle_end_local(clip: StringName) -> void:
	# Se terminou o clipe de parry_recover, já troca visualmente para idle
	var st: int = _cc.get_state()
	if st == CombatController.State.PARRY_RECOVER and clip == _anim.parry_recover_clip:
		_driver.play_idle(_anim.idle_clip)

func _on_state_entered(state: int, cfg: AttackConfig) -> void:
	if state == CombatController.State.STARTUP:
		assert(cfg != null, "STARTUP sem AttackConfig")
		var total: float = maxf(cfg.startup + cfg.hit + cfg.recovery, 0.0)
		_driver.play_attack_body(cfg.body_clip, cfg.body_frames, cfg.body_fps, total)

	elif state == CombatController.State.HIT:
		# nada; corpo do ataque já toca pelo STARTUP
		pass

	elif state == CombatController.State.RECOVER:
		# transição aguarda body_end
		pass

	elif state == CombatController.State.IDLE:
		if cfg != null and cfg.to_idle_clip != StringName():
			_driver.play_to_idle(cfg.to_idle_clip)
		else:
			_driver.play_idle(_anim.idle_clip)

	elif state == CombatController.State.STUN:
		_driver.play_to_idle(_anim.hit_clip)

	elif state == CombatController.State.PARRY_STARTUP:
		_driver.play_to_idle(_anim.parry_startup_clip)  # to_idle para permitir duração qualquer

	elif state == CombatController.State.PARRY_SUCCESS:
		if _parry_flip:
			_driver.play_to_idle(_anim.parry_success_clip_b)
		else:
			_driver.play_to_idle(_anim.parry_success_clip_a)
		_parry_flip = not _parry_flip

	elif state == CombatController.State.PARRY_RECOVER:
		_driver.play_to_idle(_anim.parry_recover_clip)
