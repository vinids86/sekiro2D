extends StateBase
class_name StateStunned

func allows_attack_input(_cc: CombatController) -> bool:
	return false

func allows_parry_input(_cc: CombatController) -> bool:
	return false

func allows_dodge_input(_cc: CombatController) -> bool:
	return false

func autoblock_enabled(_cc: CombatController) -> bool:
	return false

func allows_heavy_start(_cc: CombatController) -> bool:
	return false

func allows_reentry(_cc: CombatController) -> bool:
	return true
	
func get_current_movement_velocity(cc: CombatController) -> Vector2:
	if not cc.current_cfg or not cc.current_cfg is StunConfig:
		return Vector2.ZERO

	var cfg: StunConfig = cc.current_cfg as StunConfig
	match cc.phase:
		CombatController.Phase.STARTUP:
			return cfg.startup_velocity
	
	return Vector2.ZERO

func on_timeout(cc: CombatController) -> void:
	cc._exit_to_idle()
