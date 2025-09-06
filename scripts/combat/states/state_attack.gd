extends StateBase
class_name StateAttack

func allows_attack_input(cc: CombatController) -> bool:
	return false

func allows_parry_input(_cc: CombatController) -> bool:
	if _cc.phase == CombatController.Phase.RECOVER and _cc.current_kind == CombatController.AttackKind.LIGHT: 
		return true
	else: return false

func allows_dodge_input(_cc: CombatController) -> bool:
	var in_recover: bool = _cc.phase == CombatController.Phase.RECOVER
	if not in_recover:
		return false

	var kind: int = _cc.current_kind

	if kind == CombatController.AttackKind.LIGHT:
		return true
	if kind == CombatController.AttackKind.HEAVY:
		return true
	if kind == CombatController.AttackKind.COMBO:
		print("[ATKST] combo_index: ", _cc.combo_index, " ", _cc.attack_set.next_index(_cc.combo_index))
		return _cc.is_combo_last_attack()

	return false

func autoblock_enabled(_cc: CombatController) -> bool:
	if _cc.phase != CombatController.Phase.ACTIVE:
		return true
	return false
	
func is_interruptible(_cc: CombatController) -> bool:

	return true

func is_attack_buffer_window_open(cc: CombatController) -> bool:
	if cc.current_kind == CombatController.AttackKind.COMBO:
		return false
	return true

func allows_heavy_start(_cc: CombatController) -> bool:
	return false

func allows_reentry(_cc: CombatController) -> bool:
	return false
