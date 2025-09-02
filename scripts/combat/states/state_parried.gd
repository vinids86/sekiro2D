extends StateBase
class_name StateParried

func allows_attack_input(_cc: CombatController) -> bool:
	return false

func allows_parry_input(_cc: CombatController) -> bool:
	return true

func allows_dodge_input(_cc: CombatController) -> bool:
	return true

func autoblock_enabled(_cc: CombatController) -> bool:
	return false

func is_attack_buffer_window_open(_cc: CombatController) -> bool:
	# Em PARRIED queremos capturar ataque no buffer.
	# O controller decide quando consumir; aqui só liberamos a janela.
	return true

func allows_reentry(_cc: CombatController) -> bool:
	return false

func on_enter(_cc: CombatController, _cfg: AttackConfig) -> void:
	pass

func on_exit(_cc: CombatController) -> void:
	pass
