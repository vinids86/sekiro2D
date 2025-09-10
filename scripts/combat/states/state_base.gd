extends RefCounted
class_name StateBase

func allows_attack_input(_cc: CombatController) -> bool: return false
func allows_parry_input(_cc: CombatController) -> bool: return false
func is_parry_window(_cc: CombatController) -> bool: return false
func allows_dodge_input(_cc: CombatController) -> bool: return false
func autoblock_enabled(_cc: CombatController) -> bool: return false
func allows_heavy_start(_cc: CombatController) -> bool: return false
func allows_reentry(_cc: CombatController) -> bool: return false
func is_attack_buffer_window_open(_cc: CombatController) -> bool: return false
func allows_stamina_regen(_cc: CombatController) -> bool: return false
func refills_stamina_on_exit(_cc: CombatController) -> bool: return false
func allows_movement(_cc: CombatController) -> bool: return false

# --- NOVA FUNÇÃO ---
# Cada estado agora decide se permite que um ataque leve seja buferizado.
# Por padrão, é proibido. Apenas estados específicos (Attack, Parry) irão sobrescrever isso.
func allows_attack_buffer(_cc: CombatController) -> bool:
	return false

func on_timeout(_cc: CombatController) -> void:
	# Comportamento padrão seguro: se um estado não implementar isso, ele volta para idle.
	_cc._exit_to_idle()

func on_enter(_cc: CombatController, _cfg: StateConfig, _args: StateArgs) -> void: pass
func on_exit(_cc: CombatController, _cfg: StateConfig) -> void: pass
