extends Node
class_name CombatController

# ---------------- Enums ----------------
enum StunKind { NONE, BLOCKED, PARRIED }
enum CombatState { IDLE, STARTUP, ATTACKING, PARRY_ACTIVE, PARRY_SUCCESS, RECOVERING, STUNNED }
enum ActionType { NONE, ATTACK, PARRY }

const EFFECT_PARRY_COOLDOWN := "parry_cooldown"

# ---------------- Sinais ----------------
signal state_changed(old_state: int, new_state: int, attack_direction: Vector2)
signal play_stream(stream: AudioStream)
signal hitbox_active_changed(is_on: bool)
signal attack_step(distance_px: float)
# quem escutar pode afastar atacante/defensor após parry pesado neutro (pixels)
signal request_push_apart(pixels: float)

# ---------------- Parâmetros ----------------
@export var parry_window := 0.4
@export var parry_cooldown := 0.2
@export var block_stun := 1.0
@export var input_buffer_duration := 0.4
@export var block_stamina_cost := 10.0
@export var combo_timeout_duration := 2.0
@export var chain_grace := 0.12
@export var debug_logs := true
@export var sfx_parry_active: AudioStream
@export var sfx_parry_success: AudioStream

# Lockouts de parry (leve = vira turno; pesado = neutro)
@export var parry_light_lockout_attacker := 0.60
@export var parry_light_lockout_defender := 0.20
@export var parry_heavy_neutral_lockout := 0.45
@export var parry_heavy_pushback_pixels := 32.0

# Duração base do PARRY_SUCCESS (defensor); pode ser sobrescrita no resolver
@export var parry_success_base_lockout := 0.4

# ---------------- Estado interno ----------------
var combo_timeout_timer := 0.0
var combo_in_progress := false
var combo_index := 0

var combat_state: CombatState = CombatState.IDLE
var previous_state: CombatState = CombatState.IDLE
var state_timer: float = 0.0
var owner_node: Node

var queued_action: ActionType = ActionType.NONE
var queued_direction: Vector2 = Vector2.ZERO
var buffer_timer: float = 0.0

var current_attack_direction: Vector2 = Vector2.ZERO
var status_effects: Dictionary = {}
var did_parry_succeed := false

var recovering_phase := 0
var step_emitted := false
var active_clock := 0.0
var _prev_active_clock := 0.0

# Relógio da janela de parry (conta enquanto em PARRY_ACTIVE)
var parry_clock := 0.0

# Override dinâmico de lockouts
var parry_success_lockout_override := -1.0
var stun_lockout_override := -1.0

# Sinaliza para lógica externa se o último parry foi contra HEAVY
var last_parry_was_heavy := false

var stun_kind: StunKind = StunKind.NONE

# Lockout forçado (não segue hard/soft da RECOVERING normal) — mantido p/ usos gerais
var _force_recover_timer := -1.0
var _forced_lockout_active := false

# === NOVO: suporte a ataque pesado (override + buffer próprio) ===
var _override_attack: AttackConfig = null
var _queued_heavy_cfg: AttackConfig = null
var _queued_heavy_dir: Vector2 = Vector2.ZERO

var transitions := {
	CombatState.IDLE:          [CombatState.STARTUP, CombatState.PARRY_ACTIVE, CombatState.STUNNED],
	CombatState.STARTUP:       [CombatState.ATTACKING, CombatState.PARRY_ACTIVE, CombatState.STUNNED, CombatState.RECOVERING],
	CombatState.ATTACKING:     [CombatState.RECOVERING, CombatState.STUNNED, CombatState.PARRY_ACTIVE],
	CombatState.RECOVERING:    [CombatState.IDLE, CombatState.STUNNED, CombatState.STARTUP],
	CombatState.PARRY_ACTIVE:  [CombatState.PARRY_SUCCESS, CombatState.IDLE, CombatState.STUNNED, CombatState.RECOVERING],
	CombatState.PARRY_SUCCESS: [CombatState.IDLE, CombatState.STUNNED],
	CombatState.STUNNED:       [CombatState.IDLE, CombatState.STUNNED, CombatState.PARRY_ACTIVE]
}

