extends StateBase
class_name StateDodge

var _dir: int = 0

func allows_attack_input(_cc: CombatController) -> bool:
	return false

func allows_parry_input(_cc: CombatController) -> bool:
	if _cc.phase == CombatController.Phase.RECOVER:
		return true
	else:
		return false

func allows_dodge_input(_cc: CombatController) -> bool:
	return false

func autoblock_enabled(_cc: CombatController) -> bool:
	return false

func is_attack_buffer_window_open(cc: CombatController) -> bool:
	if cc.phase == CombatController.Phase.RECOVER:
		return true
	return false

func allows_heavy_start(_cc: CombatController) -> bool:
	return false

func allows_reentry(_cc: CombatController) -> bool:
	return false

func on_enter(_cc: CombatController, _cfg: StateConfig, _args: StateArgs) -> void:
	var da: DodgeArgs = _args as DodgeArgs
	if da != null:
		_dir = da.dir
	else:
		_dir = 0

func on_exit(_cc: CombatController, _cfg: StateConfig) -> void:
	_dir = 0
