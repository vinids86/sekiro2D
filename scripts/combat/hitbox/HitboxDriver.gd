extends Node
class_name HitboxDriver

var _cc: CombatController
var _hitbox: AttackHitbox
var _attacker: Node2D
var _pivot: Node2D   # Facing
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
	if state == CombatController.State.HIT or state == CombatController.State.COUNTER_HIT or state == CombatController.State.FINISHER_HIT:
		assert(cfg != null, "AttackConfig nulo ao entrar em HIT")
		# POSICIONA local ao Facing; o espelhamento vem do scale.x do Facing
		_hitbox.position = cfg.hitbox_offset
		_hitbox.enable(cfg, _attacker)
	elif state == CombatController.State.STUN:
		_hitbox.disable()

func _on_state_exited(state: int, _cfg: AttackConfig) -> void:
	if state == CombatController.State.HIT or state == CombatController.State.COUNTER_HIT or state == CombatController.State.FINISHER_HIT:
		_hitbox.disable()
