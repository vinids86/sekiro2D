extends StateBase
class_name StateDodgeActive

func allows_attack_input(_cc: CombatController) -> bool: return false
func allows_parry_input(_cc: CombatController) -> bool: return false
func allows_dodge_input(_cc: CombatController) -> bool: return false
func autoblock_enabled(_cc: CombatController) -> bool: return false

func on_timeout(cc: CombatController) -> void:
	cc._change_state(CombatController.State.DODGE_RECOVER, null, maxf(cc.get_dodge_recover_time(), 0.0))
