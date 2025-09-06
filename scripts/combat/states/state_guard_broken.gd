extends StateBase
class_name StateGuardBroken

func allows_attack_input(_cc: CombatController) -> bool:
	return false

func allows_parry_input(_cc: CombatController) -> bool:
	return false

func allows_dodge_input(_cc: CombatController) -> bool:
	return false

func autoblock_enabled(_cc: CombatController) -> bool:
	return false

func allows_heavy_start(_cc: CombatController) -> bool:
	return false

func allows_reentry(_cc: CombatController) -> bool:
	return false
