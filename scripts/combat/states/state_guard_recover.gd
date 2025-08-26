extends StateBase
class_name StateGuardRecover

func allows_attack_input(_cc: CombatController) -> bool: return true
func allows_parry_input(_cc: CombatController) -> bool: return true
func allows_dodge_input(_cc: CombatController) -> bool: return true
func autoblock_enabled(_cc: CombatController) -> bool: return true
func allows_heavy_start(_cc: CombatController) -> bool: return true
