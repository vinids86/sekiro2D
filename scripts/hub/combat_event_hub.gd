extends Node
class_name CombatEventHub

signal parry_success(attacker: Node2D, defender: Node2D, cfg: AttackConfig)

func publish_parry_success(attacker: Node2D, defender: Node2D, cfg: AttackConfig) -> void:
	assert(attacker != null)
	assert(defender != null)
	assert(cfg != null)
	parry_success.emit(attacker, defender, cfg)
