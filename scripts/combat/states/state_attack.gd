extends StateBase
class_name StateAttack

func allows_attack_input(cc: CombatController) -> bool:
	# Permite buffer/chain enquanto a ofensa está ativa (STARTUP/ACTIVE)
	return cc.is_combo_offense_active()

func allows_parry_input(_cc: CombatController) -> bool:
	if _cc.phase == CombatController.Phase.RECOVER and _cc.current_kind == CombatController.AttackKind.LIGHT: 
		return true
	else: return false

func allows_dodge_input(_cc: CombatController) -> bool:
	if _cc.phase == CombatController.Phase.RECOVER: return true
	else: return false

func autoblock_enabled(_cc: CombatController) -> bool:
	if _cc.phase != CombatController.Phase.ACTIVE:
		return true
	return false
	
func is_interruptible(_cc: CombatController) -> bool:
	var in_early: bool = (_cc.phase == CombatController.Phase.STARTUP) or (_cc.phase == CombatController.Phase.ACTIVE)
	var heavy_or_combo: bool = (_cc.current_kind == CombatController.AttackKind.HEAVY) or (_cc.current_kind == CombatController.AttackKind.COMBO)
	if in_early and heavy_or_combo:
		return false
	return true

func is_attack_buffer_window_open(cc: CombatController) -> bool:
	if cc.current_kind == CombatController.AttackKind.COMBO:
		return false
	return true

func allows_heavy_start(_cc: CombatController) -> bool:
	return false

func allows_reentry(_cc: CombatController) -> bool:
	return false

func on_enter(_cc: CombatController, _cfg: AttackConfig) -> void:
	pass

func on_exit(_cc: CombatController) -> void:
	pass
