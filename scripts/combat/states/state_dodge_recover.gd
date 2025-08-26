extends StateBase
class_name StateDodgeRecover

func allows_attack_input(_cc: CombatController) -> bool: return false
func allows_parry_input(_cc: CombatController) -> bool: return false
func allows_dodge_input(_cc: CombatController) -> bool: return false
func autoblock_enabled(_cc: CombatController) -> bool: return false

func on_timeout(cc: CombatController) -> void:
	cc._change_state(CombatController.State.IDLE, null, 0.0)
