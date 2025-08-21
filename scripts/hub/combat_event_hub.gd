extends Node
class_name CombatEventHub

signal parry_success(attacker: Node2D, defender: Node2D, cfg: AttackConfig)
signal guard_blocked(attacker: Node2D, defender: Node2D, cfg: AttackConfig, absorbed: int, hp_damage: int)

func publish_parry_success(attacker: Node2D, defender: Node2D, cfg: AttackConfig) -> void:
	assert(attacker != null and defender != null and cfg != null)
	parry_success.emit(attacker, defender, cfg)

func publish_guard_blocked(attacker: Node2D, defender: Node2D, cfg: AttackConfig, absorbed: int, hp_damage: int) -> void:
	assert(attacker != null and defender != null and cfg != null)
	guard_blocked.emit(attacker, defender, cfg, absorbed, hp_damage)
