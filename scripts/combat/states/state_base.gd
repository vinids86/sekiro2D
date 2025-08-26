extends RefCounted
class_name StateBase

func allows_attack_input(_cc: CombatController) -> bool:
	return false

func allows_parry_input(_cc: CombatController) -> bool:
	return false

func allows_dodge_input(_cc: CombatController) -> bool:
	return false

func is_parry_window(_cc: CombatController) -> bool:
	return false

func autoblock_enabled(_cc: CombatController) -> bool:
	return false

func ignore_reaction(_cc: CombatController) -> bool:
	return false

func allows_heavy_start(_cc: CombatController) -> bool:
	return false

func on_enter(_cc: CombatController, _cfg: AttackConfig) -> void:
	pass

func on_exit(_cc: CombatController) -> void:
	pass

func on_timeout(_cc: CombatController) -> void:
	pass
