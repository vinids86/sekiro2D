extends StateBase
class_name StateParryStartup

func allows_attack_input(_cc: CombatController) -> bool: return false
func allows_parry_input(_cc: CombatController) -> bool: return true
func allows_dodge_input(_cc: CombatController) -> bool: return false
func autoblock_enabled(_cc: CombatController) -> bool: return false
func is_parry_window(_cc: CombatController) -> bool: return true

func on_timeout(cc: CombatController) -> void:
	cc._change_state(CombatController.State.PARRY_RECOVER, null, cc.get_parry_recover_time())