# --- Interface opcional injetada (desacoplado de Player/Enemy) ---
var _iface: Dictionary = {
	"get_attack_sequence": func() -> Array: return owner_node.attack_sequence if owner_node and "attack_sequence" in owner_node else [],
	"has_stamina":        func(cost: float) -> bool: return owner_node.has_stamina(cost) if owner_node and owner_node.has_method("has_stamina") else true,
	"consume_stamina":    func(cost: float) -> void: if owner_node and owner_node.has_method("consume_stamina"): owner_node.consume_stamina(cost)
}

func setup(owner: Node, iface: Dictionary = {}) -> void:
	owner_node = owner
	iface.merge(_iface, false)
	_iface = iface

func _process(delta: float) -> void:
	if buffer_timer > 0.0:
		buffer_timer -= delta
		if buffer_timer <= 0.0:
			queued_action = ActionType.NONE
			# expira também buffer pesado
			_queued_heavy_cfg = null
			_queued_heavy_dir = Vector2.ZERO

	if can_act() and (queued_action != ActionType.NONE or _queued_heavy_cfg != null):
		try_execute_buffer()

	if state_timer > 0.0:
		state_timer -= delta
		if state_timer <= 0.0 and can_auto_advance():
			auto_advance_state()

	var expired := []
	for k in status_effects.keys():
		status_effects[k] -= delta
		if status_effects[k] <= 0.0:
			expired.append(k)
	for k in expired:
		status_effects.erase(k)

	if combo_in_progress:
		combo_timeout_timer -= delta
		if combo_timeout_timer <= 0.0:
			combo_index = 0
			combo_in_progress = false

	if combat_state == CombatState.ATTACKING:
		_prev_active_clock = active_clock
		active_clock += delta
		_check_attack_step(active_clock, _prev_active_clock)

	if combat_state == CombatState.PARRY_ACTIVE:
		parry_clock += delta

func can_auto_advance() -> bool:
	return [CombatState.STARTUP, CombatState.ATTACKING, CombatState.RECOVERING,
			CombatState.STUNNED, CombatState.PARRY_ACTIVE, CombatState.PARRY_SUCCESS].has(combat_state)

func auto_advance_state() -> void:
	match combat_state:
		CombatState.STARTUP:
			change_state(CombatState.ATTACKING)
		CombatState.ATTACKING:
			change_state(CombatState.RECOVERING)
		CombatState.RECOVERING:
			# Se estamos em lockout forçado, sair direto para IDLE ao fim do timer
			if _forced_lockout_active:
				_forced_lockout_active = false
			if _force_recover_timer >= 0.0:
				_force_recover_timer = -1.0
				change_state(CombatState.IDLE)
				return

			var attack = _current_attack()
			if recovering_phase == 1:
				recovering_phase = 2
				state_timer = attack.recovery_soft if attack else 0.0
				if buffer_timer > 0.0: buffer_timer = max(buffer_timer, chain_grace)
				if (_queued_heavy_cfg != null and _can_chain_next_on_soft(attack)):
					# chain para HEAVY
					on_attack_finished(did_parry_succeed)
					combo_in_progress = true
					combo_timeout_timer = combo_timeout_duration
					current_attack_direction = _queued_heavy_dir
					# iniciar pesado agora
					_start_heavy_from_buffer()
					return
				elif queued_action == ActionType.ATTACK and _can_chain_next_on_soft(attack):
					on_attack_finished(did_parry_succeed)
					combo_in_progress = true
					combo_timeout_timer = combo_timeout_duration
					current_attack_direction = queued_direction
					_clear_buffer()
					change_state(CombatState.STARTUP)
					return
				elif state_timer <= 0.0:
					_finish_recover_and_exit()
			else:
				_finish_recover_and_exit()
		CombatState.STUNNED:
			change_state(CombatState.IDLE)
		CombatState.PARRY_SUCCESS:
			change_state(CombatState.IDLE)
		CombatState.PARRY_ACTIVE:
			if did_parry_succeed: change_state(CombatState.PARRY_SUCCESS)
			else: change_state(CombatState.IDLE)

