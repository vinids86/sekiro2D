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
	if cc.has_heavy():
		var ok_h: bool = try_attack_heavy(cc.peek_heavy_cfg(), cc.peek_heavy_dir(), true)
		if ok_h:
			cc.clear_heavy()
			cc.clear_buffer()
		return

	# 2) Demais ações
	var act: int = cc.peek_action()
	match act:
		CombatController.ActionType.ATTACK:
			var dir_a: Vector2 = cc.peek_direction()
			var ok_a: bool = try_attack(true, dir_a)
			if ok_a:
				cc.current_attack_direction = dir_a
				cc.clear_buffer()
		CombatController.ActionType.PARRY:
			var dir_p: Vector2 = cc.peek_direction()
			var ok_p: bool = try_parry(true, dir_p)
			if ok_p:
				cc.clear_buffer()
		CombatController.ActionType.DODGE:
			var dir_d: Vector2 = cc.peek_direction()
			var ok_d: bool = try_dodge(true, dir_d)
			if ok_d:
				cc.clear_buffer()
		_:
			pass  # nada no buffer

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

	var attack: AttackConfig = cc.get_current_attack()
	if attack == null:
		return false

	if not cc._iface["has_stamina"].call(attack.stamina_cost):
		# sem stamina → bufferiza se não veio do buffer
		if not from_buffer:
			cc.queue_action(CombatController.ActionType.ATTACK, dir, cc.input_buffer_duration)
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
		if cc.can_chain_next_on_soft(attack):
			cc.on_attack_finished(false)
			cc.combo_in_progress = true
			cc.combo_timeout_timer = cc.combo_timeout_duration
			cc.current_attack_direction = dir
			cc.clear_buffer()
			cc.change_state(CombatTypes.CombatState.STARTUP)
			return true

	# Não deu agora → bufferiza se não veio do buffer
	if not from_buffer:
		cc.queue_action(CombatController.ActionType.ATTACK, dir, cc.input_buffer_duration)
	return false

# =========================================================
# =============== ATAQUE PESADO (HEAVY) ===================
# =========================================================
func try_attack_heavy(cfg: AttackConfig, dir: Vector2 = Vector2.ZERO, from_buffer: bool = false) -> bool:
	if cc == null or cfg == null:
		return false

	if cc.combat_state == CombatTypes.CombatState.STUNNED:
		return false
	if cc.combat_state == CombatTypes.CombatState.GUARD_BROKEN:
		return false

	if not cc._iface["has_stamina"].call(cfg.stamina_cost):
		if not from_buffer:
			cc.queue_heavy(cfg, dir, cc.input_buffer_duration)
		return false

	# Início no IDLE
	if cc.combat_state == CombatTypes.CombatState.IDLE:
		cc.override_next_attack(cfg)
		cc.current_attack_direction = dir
		cc.combo_timeout_timer = cc.combo_timeout_duration
		cc.combo_in_progress = true
		cc.change_state(CombatTypes.CombatState.STARTUP)
		return true

	# Chain na soft-recovery
	var curr: AttackConfig = cc.get_current_attack()
	if cc.combat_state == CombatTypes.CombatState.RECOVERING and cc.recovering_phase == 2 and cc.can_chain_next_on_soft(curr):
		cc.on_attack_finished(false)
		cc.override_next_attack(cfg)
		cc.combo_in_progress = true
		cc.combo_timeout_timer = cc.combo_timeout_duration
		cc.current_attack_direction = dir
		cc.clear_buffer()
		cc.change_state(CombatTypes.CombatState.STARTUP)
		return true

	# Não deu → bufferiza (mantém cfg + dir)
	if not from_buffer:
		cc.queue_heavy(cfg, dir, cc.input_buffer_duration)
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
			cc.queue_action(CombatController.ActionType.PARRY, dir, cc.input_buffer_duration)
		return false
	if not cc._iface["has_stamina"].call(1.0):
		if not from_buffer:
			cc.queue_action(CombatController.ActionType.PARRY, dir, cc.input_buffer_duration)
		return false

	# Em quais estados pode entrar em parry?
	var attack: AttackConfig = cc.get_current_attack()
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
			cc.queue_action(CombatController.ActionType.PARRY, dir, cc.input_buffer_duration)
		return false

	cc.change_state(CombatTypes.CombatState.PARRY_ACTIVE)
	if not from_buffer:
		cc.clear_buffer()
	return true

# =========================================================
# ===================== DODGE =============================
# =========================================================
func try_dodge(from_buffer: bool = false, dir: Vector2 = Vector2.ZERO) -> bool:
	if cc == null:
		return false

	if cc.has_effect(CombatController.EFFECT_DODGE_COOLDOWN):
		if not from_buffer:
			cc.queue_action(CombatController.ActionType.DODGE, dir, cc.input_buffer_duration)
		return false
	if not cc._iface["has_stamina"].call(cc.dodge_stamina_cost):
		if not from_buffer:
			cc.queue_action(CombatController.ActionType.DODGE, dir, cc.input_buffer_duration)
		return false

	# Só do IDLE por enquanto
	if cc.combat_state != CombatTypes.CombatState.IDLE:
		if not from_buffer:
			cc.queue_action(CombatController.ActionType.DODGE, dir, cc.input_buffer_duration)
		return false

	# Não altera facing nem current_attack_direction (dodge sem deslocamento)
	cc.change_state(CombatTypes.CombatState.DODGE_STARTUP)
	if not from_buffer:
		cc.clear_buffer()
	return true

# =========================================================
# ============ FIM DE ATAQUE / COMBO INDEX ================
# =========================================================
func on_attack_finished(was_parried: bool) -> void:
	if cc == null:
		return
	var attack: AttackConfig = cc.get_current_attack()
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
	cc.override_next_attack(null)
