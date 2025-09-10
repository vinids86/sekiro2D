extends StateBase
class_name StateAttack

func allows_attack_input(cc: CombatController) -> bool:
	return false

func allows_parry_input(cc: CombatController) -> bool:
	# Regra atual: parry ignora buffer; janela só em RECOVER de LIGHT.
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
		# COMBO: liberar dodge apenas no último hit da sequência
		return cc.is_combo_last_attack()

	return false

func autoblock_enabled(_cc: CombatController) -> bool:
	if _cc.phase != CombatController.Phase.ACTIVE:
		return true
	return false
	
func allows_attack_buffer(cc: CombatController) -> bool:
	# Buffer apenas na cadeia leve durante RECOVER
	if cc.phase != CombatController.Phase.RECOVER:
		return false
	if cc.current_kind != CombatController.AttackKind.LIGHT:
		return false
	if cc.attack_set == null:
		return false
	var next_idx: int = cc.attack_set.next_index(cc.combo_index)
	return next_idx >= 0

func is_attack_buffer_window_open(cc: CombatController) -> bool:
	# Nunca abre janela de buffer para COMBO explícito
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
		print("[ATKST] timeout: cfg is not AttackConfig -> exit_to_idle")
		cc._exit_to_idle()
		return

	var acfg: AttackConfig = cc.current_cfg
	var path: String = acfg.resource_path
	var name: String = acfg.resource_name
	if path == "":
		path = "(built-in)"
	if name == "":
		name = "unnamed"

	if cc.phase == CombatController.Phase.STARTUP:
		# Conferir o mesmo cfg antes de entrar em ACTIVE
		print("[CFG] BEFORE ACTIVE: path=%s name=%s body=%s times{ startup=%.3f hit=%.3f rec=%.3f }"
			% [path, name, str(acfg.body_clip), acfg.startup, acfg.hit, acfg.recovery])
		cc._change_phase(CombatController.Phase.ACTIVE, acfg)
		var hit_time: float = cc._phase_duration_from_cfg(acfg, CombatController.Phase.ACTIVE)
		cc._safe_start_timer(hit_time)
		return

	if cc.phase == CombatController.Phase.ACTIVE:
		# Conferir o mesmo cfg antes de entrar em RECOVER
		print("[CFG] BEFORE RECOVER: path=%s name=%s body=%s times{ startup=%.3f hit=%.3f rec=%.3f }"
			% [path, name, str(acfg.body_clip), acfg.startup, acfg.hit, acfg.recovery])
		cc._change_phase(CombatController.Phase.RECOVER, acfg)
		cc._safe_start_timer(acfg.recovery)
		return

	if cc.phase == CombatController.Phase.RECOVER:
		# COMBO explícito avança sozinho
		if cc.current_kind == CombatController.AttackKind.COMBO:
			var next_idx_combo: int = cc._combo_hit + 1
			print("[ATKST] RECOVER (COMBO): next_hit=%d size=%d" % [next_idx_combo, cc._combo_seq.size()])
			if next_idx_combo < cc._combo_seq.size():
				cc._combo_hit = next_idx_combo
				cc.current_cfg = cc._combo_seq[cc._combo_hit]
				cc._change_phase(CombatController.Phase.STARTUP, cc.current_cfg)
				cc._safe_start_timer((cc.current_cfg as AttackConfig).startup)
				return
			print("[ATKST] combo finished -> exit_to_idle")
			cc._exit_to_idle()
			return

		print("[ATKST] RECOVER (LIGHT/HEAVY) -> exit_to_idle (buffer may consume)")
		cc._exit_to_idle()
		return
