extends StateBase
class_name StateCounterStartup

func allows_attack_input(_cc: CombatController) -> bool: return false
func allows_parry_input(_cc: CombatController) -> bool: return false
func allows_dodge_input(_cc: CombatController) -> bool: return false
func autoblock_enabled(_cc: CombatController) -> bool: return false

func on_timeout(cc: CombatController) -> void:
	var cfg := cc.get_current_attack()
	assert(cfg != null, "StateCounterStartup.on_timeout: cfg nulo")
	cc._change_state(CombatController.State.COUNTER_HIT, cfg, maxf(cfg.hit, 0.0))
