extends Node
class_name CombatAnimListener

var _cc: CombatController
var _animation: AnimationPlayer
var _sprite: AnimatedSprite2D
var _parry_toggle: bool = false  # alterna success A/B

func setup(controller: CombatController, animation: AnimationPlayer, sprite: AnimatedSprite2D) -> void:
	_cc = controller
	_animation = animation
	_sprite = sprite
	if _cc != null:
		_cc.state_entered.connect(_on_state_entered)
		_cc.phase_changed.connect(_on_phase_changed)

# ===================== ROTEAMENTO POR SINAIS =====================

func _on_state_entered(state: int, cfg: AttackConfig) -> void:
	if state == CombatController.State.ATTACK:
		if _cc.current_kind == CombatController.AttackKind.COMBO:
			_animation.play(&"combo")
		else:
			_animation.play(cfg.body_clip)
	elif state == CombatController.State.PARRY:
		_animation.play(&"parry")
	elif state == CombatController.State.DODGE:
		_animation.play(&"dodge_down")
	elif state == CombatController.State.PARRIED:
		_animation.play(&"parried_light")
	elif state == CombatController.State.GUARD_HIT:
		_animation.play(&"block_hit")
	elif state == CombatController.State.STUNNED:
		_animation.play(&"hitstun")
	elif state == CombatController.State.IDLE:
		_animation.play(&"idle")

func _on_phase_changed(phase: int, cfg: AttackConfig) -> void:
	if _animation == null or _cc == null:
		return

	var st: int = _cc.get_state()

	# Tocar o próximo golpe do combo normal (sem entrar de novo no estado)
	if st == CombatController.State.ATTACK and phase == CombatController.Phase.STARTUP:
		if _cc.current_kind != CombatController.AttackKind.COMBO and cfg != null:
			_animation.play(cfg.body_clip)
		return

	# Parry: agora dirigimos por phases PARRY/STARTUP, PARRY/SUCCESS
	if st == CombatController.State.PARRY:
		print("parry -> _on_phase_changed: ", phase)
		if phase == CombatController.Phase.STARTUP:
			print("parry -> STARTUP")
			# Entrada inicial ou rearme manual durante SUCCESS
			_animation.play(&"parry")
			return
		elif phase == CombatController.Phase.SUCCESS:
			print("parry -> SUCCESS")
			# Alterna entre A/B a cada sucesso
			var clip: StringName = &"parry_success_a"
			if _parry_toggle:
				clip = &"parry_success_b"
			_parry_toggle = not _parry_toggle
			_animation.play(clip)
			return
		# ACTIVE/RECOVER: não trocamos clipe aqui; timeline já cobre

# ===================== NOTIFIES (AnimationPlayer -> Controller) =====================

func phase_startup_end() -> void:
	_cc.on_phase_startup_end()

func phase_hit_end() -> void:
	_cc.on_phase_hit_end()

func phase_recover_end() -> void:
	_cc.on_phase_recover_end()

func parried_end() -> void:
	_cc.on_parried_end()

func guard_hit_end() -> void:
	_cc.on_guard_hit_end()

func hitstun_end() -> void:
	_cc.on_hitstun_end()

func parry_window_on() -> void:
	_cc.on_parry_window_on()
	
func parry_window_off() -> void:
	_cc.on_parry_window_off()

func parry_fail_end() -> void:
	_cc.on_parry_fail_end()

func parry_success_end() -> void:
	_cc.on_parry_success_end()