func _finish_recover_and_exit() -> void:
	# Se for lockout forçado, não aplicar lógica de combo/chain
	if _forced_lockout_active or _force_recover_timer >= 0.0:
		_forced_lockout_active = false
		_force_recover_timer = -1.0
		change_state(CombatState.IDLE)
		return

	on_attack_finished(did_parry_succeed)
	if _queued_heavy_cfg != null and buffer_timer > 0.0:
		current_attack_direction = _queued_heavy_dir
		_start_heavy_from_buffer()
	elif queued_action == ActionType.ATTACK and buffer_timer > 0.0:
		current_attack_direction = queued_direction
		_clear_buffer()
		change_state(CombatState.STARTUP)
	else:
		change_state(CombatState.IDLE)

func change_state(new_state: CombatState) -> void:
	if not transitions.get(combat_state, []).has(new_state):
		return
	if debug_logs:
		print("%s mudando estado: %s → %s" % [
			owner_node.name,
			CombatState.keys()[combat_state],
			CombatState.keys()[new_state]
		])
	previous_state = combat_state
	_on_exit_state(combat_state)
	combat_state = new_state
	_on_enter_state(combat_state)
	emit_signal("state_changed", previous_state, new_state, current_attack_direction)

func _on_enter_state(state: CombatState) -> void:
	did_parry_succeed = false
	var attack = _current_attack()

	match state:
		CombatState.STARTUP:
			if attack:
				state_timer = attack.startup
				_iface.consume_stamina.call(attack.stamina_cost)

		CombatState.ATTACKING:
			if attack:
				state_timer = attack.active_duration
				active_clock = 0.0
				_prev_active_clock = 0.0
				step_emitted = false
				hitbox_active_changed.emit(true)
				if attack.attack_sound:
					play_stream.emit(attack.attack_sound)

		CombatState.RECOVERING:
			var forced := _force_recover_timer
			if forced >= 0.0:
				_forced_lockout_active = true
				recovering_phase = 0
				state_timer = forced
			else:
				recovering_phase = 1
				state_timer = attack.recovery_hard if attack else 0.0
				if buffer_timer > 0.0:
					buffer_timer = max(buffer_timer, chain_grace)

		CombatState.PARRY_ACTIVE:
			state_timer = parry_window
			parry_clock = 0.0
			play_stream.emit(sfx_parry_active)

		CombatState.STUNNED:
			var dur := block_stun
			if stun_lockout_override >= 0.0:
				dur = stun_lockout_override
				stun_lockout_override = -1.0
			state_timer = dur
			queued_action = ActionType.NONE
			buffer_timer = 0.0
			# se estava com HEAVY enfileirado, limpa
			_queued_heavy_cfg = null
			_queued_heavy_dir = Vector2.ZERO

		CombatState.PARRY_SUCCESS:
			var dur := parry_success_base_lockout
			if parry_success_lockout_override >= 0.0:
				dur = parry_success_lockout_override
				parry_success_lockout_override = -1.0
			state_timer = dur
			play_stream.emit(sfx_parry_success)

		CombatState.IDLE:
			recovering_phase = 0
			await get_tree().process_frame
			try_execute_buffer()

func _on_exit_state(state: CombatState) -> void:
	match state:
		CombatState.STARTUP, CombatState.ATTACKING, CombatState.PARRY_ACTIVE:
			if state == CombatState.PARRY_ACTIVE:
				apply_effect(EFFECT_PARRY_COOLDOWN, parry_cooldown)
			if state == CombatState.ATTACKING:
				hitbox_active_changed.emit(false)

func apply_effect(name: String, duration: float) -> void:
	status_effects[name] = duration

func has_effect(name: String) -> bool:
	return status_effects.has(name)

func try_execute_buffer() -> void:
	if not can_act(): return
	# Prioriza HEAVY enfileirado
	if _queued_heavy_cfg != null:
		if try_attack_heavy(_queued_heavy_cfg, _queued_heavy_dir, true):
			_queued_heavy_cfg = null
			_queued_heavy_dir = Vector2.ZERO
			_clear_buffer() # limpa leve que porventura estava junto
		return

	match queued_action:
		ActionType.ATTACK:
			if try_attack(true, queued_direction):
				current_attack_direction = queued_direction
				_clear_buffer()
		ActionType.PARRY:
			if try_parry(true, queued_direction):
				_clear_buffer()

