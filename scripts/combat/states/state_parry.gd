extends StateBase
class_name StateParry

func allows_attack_input(_cc: CombatController) -> bool:
	return false

func allows_parry_input(cc: CombatController) -> bool:
	return cc.phase == CombatController.Phase.SUCCESS

func is_parry_window(_cc: CombatController) -> bool:
	return _cc.get_state() == CombatController.State.PARRY \
		and _cc.phase == CombatController.Phase.ACTIVE

func allows_dodge_input(_cc: CombatController) -> bool:
	return false

func autoblock_enabled(_cc: CombatController) -> bool:
	return true

func allows_heavy_start(_cc: CombatController) -> bool:
	return false

func allows_reentry(cc: CombatController) -> bool:
	# Reentrar em PARRY apenas quando está em SUCCESS
	return cc.phase == CombatController.Phase.SUCCESS
	
func is_attack_buffer_window_open(cc: CombatController) -> bool:
	if cc.phase == CombatController.Phase.RECOVER or cc.phase == CombatController.Phase.SUCCESS:
		return true
	return false
