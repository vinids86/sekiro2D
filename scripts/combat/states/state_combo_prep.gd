extends StateBase
class_name StateComboPrep

func allows_attack_input(_cc: CombatController) -> bool: return false
func allows_parry_input(_cc: CombatController) -> bool: return false
func allows_dodge_input(_cc: CombatController) -> bool: return false
func autoblock_enabled(_cc: CombatController) -> bool: return true

func on_timeout(cc: CombatController) -> void:
	cc.combo_begin_after_prep()