func try_attack(from_buffer := false, dir := Vector2.ZERO) -> bool:
	if combat_state == CombatState.STUNNED:
		return false

	var seq: Array = (_iface["get_attack_sequence"] as Callable).call()
	if seq.is_empty():
		return false

	# Usa o ataque atual da sequência (sem override)
	var attack = (_override_attack if _override_attack != null else _current_attack())
	if not attack or not _iface.has_stamina.call(attack.stamina_cost):
		return false

	if combat_state == CombatState.IDLE:
		current_attack_direction = dir
		combo_timeout_timer = combo_timeout_duration
		combo_in_progress = true
		# se houver override (heavy), STARTUP usará ele
		change_state(CombatState.STARTUP)
		return true
	elif combat_state == CombatState.RECOVERING and recovering_phase == 2:
		if _can_chain_next_on_soft(attack):
			on_attack_finished(false)
			combo_in_progress = true
			combo_timeout_timer = combo_timeout_duration
			current_attack_direction = dir
			_clear_buffer()
			change_state(CombatState.STARTUP)
			return true

	if not from_buffer:
		queued_action = ActionType.ATTACK
		queued_direction = dir
		buffer_timer = input_buffer_duration
	return false

# === NOVO: iniciar HEAVY ===
func try_attack_heavy(cfg: AttackConfig, dir := Vector2.ZERO, from_buffer := false) -> bool:
	if combat_state == CombatState.STUNNED:
		return false
	if cfg == null:
		return false
	if not _iface.has_stamina.call(cfg.stamina_cost):
		return false

	# IDLE → inicia imediato com override
	if combat_state == CombatState.IDLE:
		_override_attack = cfg
		current_attack_direction = dir
		combo_timeout_timer = combo_timeout_duration
		combo_in_progress = true
		change_state(CombatState.STARTUP)
		return true

	# Em RECOVERING fase 2 → chain se permitido
	var curr: AttackConfig = _current_attack()
	if combat_state == CombatState.RECOVERING and recovering_phase == 2 and _can_chain_next_on_soft(curr):
		on_attack_finished(false)
		_override_attack = cfg
		combo_in_progress = true
		combo_timeout_timer = combo_timeout_duration
		current_attack_direction = dir
		_clear_buffer()
		change_state(CombatState.STARTUP)
		return true

	# Caso contrário, bufferiza pesado
	if not from_buffer:
		_queued_heavy_cfg = cfg
		_queued_heavy_dir = dir
		buffer_timer = input_buffer_duration
	return false

func _start_heavy_from_buffer() -> void:
	if _queued_heavy_cfg == null:
		return
	_override_attack = _queued_heavy_cfg
	_queued_heavy_cfg = null
	change_state(CombatState.STARTUP)

func on_attack_finished(was_parried: bool) -> void:
	var attack = _current_attack()
	# Decide combo antes de limpar o override
	if was_parried or (attack and attack.ends_combo):
		combo_index = 0
		combo_in_progress = false
	else:
		var seq: Array = (_iface["get_attack_sequence"] as Callable).call()
		if not seq.is_empty():
			combo_index = (combo_index + 1) % seq.size()
	# HEAVY finalizado → limpa override
	_override_attack = null

func can_transition_to_parry() -> bool:
	if combat_state == CombatState.PARRY_ACTIVE: return false
	if has_effect(EFFECT_PARRY_COOLDOWN): return false
	if not _iface.has_stamina.call(1.0): return false
	var attack = _current_attack()
	match combat_state:
		CombatState.IDLE: return true
		CombatState.STARTUP: return attack and attack.can_cancel_to_parry_on_startup
		CombatState.ATTACKING: return attack and attack.can_cancel_to_parry_on_active
		CombatState.RECOVERING: return false
		CombatState.STUNNED: return true
		_: return false

