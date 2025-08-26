extends StateBase
class_name StateComboParry

func allows_attack_input(_cc: CombatController) -> bool: return false
func allows_parry_input(_cc: CombatController) -> bool: return true
func allows_dodge_input(_cc: CombatController) -> bool: return false
func autoblock_enabled(_cc: CombatController) -> bool: return false
func is_parry_window(_cc: CombatController) -> bool: return true

func on_timeout(cc: CombatController) -> void:
	cc._change_state(CombatController.State.COMBO_PREP, null, maxf(cc.get_combo_prep_time(), 0.0))
