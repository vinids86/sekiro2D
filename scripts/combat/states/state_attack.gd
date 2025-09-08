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

func is_attack_buffer_window_open(cc: CombatController) -> bool:
	if cc.current_kind == CombatController.AttackKind.COMBO:
		return false
	return true

func allows_heavy_start(_cc: CombatController) -> bool:
	return false

func allows_reentry(_cc: CombatController) -> bool:
	return false

# --- NOVA FUNÇÃO ---
# Retorna a velocidade de movimento que deve ser aplicada neste frame,
# com base na fase atual do combate.
func get_current_movement_velocity(cc: CombatController) -> Vector2:
	if not cc.current_cfg:
		return Vector2.ZERO

	# Garante que estamos lidando com um AttackConfig que tem as propriedades de velocidade
	if not cc.current_cfg is AttackConfig:
		return Vector2.ZERO

	var cfg: AttackConfig = cc.current_cfg as AttackConfig
	match cc.phase:
		CombatController.Phase.STARTUP:
			return cfg.startup_velocity
		CombatController.Phase.ACTIVE:
			return cfg.active_velocity
		CombatController.Phase.RECOVER:
			return cfg.recover_velocity
	
	return Vector2.ZERO


func on_timeout(cc: CombatController) -> void:
	if cc.current_cfg == null:
		cc._exit_to_idle()
		return

	if cc.phase == CombatController.Phase.STARTUP:
		cc._change_phase(CombatController.Phase.ACTIVE, cc.current_cfg)
		var hit_time: float = cc._phase_duration_from_cfg(cc.current_cfg, CombatController.Phase.ACTIVE)
		cc._safe_start_timer(hit_time)
		return

	if cc.phase == CombatController.Phase.ACTIVE:
		cc._change_phase(CombatController.Phase.RECOVER, cc.current_cfg)
		cc._safe_start_timer(cc.current_cfg.recovery)
		return

	if cc.phase == CombatController.Phase.RECOVER:
		if cc.current_kind == CombatController.AttackKind.COMBO:
			var next_idx_combo: int = cc._combo_hit + 1
			if next_idx_combo < cc._combo_seq.size():
				cc._combo_hit = next_idx_combo
				cc.current_cfg = cc._combo_seq[cc._combo_hit]
				cc._change_phase(CombatController.Phase.STARTUP, cc.current_cfg)
				cc._safe_start_timer(cc.current_cfg.startup)
				return
			cc._exit_to_idle()
			return

		if cc.buffer_controller and cc.buffer_controller.try_consume(cc):
			return

		cc._exit_to_idle()
		return
