extends RefCounted
class_name CombatActions

var cc: CombatController = null

func setup(controller: CombatController) -> void:
	cc = controller

# =========================================================
# =============== EXECUÇÃO DO BUFFER ======================
# =========================================================
func try_execute_buffer() -> void:
	if cc == null:
		return

	# 1) Heavy em buffer tem prioridade
	if cc._queued_heavy_cfg != null:
		var ok_h: bool = try_attack_heavy(cc._queued_heavy_cfg, cc._queued_heavy_dir, true)
		if ok_h:
			cc._queued_heavy_cfg = null
			cc._queued_heavy_dir = Vector2.ZERO
			_clear_buffer()
		return

	# 2) Demais ações
	match cc.queued_action:
		cc.ActionType.ATTACK:
			var ok_a: bool = try_attack(true, cc.queued_direction)
			if ok_a:
				cc.current_attack_direction = cc.queued_direction
				_clear_buffer()
		cc.ActionType.PARRY:
			var ok_p: bool = try_parry(true, cc.queued_direction)
			if ok_p:
				_clear_buffer()
		cc.ActionType.DODGE:
			var ok_d: bool = try_dodge(true, cc.queued_direction)
			if ok_d:
				_clear_buffer()

# =========================================================
# =============== ATAQUE LEVE / CHAIN =====================
# =========================================================
func try_attack(from_buffer: bool = false, dir: Vector2 = Vector2.ZERO) -> bool:
	if cc == null:
		return false

	# Não ataca atordoado/guard broken
	if cc.combat_state == CombatTypes.CombatState.STUNNED:
		return false
	if cc.combat_state == CombatTypes.CombatState.GUARD_BROKEN:
		return false

	# Ataque atual/config
	var seq: Array = cc._iface["get_attack_sequence"].call()
	if seq.is_empty():
		return false

	var attack: AttackConfig = cc._current_attack()
	if attack == null:
		return false
	if not cc._iface["has_stamina"].call(attack.stamina_cost):
		# sem stamina → bufferiza se não veio do buffer
		if not from_buffer:
			_queue_action(cc.ActionType.ATTACK, dir)
		return false

	# Início de combo a partir do IDLE
	if cc.combat_state == CombatTypes.CombatState.IDLE:
		cc.current_attack_direction = dir
		cc.combo_timeout_timer = cc.combo_timeout_duration
		cc.combo_in_progress = true
		cc.change_state(CombatTypes.CombatState.STARTUP)
		return true

	# Chain na soft-recovery (fase 2)
	if cc.combat_state == CombatTypes.CombatState.RECOVERING and cc.recovering_phase == 2:
		if cc._can_chain_next_on_soft(attack):
			cc.on_attack_finished(false)
			cc.combo_in_progress = true
			cc.combo_timeout_timer = cc.combo_timeout_duration
			cc.current_attack_direction = dir
			_clear_buffer()
			cc.change_state(CombatTypes.CombatState.STARTUP)
			return true

	# Não deu agora → bufferiza se não veio do buffer
	if not from_buffer:
		_queue_action(cc.ActionType.ATTACK, dir)
	return false

# =========================================================
# =============== ATAQUE PESADO (HEAVY) ===================
# =========================================================
func try_attack_heavy(cfg: AttackConfig, dir: Vector2 = Vector2.ZERO, from_buffer: bool = false) -> bool:
	if cc == null:
		return false
	if cfg == null:
		return false

	if cc.combat_state == CombatTypes.CombatState.STUNNED:
		return false
	if cc.combat_state == CombatTypes.CombatState.GUARD_BROKEN:
		return false

	if not cc._iface["has_stamina"].call(cfg.stamina_cost):
		if not from_buffer:
			# mantém heavy enfileirado
			cc._queued_heavy_cfg = cfg
			cc._queued_heavy_dir = dir
			cc.buffer_timer = cc.input_buffer_duration
		return false

	# Início no IDLE
	if cc.combat_state == CombatTypes.CombatState.IDLE:
		cc._override_attack = cfg
		cc.current_attack_direction = dir
		cc.combo_timeout_timer = cc.combo_timeout_duration
		cc.combo_in_progress = true
		cc.change_state(CombatTypes.CombatState.STARTUP)
		return true

	# Chain na soft-recovery
	var curr: AttackConfig = cc._current_attack()
	if cc.combat_state == CombatTypes.CombatState.RECOVERING and cc.recovering_phase == 2 and cc._can_chain_next_on_soft(curr):
		cc.on_attack_finished(false)
		cc._override_attack = cfg
		cc.combo_in_progress = true
		cc.combo_timeout_timer = cc.combo_timeout_duration
		cc.current_attack_direction = dir
		_clear_buffer()
		cc.change_state(CombatTypes.CombatState.STARTUP)
		return true

	# Não deu → bufferiza (mantém cfg + dir)
	if not from_buffer:
		cc._queued_heavy_cfg = cfg
		cc._queued_heavy_dir = dir
		cc.buffer_timer = cc.input_buffer_duration
	return false

