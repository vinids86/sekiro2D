extends StateBase
class_name StateRecover

func allows_attack_input(_cc: CombatController) -> bool: return true
func allows_parry_input(_cc: CombatController) -> bool: return true
func allows_dodge_input(_cc: CombatController) -> bool: return true
func autoblock_enabled(_cc: CombatController) -> bool: return true
func allows_heavy_start(_cc: CombatController) -> bool: return true

func on_timeout(_cc: CombatController) -> void:
	# Intencionalmente vazio: a saída de RECOVER é controlada pelo AnimationDriver.on_body_end
	pass
