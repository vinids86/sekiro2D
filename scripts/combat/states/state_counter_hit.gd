extends StateBase
class_name StateCounterHit

func allows_attack_input(_cc: CombatController) -> bool: return false
func allows_parry_input(_cc: CombatController) -> bool: return false
func allows_dodge_input(_cc: CombatController) -> bool: return false
func autoblock_enabled(_cc: CombatController) -> bool: return false

func on_timeout(cc: CombatController) -> void:
	var cfg := cc.get_current_attack()
	assert(cfg != null, "StateCounterHit.on_timeout: cfg nulo")
	cc._change_state(CombatController.State.COUNTER_RECOVER, cfg, maxf(cfg.recovery, 0.0))
