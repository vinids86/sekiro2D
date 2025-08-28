extends StateBase
class_name StateGuardHit

func allows_attack_input(_cc: CombatController) -> bool:
	return false

func allows_parry_input(_cc: CombatController) -> bool:
	return true

func allows_dodge_input(_cc: CombatController) -> bool:
	return true

func autoblock_enabled(_cc: CombatController) -> bool:
	return true

func allows_heavy_start(_cc: CombatController) -> bool:
	return false

func allows_reentry(_cc: CombatController) -> bool:
	# Queremos reiniciar o clipe/som a cada novo bloqueio enquanto estiver em GUARD_HIT
	return true

func on_enter(_cc: CombatController, _cfg: AttackConfig) -> void:
	# Timeout vem da animação (AnimPlayer → guard_hit_end). Nada a fazer aqui.
	pass

func on_exit(_cc: CombatController) -> void:
	# Limpeza específica se um dia precisar (não necessário agora)
	pass
