extends StateBase
class_name StateParry

func allows_attack_input(_cc: CombatController) -> bool:
	return false

func allows_parry_input(cc: CombatController) -> bool:
	# Rearme manual só durante a pose de sucesso
	return cc.phase == CombatController.Phase.SUCCESS

func allows_dodge_input(_cc: CombatController) -> bool:
	return false

func autoblock_enabled(_cc: CombatController) -> bool:
	return false

func allows_heavy_start(_cc: CombatController) -> bool:
	return false

func allows_reentry(cc: CombatController) -> bool:
	# Reentrar em PARRY apenas quando está em SUCCESS
	return cc.phase == CombatController.Phase.SUCCESS

func on_enter(_cc: CombatController, _cfg: AttackConfig) -> void:
	pass

func on_exit(_cc: CombatController) -> void:
	pass
