extends StateBase
class_name StateParrySuccess

func allows_attack_input(_cc: CombatController) -> bool: return true  # buffer do counter
func allows_parry_input(_cc: CombatController) -> bool: return true
func allows_dodge_input(_cc: CombatController) -> bool: return false
func autoblock_enabled(_cc: CombatController) -> bool: return true

func on_timeout(cc: CombatController) -> void:
	if cc.consume_counter_buffered():
		cc.start_counter_attack()
	else:
		cc._change_state(CombatController.State.IDLE, null, 0.0)
