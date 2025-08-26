extends StateBase
class_name StateHeavyRecover

func allows_attack_input(_cc: CombatController) -> bool: return true
func allows_parry_input(_cc: CombatController) -> bool: return true
func allows_dodge_input(_cc: CombatController) -> bool: return true
func autoblock_enabled(_cc: CombatController) -> bool: return true
func allows_heavy_start(_cc: CombatController) -> bool: return true

func on_timeout(cc: CombatController) -> void:
	if cc.consume_chain_request():
		cc.start_first_attack()
	else:
		cc._change_state(CombatController.State.IDLE, null, 0.0)
