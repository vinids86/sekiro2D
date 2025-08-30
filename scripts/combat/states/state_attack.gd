extends StateBase
class_name StateAttack

func allows_attack_input(cc: CombatController) -> bool:
	# Permite buffer/chain enquanto a ofensa está ativa (STARTUP/ACTIVE)
	return cc.is_combo_offense_active()

func allows_parry_input(_cc: CombatController) -> bool:
	if _cc.phase == CombatController.Phase.RECOVER: return true
	else: return false

func allows_dodge_input(_cc: CombatController) -> bool:
	if _cc.phase == CombatController.Phase.RECOVER: return true
	else: return false

func autoblock_enabled(_cc: CombatController) -> bool:
	return false

func allows_heavy_start(_cc: CombatController) -> bool:
	return false

func allows_reentry(_cc: CombatController) -> bool:
	return false

func on_enter(_cc: CombatController, _cfg: AttackConfig) -> void:
	pass

func on_exit(_cc: CombatController) -> void:
	pass
