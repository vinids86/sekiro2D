extends Node
class_name ImpactDriver

signal hit_applied(attacker: Node2D, defender: Node2D, cfg: AttackConfig)

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
	var defender: Node2D = _hurtbox.get_parent() as Node2D
	assert(defender != null)

	_health.apply_damage(cfg.damage, attacker)

	_cc.enter_stun()

	hit_applied.emit(attacker, defender, cfg)
