extends Node
class_name CombatResolver

# Futuro: enums Impact, cálculo de dano, time/facção, etc.

func resolve_hit(attacker: Node, hurtbox: Area2D, cfg: AttackConfig) -> void:
	assert(attacker != null, "Attacker não encontrado no CombatResolver")
	assert(hurtbox != null, "Hurtbox não encontrado no CombatResolver")
	assert(cfg != null, "AttackConfig não encontrado no CombatResolver")

	# Encaminha pro lado da vítima (se já tiver API; senão, só loga por enquanto)
	var hb: Hurtbox = hurtbox as Hurtbox
	if hb != null:
		var health: Health = hb.get_health()
		health.apply_damage(cfg.damage, attacker)
		hb.controller.enter_stun()
		print("[Resolver] hit -> ", hb.name, " por ", attacker.name, " (", cfg.name_id, ")")
