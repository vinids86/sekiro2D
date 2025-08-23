extends Node
class_name CombatAnimListener

var _cc: CombatController
var _driver: AnimationDriver
var _anim: AnimProfile
var _parry_flip: bool = false

# controle visual do combo especial (clip único)
var _combo_visual_on: bool = false

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
	# Intercepta fim de clipes “to_idle” para voltar ao idle visual se necessário
	_driver.to_idle_end.connect(Callable(self, "_on_to_idle_end_local"))

	_driver.play_idle(_anim.idle_clip)

func _on_state_entered(state: int, cfg: AttackConfig) -> void:
	if state == CombatController.State.STARTUP:
		assert(cfg != null, "STARTUP sem AttackConfig")
		var total: float = maxf(cfg.startup + cfg.hit + cfg.recovery, 0.0)
		_driver.play_attack_body(cfg.body_clip, cfg.body_frames, cfg.body_fps, total)

	elif state == CombatController.State.HIT:
		# já está tocando o body do ataque
		pass

	elif state == CombatController.State.RECOVER:
		# aguardará body_end
		pass

	elif state == CombatController.State.IDLE:
		# reset do controle visual do combo ao encerrar
		_combo_visual_on = false
		if cfg != null and cfg.to_idle_clip != StringName():
			_driver.play_to_idle(cfg.to_idle_clip)
		else:
			_driver.play_idle(_anim.idle_clip)

	elif state == CombatController.State.STUN:
		# Sem animação por enquanto (como você pediu)
		pass

	elif state == CombatController.State.PARRY_STARTUP:
		_driver.play_to_idle(_anim.parry_startup_clip)

	elif state == CombatController.State.PARRY_SUCCESS:
		if not _parry_flip:
			_driver.play_to_idle(_anim.parry_success_clip_a)
		else:
			_driver.play_to_idle(_anim.parry_success_clip_b)
		_parry_flip = not _parry_flip

	elif state == CombatController.State.PARRY_RECOVER:
		_driver.play_to_idle(_anim.parry_recover_clip)

	elif state == CombatController.State.HIT_REACT:
		_driver.play_to_idle(_anim.hit_clip)

	elif state == CombatController.State.PARRIED:
		assert(cfg != null, "PARRIED sem AttackConfig atual")
		assert(cfg.to_parried_clip != StringName(), "AttackConfig.to_parried_clip não preenchido")
		_driver.play_to_idle(cfg.to_parried_clip)

	elif state == CombatController.State.GUARD_HIT:
		if _anim.guard_hit_clip != StringName():
			print("play guard hit", _anim.guard_hit_clip)
			_driver.play_to_idle(_anim.guard_hit_clip)

	elif state == CombatController.State.GUARD_RECOVER:
		print("play guard recover", _anim.guard_recover_clip)
		_driver.play_to_idle(_anim.guard_recover_clip)

	elif state == CombatController.State.COUNTER_STARTUP:
		assert(cfg != null, "COUNTER_STARTUP sem AttackConfig")
		var total_c: float = maxf(cfg.startup + cfg.hit + cfg.recovery, 0.0)
		_driver.play_attack_body(cfg.body_clip, cfg.body_frames, cfg.body_fps, total_c)

	elif state == CombatController.State.COUNTER_HIT:
		pass

	elif state == CombatController.State.COUNTER_RECOVER:
		pass

	elif state == CombatController.State.FINISHER_STARTUP:
		assert(cfg != null, "FINISHER_STARTUP sem AttackConfig")
		var total_f: float = maxf(cfg.startup + cfg.hit + cfg.recovery, 0.0)
		_driver.play_attack_body(cfg.body_clip, cfg.body_frames, cfg.body_fps, total_f)

	elif state == CombatController.State.FINISHER_HIT:
		pass

	elif state == CombatController.State.FINISHER_RECOVER:
		pass

	elif state == CombatController.State.GUARD_BROKEN:
		print("play guard broken", _anim.guard_broken_clip)
		_driver.play_idle(_anim.guard_broken_clip)

	elif state == CombatController.State.BROKEN_FINISHER_REACT:
		print("play guard broken", _anim.broken_finisher_clip)
		_driver.play_to_idle(_anim.broken_finisher_clip)

# -------- SPECIAL COMBO (clip único) --------
	elif state == CombatController.State.COMBO_STARTUP:
		assert(cfg != null, "COMBO_STARTUP sem AttackConfig")
		# Só dispara o clip uma vez (primeira entrada do combo)
		if not _combo_visual_on:
			var total_combo: float = 0.0
			if cfg.body_fps > 0.0:
				total_combo = float(cfg.body_frames) / cfg.body_fps
			else:
				# fallback: usa tempos do cfg atual (pode não refletir a sequência inteira)
				total_combo = maxf(cfg.startup + cfg.hit + cfg.recovery, 0.0)
			_driver.play_attack_body(cfg.body_clip, cfg.body_frames, cfg.body_fps, total_combo)
			_combo_visual_on = true

	elif state == CombatController.State.COMBO_HIT:
		# clip já está rodando; nada a fazer
		pass

	elif state == CombatController.State.COMBO_RECOVER:
		# clip já inclui o recover; nenhuma ação adicional aqui
		pass

func _on_to_idle_end_local(clip: StringName) -> void:
	var st: int = _cc.get_state()

	if st == CombatController.State.HIT_REACT and clip == _anim.hit_clip:
		_driver.play_idle(_anim.idle_clip)
	elif st == CombatController.State.PARRY_RECOVER and clip == _anim.parry_recover_clip:
		_driver.play_idle(_anim.idle_clip)