func try_parry(from_buffer := false, dir := Vector2.ZERO) -> bool:
	if not can_transition_to_parry():
		# Se falhou por cooldown, NÃO bufferiza (ignora input)
		if not from_buffer and not has_effect(EFFECT_PARRY_COOLDOWN):
			queued_action = ActionType.PARRY
			queued_direction = dir
			buffer_timer = input_buffer_duration
		return false

	change_state(CombatState.PARRY_ACTIVE)
	if not from_buffer:
		_clear_buffer()
		queued_direction = dir
	return true

# Stuns diretos (ex.: levou parry, levou block forte)
func force_stun(duration: float, as_parried := true) -> void:
	stun_kind = StunKind.PARRIED if as_parried else StunKind.BLOCKED
	stun_lockout_override = max(0.0, duration)
	change_state(CombatState.STUNNED)

func on_parried() -> void:
	stun_kind = StunKind.PARRIED
	change_state(CombatState.STUNNED)

func on_blocked() -> void:
	stun_kind = StunKind.BLOCKED
	change_state(CombatState.STUNNED)
	_iface.consume_stamina.call(block_stamina_cost)

func can_act() -> bool:
	return combat_state in [CombatState.IDLE, CombatState.RECOVERING]

func _current_attack():
	# Se houver override (HEAVY), ele manda:
	if _override_attack != null:
		return _override_attack
	var seq: Array = _iface.get_attack_sequence.call()
	if seq.is_empty(): return null
	return seq[combo_index]

func _can_chain_next_on_soft(attack) -> bool:
	return attack and attack.can_chain_next_attack_on_soft_recovery

func _clear_buffer() -> void:
	queued_action = ActionType.NONE
	queued_direction = Vector2.ZERO
	buffer_timer = 0.0
	# não mexe no buffer pesado aqui; ele tem ciclo próprio

func get_current_attack():
	return _current_attack()

func _check_attack_step(t: float, prev_t: float) -> void:
	var atk = _current_attack()
	if not atk or step_emitted or atk.step_distance_px == 0.0:
		return
	if prev_t < atk.step_time_in_active and t >= atk.step_time_in_active:
		step_emitted = true
		attack_step.emit(atk.step_distance_px)

# ---------------- Helpers p/ parry e lockouts ----------------

# Lockout "seco": ignora a lógica normal de RECOVERING (mantido p/ outros usos)
func force_lockout(duration: float) -> void:
	_force_recover_timer = max(0.0, duration)
	_forced_lockout_active = true
	queued_action = ActionType.NONE
	buffer_timer = 0.0
	# cancela qualquer heavy enfileirado
	_queued_heavy_cfg = null
	_queued_heavy_dir = Vector2.ZERO
	change_state(CombatState.RECOVERING)

# Parry LEVE: vira o turno (atacante STUNNED longo; defensor PARRY_SUCCESS curto)
func resolve_parry_light(attacker: CombatController, defender: CombatController) -> void:
	defender.did_parry_succeed = true
	defender.last_parry_was_heavy = false
	defender.parry_success_lockout_override = defender.parry_light_lockout_defender
	if defender.combat_state == CombatState.PARRY_ACTIVE:
		defender.change_state(CombatState.PARRY_SUCCESS)
	attacker.force_stun(parry_light_lockout_attacker, true)

# Parry PESADO: neutro — ambos com mesmo lockout; afastamento
func resolve_parry_heavy_neutral(attacker: CombatController, defender: CombatController) -> void:
	defender.did_parry_succeed = true
	defender.last_parry_was_heavy = true
	defender.parry_success_lockout_override = defender.parry_heavy_neutral_lockout
	if defender.combat_state == CombatState.PARRY_ACTIVE:
		defender.change_state(CombatState.PARRY_SUCCESS)
	attacker.force_stun(parry_heavy_neutral_lockout, true)
	request_push_apart.emit(parry_heavy_pushback_pixels)

# Checagem de janela efetiva (usa relógio de PARRY_ACTIVE)
func is_within_parry_window(effective_window: float) -> bool:
	return parry_clock <= effective_window
