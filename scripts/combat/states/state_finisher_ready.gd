extends StateBase
class_name StateFinisherReady

func allows_attack_input(_cc: CombatController) -> bool: return true
func allows_heavy_start(_cc: CombatController) -> bool: return false
func allows_parry_input(_cc: CombatController) -> bool: return false
func allows_dodge_input(_cc: CombatController) -> bool: return false
func autoblock_enabled(_cc: CombatController) -> bool: return false
func allows_reentry(_cc: CombatController) -> bool: return true
func is_attack_buffer_window_open(_cc: CombatController) -> bool: return false
func is_interruptible(_cc: CombatController) -> bool: return true
