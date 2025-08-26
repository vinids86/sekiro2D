extends StateBase
class_name StateFinisherRecover

# Padrão mais seguro: inputs OFF; se quiser igual ao RECOVER, troco
func allows_attack_input(_cc: CombatController) -> bool: return false
func allows_parry_input(_cc: CombatController) -> bool: return false
func allows_dodge_input(_cc: CombatController) -> bool: return false
func autoblock_enabled(_cc: CombatController) -> bool: return true
