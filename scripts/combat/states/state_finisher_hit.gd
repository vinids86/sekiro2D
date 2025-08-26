extends StateBase
class_name StateFinisherHit

func allows_attack_input(_cc: CombatController) -> bool: return false
func allows_parry_input(_cc: CombatController) -> bool: return false
func allows_dodge_input(_cc: CombatController) -> bool: return false
func autoblock_enabled(_cc: CombatController) -> bool: return false

func on_timeout(cc: CombatController) -> void:
	var cfg := cc.get_current_attack()
	assert(cfg != null, "StateFinisherHit.on_timeout: cfg nulo")
	cc._change_state(CombatController.State.FINISHER_RECOVER, cfg, maxf(cfg.recovery, 0.0))
