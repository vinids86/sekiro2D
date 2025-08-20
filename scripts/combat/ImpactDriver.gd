extends Node
class_name ImpactDriver

var _hurtbox: Hurtbox
var _health: Health
var _cc: CombatController

var _wired: bool = false

func setup(hurtbox: Hurtbox, health: Health, controller: CombatController) -> void:
	_hurtbox = hurtbox
	_health = health
	_cc = controller

	assert(_hurtbox != null, "Hurtbox nulo no ImpactDriver")
	assert(_health != null, "Health nulo no ImpactDriver")
	assert(_cc != null, "CombatController nulo no ImpactDriver")

	if _wired:
		return
	_wired = true

	_hurtbox.contact.connect(_on_contact, Object.CONNECT_DEFERRED)

func _on_contact(attacker: Node2D, cfg: AttackConfig, _hitbox: AttackHitbox) -> void:
	if _cc.is_parry_window():
		_cc.enter_parry_success()
		return

	# Fluxo normal atual (vamos trocar para autoblock depois)
	_health.apply_damage(cfg.damage, attacker)
	_cc.enter_stun()
