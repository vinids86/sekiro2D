extends Node
class_name ImpactDriver

var _hurtbox: Hurtbox
var _health: Health
var _cc: CombatController
var _hub: CombatEventHub
var _wired: bool = false

func setup(hurtbox: Hurtbox, health: Health, controller: CombatController, hub: CombatEventHub) -> void:
	_hurtbox = hurtbox
	_health = health
	_cc = controller
	_hub = hub
	
	assert(_hub != null, "CombatEventHub nulo no ImpactDriver")
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
		_hub.publish_parry_success(attacker, _hurtbox.get_parent() as Node2D, cfg)
		return

	# caminho normal
	_health.apply_damage(cfg.damage, attacker)
	_cc.enter_hit_react()
