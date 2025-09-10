extends StateBase
class_name StateAttack

func allows_attack_input(cc: CombatController) -> bool:
	return false

func allows_parry_input(cc: CombatController) -> bool:
	if cc.phase != CombatController.Phase.RECOVER:
		return false
	if cc.current_kind != CombatController.AttackKind.LIGHT:
		return false
	return true

func allows_dodge_input(cc: CombatController) -> bool:
	var in_recover: bool = cc.phase == CombatController.Phase.RECOVER
	if not in_recover:
		return false

	var kind: int = cc.current_kind
	if kind == CombatController.AttackKind.LIGHT:
		return true
	if kind == CombatController.AttackKind.HEAVY:
		return true
	if kind == CombatController.AttackKind.COMBO:
		return cc.is_combo_last_attack()

	return false

func autoblock_enabled(cc: CombatController) -> bool:
	if cc.phase != CombatController.Phase.ACTIVE:
		return true
	return false

func allows_attack_buffer(cc: CombatController) -> bool:
	if cc.phase != CombatController.Phase.RECOVER:
		return false
	if cc.current_kind != CombatController.AttackKind.LIGHT:
		return false
	if cc.attack_set == null:
		return false
	var next_idx: int = cc.attack_set.next_index(cc.combo_index)
	return next_idx >= 0

func is_attack_buffer_window_open(cc: CombatController) -> bool:
	if cc.current_kind == CombatController.AttackKind.COMBO:
		return false
	return true

func allows_heavy_start(_cc: CombatController) -> bool:
	return false

func allows_reentry(_cc: CombatController) -> bool:
	return true

func get_current_movement_velocity(cc: CombatController) -> Vector2:
	if cc.current_cfg == null:
		return Vector2.ZERO
	if not (cc.current_cfg is AttackConfig):
		return Vector2.ZERO

	var cfg: AttackConfig = cc.current_cfg
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

	if not (cc.current_cfg is AttackConfig):
		cc._exit_to_idle()
		return

	var acfg: AttackConfig = cc.current_cfg

	if cc.phase == CombatController.Phase.STARTUP:
		cc._change_phase(CombatController.Phase.ACTIVE, acfg)
		var hit_time: float = cc._phase_duration_from_cfg(acfg, CombatController.Phase.ACTIVE)
		cc._safe_start_timer(hit_time)
		return

	if cc.phase == CombatController.Phase.ACTIVE:
		cc._change_phase(CombatController.Phase.RECOVER, acfg)
		cc._safe_start_timer(acfg.recovery)
		return

	if cc.phase == CombatController.Phase.RECOVER:
		if cc.current_kind == CombatController.AttackKind.COMBO:
			var next_idx_combo: int = cc._combo_hit + 1
			if next_idx_combo < cc._combo_seq.size():
				cc._combo_hit = next_idx_combo
				cc.current_cfg = cc._combo_seq[cc._combo_hit]
				cc._change_phase(CombatController.Phase.STARTUP, cc.current_cfg)
				cc._safe_start_timer((cc.current_cfg as AttackConfig).startup)
				return
			cc._exit_to_idle()
			return

		cc._exit_to_idle()
		return