# =========================================================
# ===================== PARRY =============================
# =========================================================
func try_parry(from_buffer: bool = false, dir: Vector2 = Vector2.ZERO) -> bool:
	if cc == null:
		return false

	# Cooldown ou já ativo
	if cc.combat_state == CombatTypes.CombatState.PARRY_ACTIVE:
		return false
	if cc.has_effect(CombatController.EFFECT_PARRY_COOLDOWN):
		if not from_buffer:
			_queue_action(cc.ActionType.PARRY, dir)
		return false
	if not cc._iface["has_stamina"].call(1.0):
		if not from_buffer:
			_queue_action(cc.ActionType.PARRY, dir)
		return false

	# Em quais estados pode entrar em parry?
	var attack: AttackConfig = cc._current_attack()
	var can: bool = false
	match cc.combat_state:
		CombatTypes.CombatState.IDLE:
			can = true
		CombatTypes.CombatState.STARTUP:
			can = (attack != null and attack.can_cancel_to_parry_on_startup)
		CombatTypes.CombatState.ATTACKING:
			can = (attack != null and attack.can_cancel_to_parry_on_active)
		CombatTypes.CombatState.RECOVERING:
			can = false
		CombatTypes.CombatState.STUNNED:
			can = true
		CombatTypes.CombatState.GUARD_BROKEN:
			can = false
		_:
			can = false

	if not can:
		if not from_buffer and not cc.has_effect(CombatController.EFFECT_PARRY_COOLDOWN):
			_queue_action(cc.ActionType.PARRY, dir)
		return false

	cc.change_state(CombatTypes.CombatState.PARRY_ACTIVE)
	if not from_buffer:
		_clear_buffer()
		cc.queued_direction = dir
	return true

# =========================================================
# ===================== DODGE =============================
# =========================================================
func try_dodge(from_buffer: bool = false, dir: Vector2 = Vector2.ZERO) -> bool:
	if cc == null:
		return false

	if cc.has_effect(CombatController.EFFECT_DODGE_COOLDOWN):
		if not from_buffer:
			_queue_action(cc.ActionType.DODGE, dir)
		return false
	if not cc._iface["has_stamina"].call(cc.dodge_stamina_cost):
		if not from_buffer:
			_queue_action(cc.ActionType.DODGE, dir)
		return false

	# Só do IDLE por enquanto
	if cc.combat_state != CombatTypes.CombatState.IDLE:
		if not from_buffer:
			_queue_action(cc.ActionType.DODGE, dir)
		return false

	# Não altera facing nem current_attack_direction (dodge sem deslocamento)
	cc.change_state(CombatTypes.CombatState.DODGE_STARTUP)
	if not from_buffer:
		_clear_buffer()
	return true

# =========================================================
# ============ FIM DE ATAQUE / COMBO INDEX ================
# =========================================================
func on_attack_finished(was_parried: bool) -> void:
	if cc == null:
		return
	var attack: AttackConfig = cc._current_attack()
	if was_parried or (attack != null and attack.ends_combo):
		cc.combo_index = 0
		cc.combo_in_progress = false
	else:
		var seq: Array = cc._iface["get_attack_sequence"].call()
		if not seq.is_empty():
			var next_idx: int = cc.combo_index + 1
			if next_idx >= seq.size():
				next_idx = 0
			cc.combo_index = next_idx
	cc._override_attack = null

# =========================================================
# ==================== HELPERS ============================
# =========================================================
func _queue_action(act: CombatController.ActionType, dir: Vector2) -> void:
	cc.queued_action = act
	cc.queued_direction = dir
	cc.buffer_timer = cc.input_buffer_duration

func _clear_buffer() -> void:
	cc.queued_action = CombatController.ActionType.NONE
	cc.queued_direction = Vector2.ZERO
	cc.buffer_timer = 0.0
