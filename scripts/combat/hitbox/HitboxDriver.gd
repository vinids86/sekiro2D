extends Node
class_name HitboxDriver

var _cc: CombatController
var _hitbox: AttackHitbox
var _attacker: Node2D
var _pivot: Node2D   # Deve ser um FacingDriver
var _wired: bool = false

func setup(controller: CombatController, hitbox: AttackHitbox, attacker: Node2D, pivot: Node2D) -> void:
	_cc = controller
	_hitbox = hitbox
	_attacker = attacker
	_pivot = pivot

	assert(_cc != null, "CombatController nulo")
	assert(_hitbox != null, "AttackHitbox nulo")
	assert(_attacker != null, "Attacker nulo")
	assert(_pivot != null, "Facing pivot nulo")

	if _wired:
		return
	_wired = true

	_cc.state_entered.connect(_on_state_entered)   # imediato é ok (FSM roda no idle)
	_cc.state_exited.connect(_on_state_exited)

	_hitbox.disable()

func _on_state_entered(state: int, cfg: AttackConfig) -> void:
	if _is_hit_state(state):
		assert(cfg != null, "AttackConfig nulo ao entrar em estado de HIT")

		var applied_bonus: bool = false

		# Perfect Link: aplica multiplicador de dano somente em COMBO_HIT
		if state == CombatController.State.COMBO_HIT:
			var mul: float = 1.0
			if _cc != null:
				mul = _cc.consume_combo_link_multiplier()
			print("[LINK] enter COMBO_HIT | mul=", str(mul))
			if mul > 1.0:
				_hitbox.set_runtime_damage_multiplier(mul)
				applied_bonus = true
				print("[LINK] runtime damage mul APPLIED to hitbox")

		# POSICIONA local ao Facing; o espelhamento vem do scale.x do Facing
		_hitbox.position = cfg.hitbox_offset
		_hitbox.enable(cfg, _attacker)
		print("[HITBOX] enabled at pos=", str(_hitbox.position))

		# Feedback visual: chama clarão no FacingDriver quando houver bônus
		if state == CombatController.State.COMBO_HIT and applied_bonus:
			var fd: FacingDriver = _pivot as FacingDriver
			assert(fd != null, "HitboxDriver: pivot não é FacingDriver; não é possível chamar flash().")
			fd.flash()

	elif state == CombatController.State.STUN:
		_hitbox.disable()

func _on_state_exited(state: int, _cfg: AttackConfig) -> void:
	if _is_hit_state(state):
		_hitbox.disable()

func _is_hit_state(state: int) -> bool:
	return state == CombatController.State.HIT \
		or state == CombatController.State.COUNTER_HIT \
		or state == CombatController.State.FINISHER_HIT \
		or state == CombatController.State.COMBO_HIT
