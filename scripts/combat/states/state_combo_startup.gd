extends StateBase
class_name StateComboStartup

func allows_attack_input(_cc: CombatController) -> bool: return false
func allows_parry_input(_cc: CombatController) -> bool: return false
func allows_dodge_input(_cc: CombatController) -> bool: return false
func autoblock_enabled(_cc: CombatController) -> bool: return false
func ignore_reaction(_cc: CombatController) -> bool: return true

func on_timeout(cc: CombatController) -> void:
	var cfg := cc.get_current_attack()
	assert(cfg != null, "StateComboStartup.on_timeout: cfg nulo")
	cc._change_state(CombatController.State.COMBO_HIT, cfg, maxf(cfg.hit, 0.0))
