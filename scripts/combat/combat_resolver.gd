extends Node
class_name CombatResolver

signal hit_applied(attacker: Node2D, defender: Node2D, cfg: AttackConfig)

func resolve_hit(attacker: Node2D, hurtbox: Area2D, cfg: AttackConfig) -> void:
	assert(attacker != null, "Attacker não encontrado no CombatResolver")
	assert(hurtbox != null, "Hurtbox não encontrado no CombatResolver")
	assert(cfg != null, "AttackConfig não encontrado no CombatResolver")

	var hb: Hurtbox = hurtbox as Hurtbox
	assert(hb != null, "A Area2D atingida não tem script Hurtbox")

	var defender: Node2D = hb.get_parent() as Node2D
	assert(defender != null, "Defender inválido (parent da Hurtbox)")

	var health: Health = hb.get_health()
	assert(health != null, "Health ausente na Hurtbox/defensor")

	# — regra atual mínima —
	health.apply_damage(cfg.damage, attacker)

	# Se hoje o Resolver também dispara reação de hit:
	var def_cc: CombatController = defender.get_node(^"CombatController") as CombatController
	assert(def_cc != null, "CombatController ausente no defensor")
	def_cc.enter_stun()

	hit_applied.emit(attacker, defender, cfg)
