extends StateBase
class_name StateDodge

func allows_attack_input(_cc: CombatController) -> bool:
	return false

func allows_parry_input(_cc: CombatController) -> bool:
	if _cc.phase == CombatController.Phase.RECOVER:
		return true
	return false

func allows_dodge_input(_cc: CombatController) -> bool:
	return false

# A invencibilidade (iframes) agora é controlada pelo DodgeConfig
func autoblock_enabled(cc: CombatController) -> bool:
	var cfg: DodgeConfig = cc.current_cfg as DodgeConfig
	if cfg and cfg.has_iframes and cc.phase == CombatController.Phase.ACTIVE:
		return true # Nome "autoblock" aqui é um pouco enganoso, mas a função é a mesma: ignorar dano
	return false

func is_attack_buffer_window_open(cc: CombatController) -> bool:
	if cc.phase == CombatController.Phase.RECOVER:
		return true
	return false

func allows_heavy_start(_cc: CombatController) -> bool:
	return false

func allows_reentry(_cc: CombatController) -> bool:
	return false

func get_current_movement_velocity(cc: CombatController) -> Vector2:
	if not cc.current_cfg or not cc.current_cfg is DodgeConfig:
		return Vector2.ZERO

	var cfg: DodgeConfig = cc.current_cfg as DodgeConfig
	match cc.phase:
		CombatController.Phase.STARTUP:
			return cfg.startup_velocity
		CombatController.Phase.ACTIVE:
			return cfg.active_velocity
		CombatController.Phase.RECOVER:
			return cfg.recover_velocity
	
	return Vector2.ZERO

# --- on_timeout MODIFICADO para ler do config ---
func on_timeout(cc: CombatController) -> void:
	var cfg: DodgeConfig = cc.current_cfg as DodgeConfig
	if not cfg:
		cc._exit_to_idle()
		return

	if cc.phase == CombatController.Phase.STARTUP:
		cc._change_phase(CombatController.Phase.ACTIVE, cfg)
		cc._safe_start_timer(cfg.active)
		return

	if cc.phase == CombatController.Phase.ACTIVE:
		cc._change_phase(CombatController.Phase.RECOVER, cfg)
		cc._safe_start_timer(cfg.recover)
		return

	if cc.phase == CombatController.Phase.RECOVER:
		cc._exit_to_idle()
		return
