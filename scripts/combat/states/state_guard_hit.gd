extends StateBase
class_name StateGuardHit

func allows_attack_input(_cc: CombatController) -> bool: return false
func allows_parry_input(_cc: CombatController) -> bool: return false
func allows_dodge_input(_cc: CombatController) -> bool: return false
func autoblock_enabled(_cc: CombatController) -> bool: return true

func on_timeout(cc: CombatController) -> void:
	cc._change_state(CombatController.State.GUARD_RECOVER, null, cc.get_guard_recover_time())
