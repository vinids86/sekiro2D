
extends StateBase
class_name StateParry

func allows_attack_input(_cc: CombatController) -> bool: return false
func allows_parry_input(_cc: CombatController) -> bool: return true
func allows_dodge_input(_cc: CombatController) -> bool: return false
func autoblock_enabled(_cc: CombatController) -> bool: return false
func allows_heavy_start(_cc: CombatController) -> bool: return false

func is_parry_window(cc: CombatController) -> bool:
	return cc.get_state() == CombatController.State.PARRY and (cc.phase == CombatController.Phase.ACTIVE or cc.phase == CombatController.Phase.STARTUP)

func on_enter(_cc: CombatController, _cfg: AttackConfig) -> void:
	pass

func on_exit(_cc: CombatController) -> void:
	pass
