extends Node
class_name CombatController

var combat_state: CombatTypes.CombatState = CombatTypes.CombatState.IDLE
var stun_kind: CombatTypes.StunKind = CombatTypes.StunKind.NONE

# ---------------- Sinais ----------------
signal state_changed(state: int, attack_direction: Vector2)
signal play_stream(stream: AudioStream)
signal hitbox_active_changed(is_on: bool)
signal attack_step(distance_px: float)
signal request_push_apart(pixels: float)

# ---------------- Constantes de efeitos ----------------
const EFFECT_PARRY_COOLDOWN: String = "parry_cooldown"
const EFFECT_DODGE_COOLDOWN: String = "dodge_cooldown"

# ---------------- Parâmetros ----------------
@export var parry_window: float = 0.4
@export var parry_cooldown: float = 0.2
@export var block_stun: float = 1.0
@export var input_buffer_duration: float = 0.4
@export var block_stamina_cost: float = 10.0
@export var combo_timeout_duration: float = 2.0
@export var chain_grace: float = 0.12
@export var debug_logs: bool = true
@export var sfx_parry_active: AudioStream
@export var sfx_parry_success: AudioStream

# Lockouts de parry
@export var parry_light_lockout_attacker: float = 0.60
@export var parry_light_lockout_defender: float = 0.20
@export var parry_heavy_neutral_lockout: float = 0.45
@export var parry_heavy_pushback_pixels: float = 32.0

# PARRY_SUCCESS (defensor)
@export var parry_success_base_lockout: float = 0.4

# --- Guard Broken & Finisher ---
@export var guard_broken_duration: float = 1.9
@export var finisher_attacker_lockout: float = 0.45
@export var finisher_defender_lockout: float = 0.9
@export var finisher_push_px: float = 64.0

# --- Esquiva (i-frames + animação, sem deslocamento) ---
@export var dodge_startup: float = 0.08
@export var dodge_active_duration: float = 0.16
@export var dodge_recovery: float = 0.22
@export var dodge_stamina_cost: float = 8.0
@export var dodge_cooldown: float = 0.35
# Quais tipos a esquiva evita
@export var dodge_avoid_normal: bool = true
@export var dodge_avoid_heavy: bool = true
@export var dodge_avoid_grab: bool = false
@export var dodge_avoid_special: bool = false

@export var sfx_dodge_startup: AudioStream
@export var sfx_dodge_recover: AudioStream

# ---------------- Estado interno ----------------
var owner_node: Node

var current_attack_direction: Vector2 = Vector2.ZERO

enum ActionType { NONE, ATTACK, PARRY, DODGE }
var queued_action: ActionType = ActionType.NONE
var queued_direction: Vector2 = Vector2.ZERO
var buffer_timer: float = 0.0

var combo_timeout_timer: float = 0.0
var combo_in_progress: bool = false
var combo_index: int = 0

var status_effects: Dictionary = {}
var did_parry_succeed: bool = false
var last_parry_was_heavy: bool = false

# Timers/flags auxiliares
var recovering_phase: int = 0
var _force_recover_timer: float = -1.0
var _forced_lockout_active: bool = false

# Dados do ataque ativo
var step_emitted: bool = false
var active_clock: float = 0.0
var _prev_active_clock: float = 0.0
var parry_clock: float = 0.0

# Overrides/Lockouts
var parry_success_lockout_override: float = -1.0
var stun_lockout_override: float = -1.0
var guard_broken_lockout_override: float = -1.0

# HEAVY override/buffer
var _override_attack: AttackConfig = null
var _queued_heavy_cfg: AttackConfig = null
var _queued_heavy_dir: Vector2 = Vector2.ZERO

# --- Interface injetada (setup) ---
var _iface: Dictionary = {
	"get_attack_sequence": func() -> Array: return owner_node.attack_sequence if owner_node and "attack_sequence" in owner_node else [],
	"has_stamina":        func(cost: float) -> bool: return owner_node.has_stamina(cost) if owner_node and owner_node.has_method("has_stamina") else true,
	"consume_stamina":    func(cost: float) -> void: if owner_node and owner_node.has_method("consume_stamina"): owner_node.consume_stamina(cost),
	"apply_attack_effects": func(_cfg: AttackConfig) -> void: pass,
	"play_block_sfx":       func() -> void: pass
}

# ---------------- Componentes ----------------
var fsm: CombatFSM
var hit: CombatHitResolver
var actions: CombatActions

# ======================= SETUP =======================
func setup(owner: Node, iface: Dictionary = {}) -> void:
	owner_node = owner
	iface.merge(_iface, false)
	_iface = iface

	fsm = CombatFSM.new()
	hit = CombatHitResolver.new()
	actions = CombatActions.new()

	fsm.setup(
		self,
		debug_logs,
		Callable(self, "_on_enter_state"),
		Callable(self, "_on_exit_state"),
		Callable(self, "can_auto_advance"),
		Callable(self, "auto_advance_state")
	)
	fsm.sync_from_controller(combat_state)

	# Sinal do FSM agora é (state: int, dir: Vector2)
	fsm.state_changed.connect(func(s: int, dir: Vector2) -> void:
		state_changed.emit(s, dir)
	)

	hit.setup(
		self,
		_iface["has_stamina"] as Callable,
		_iface["consume_stamina"] as Callable,
		_iface["apply_attack_effects"] as Callable,
		_iface["play_block_sfx"] as Callable
	)

	actions.setup(self)

# ======================= LOOP =======================
func _ready() -> void:
	set_process(true)

func _process(delta: float) -> void:
	# Buffer window
	if buffer_timer > 0.0:
		buffer_timer -= delta
		if buffer_timer <= 0.0:
			_clear_buffer_and_heavy()

	# Executar buffer quando possível
	if can_act():
		if queued_action != ActionType.NONE or _queued_heavy_cfg != null:
			actions.try_execute_buffer()

	# Timers de estado (FSM)
	fsm.tick(delta)

	# Efeitos temporários
	var expired: Array = []
	for k in status_effects.keys():
		status_effects[k] -= delta
		if status_effects[k] <= 0.0:
			expired.append(k)
	for k in expired:
		status_effects.erase(k)

	# Timeout de combo
	if combo_in_progress:
		combo_timeout_timer -= delta
		if combo_timeout_timer <= 0.0:
			combo_index = 0
			combo_in_progress = false

	# Relógio da fase ativa do ataque
	if combat_state == CombatTypes.CombatState.ATTACKING:
		_prev_active_clock = active_clock
		active_clock += delta
		_check_attack_step(active_clock, _prev_active_clock)

	# Relógio do parry window
	if combat_state == CombatTypes.CombatState.PARRY_ACTIVE:
		parry_clock += delta

# ======================= FSM: API =======================
func can_auto_advance() -> bool:
	return [
		CombatTypes.CombatState.STARTUP, CombatTypes.CombatState.ATTACKING, CombatTypes.CombatState.RECOVERING,
		CombatTypes.CombatState.STUNNED, CombatTypes.CombatState.PARRY_ACTIVE, CombatTypes.CombatState.PARRY_SUCCESS, CombatTypes.CombatState.GUARD_BROKEN,
		CombatTypes.CombatState.DODGE_STARTUP, CombatTypes.CombatState.DODGE_ACTIVE, CombatTypes.CombatState.DODGE_RECOVERING
	].has(combat_state)

func auto_advance_state() -> void:
	match combat_state:
		CombatTypes.CombatState.STARTUP:
			change_state(CombatTypes.CombatState.ATTACKING)

		CombatTypes.CombatState.ATTACKING:
			change_state(CombatTypes.CombatState.RECOVERING)

		CombatTypes.CombatState.RECOVERING:
			if _forced_lockout_active:
				_forced_lockout_active = false
			if _force_recover_timer >= 0.0:
				_force_recover_timer = -1.0
				change_state(CombatTypes.CombatState.IDLE)
				return

			var attack: AttackConfig = _current_attack() as AttackConfig
			if recovering_phase == 1:
				recovering_phase = 2
				var soft: float = 0.0
				if attack != null:
					soft = attack.recovery_soft
				fsm.state_timer = soft
				if buffer_timer > 0.0:
					buffer_timer = max(buffer_timer, chain_grace)

				if _queued_heavy_cfg != null and _can_chain_next_on_soft(attack):
					actions.on_attack_finished(did_parry_succeed)
					combo_in_progress = true
					combo_timeout_timer = combo_timeout_duration
					current_attack_direction = _queued_heavy_dir
					_start_heavy_from_buffer()
					return
				elif queued_action == ActionType.ATTACK and _can_chain_next_on_soft(attack):
					actions.on_attack_finished(did_parry_succeed)
					combo_in_progress = true
					combo_timeout_timer = combo_timeout_duration
					current_attack_direction = queued_direction
					_clear_buffer()
					change_state(CombatTypes.CombatState.STARTUP)
					return
				elif fsm.state_timer <= 0.0:
					_finish_recover_and_exit()
			else:
				_finish_recover_and_exit()

		CombatTypes.CombatState.STUNNED:
			change_state(CombatTypes.CombatState.IDLE)

		CombatTypes.CombatState.PARRY_SUCCESS:
			change_state(CombatTypes.CombatState.IDLE)

		CombatTypes.CombatState.PARRY_ACTIVE:
			if did_parry_succeed:
				change_state(CombatTypes.CombatState.PARRY_SUCCESS)
			else:
				change_state(CombatTypes.CombatState.IDLE)

		CombatTypes.CombatState.GUARD_BROKEN:
			change_state(CombatTypes.CombatState.IDLE)

		CombatTypes.CombatState.DODGE_STARTUP:
			change_state(CombatTypes.CombatState.DODGE_ACTIVE)

		CombatTypes.CombatState.DODGE_ACTIVE:
			change_state(CombatTypes.CombatState.DODGE_RECOVERING)

		CombatTypes.CombatState.DODGE_RECOVERING:
			change_state(CombatTypes.CombatState.IDLE)

func change_state(new_state: CombatTypes.CombatState) -> void:
	# FSM é o árbitro das transições
	if fsm == null:
		return
	if not fsm.can_transition_from(combat_state, new_state):
		return

	var prev: CombatTypes.CombatState = combat_state
	combat_state = new_state

	if debug_logs:
		var owner_name: String = "<?>"
		if owner_node != null:
			owner_name = owner_node.name
		print("%s mudando estado: %s → %s" % [
			owner_name,
			CombatTypes.CombatState.keys()[prev],
			CombatTypes.CombatState.keys()[new_state]
		])

	# Delegar a transição ao FSM (ele chama _on_exit/_on_enter e emite state_changed)
	fsm.change_state(new_state)

# ======================= FSM: ENTER/EXIT =======================
func _on_enter_state(state: CombatTypes.CombatState) -> void:
	did_parry_succeed = false
	var attack: AttackConfig = _current_attack()

	match state:
		CombatTypes.CombatState.STARTUP:
			if attack != null:
				fsm.state_timer = attack.startup
				_iface["consume_stamina"].call(attack.stamina_cost)

		CombatTypes.CombatState.ATTACKING:
			if attack != null:
				fsm.state_timer = attack.active_duration
				active_clock = 0.0
				_prev_active_clock = 0.0
				step_emitted = false
				hitbox_active_changed.emit(true)
				if attack.attack_sound != null:
					play_stream.emit(attack.attack_sound)

		CombatTypes.CombatState.RECOVERING:
			var forced: float = _force_recover_timer
			if forced >= 0.0:
				_forced_lockout_active = true
				recovering_phase = 0
				fsm.state_timer = forced
				_override_attack = null
			else:
				recovering_phase = 1
				var hard: float = 0.0
				if attack != null:
					hard = attack.recovery_hard
				fsm.state_timer = hard
				if buffer_timer > 0.0:
					buffer_timer = max(buffer_timer, chain_grace)

		CombatTypes.CombatState.PARRY_ACTIVE:
			fsm.state_timer = parry_window
			parry_clock = 0.0
			play_stream.emit(sfx_parry_active)

		CombatTypes.CombatState.STUNNED:
			var dur: float = block_stun
			if stun_lockout_override >= 0.0:
				dur = stun_lockout_override
				stun_lockout_override = -1.0
			fsm.state_timer = dur
			_clear_buffer_and_heavy()
			_override_attack = null

		CombatTypes.CombatState.PARRY_SUCCESS:
			var dur_ps: float = parry_success_base_lockout
			if parry_success_lockout_override >= 0.0:
				dur_ps = parry_success_lockout_override
				parry_success_lockout_override = -1.0
			fsm.state_timer = dur_ps
			play_stream.emit(sfx_parry_success)

		CombatTypes.CombatState.GUARD_BROKEN:
			var dur_gb: float = guard_broken_duration
			if guard_broken_lockout_override >= 0.0:
				dur_gb = guard_broken_lockout_override
				guard_broken_lockout_override = -1.0
			fsm.state_timer = dur_gb
			_clear_buffer_and_heavy()
			_override_attack = null

		CombatTypes.CombatState.DODGE_STARTUP:
			fsm.state_timer = dodge_startup
			_iface["consume_stamina"].call(dodge_stamina_cost)
			play_stream.emit(sfx_dodge_startup)

		CombatTypes.CombatState.DODGE_ACTIVE:
			fsm.state_timer = dodge_active_duration

		CombatTypes.CombatState.DODGE_RECOVERING:
			fsm.state_timer = dodge_recovery
			play_stream.emit(sfx_dodge_recover)

		CombatTypes.CombatState.IDLE:
			recovering_phase = 0
			await get_tree().process_frame
			actions.try_execute_buffer()

func _on_exit_state(state: CombatTypes.CombatState) -> void:
	match state:
		CombatTypes.CombatState.STARTUP, CombatTypes.CombatState.ATTACKING, CombatTypes.CombatState.PARRY_ACTIVE, CombatTypes.CombatState.DODGE_ACTIVE, CombatTypes.CombatState.DODGE_RECOVERING:
			if state == CombatTypes.CombatState.PARRY_ACTIVE:
				apply_effect(EFFECT_PARRY_COOLDOWN, parry_cooldown)
			if state == CombatTypes.CombatState.ATTACKING:
				hitbox_active_changed.emit(false)
			if state == CombatTypes.CombatState.DODGE_ACTIVE or state == CombatTypes.CombatState.DODGE_RECOVERING:
				apply_effect(EFFECT_DODGE_COOLDOWN, dodge_cooldown)

# ======================= AÇÕES: WRAPPERS =======================
func try_attack(from_buffer: bool = false, dir: Vector2 = Vector2.ZERO) -> bool:
	return actions.try_attack(from_buffer, dir)

func try_attack_heavy(cfg: AttackConfig, dir: Vector2 = Vector2.ZERO, from_buffer: bool = false) -> bool:
	return actions.try_attack_heavy(cfg, dir, from_buffer)

func on_attack_finished(was_parried: bool) -> void:
	actions.on_attack_finished(was_parried)

func try_parry(from_buffer: bool = false, dir: Vector2 = Vector2.ZERO) -> bool:
	return actions.try_parry(from_buffer, dir)

func try_dodge(from_buffer: bool = false, dir: Vector2 = Vector2.ZERO) -> bool:
	return actions.try_dodge(from_buffer, dir)

# ======================= HIT RESOLUTION =======================
func process_incoming_hit(attacker: Node) -> void:
	hit.process_incoming_hit(attacker)

# ======================= UTILIDADES/REGRAS =======================
func is_dodge_iframe_active() -> bool:
	return combat_state == CombatTypes.CombatState.DODGE_ACTIVE

func is_dodge_invulnerable_to(kind: int) -> bool:
	if not is_dodge_iframe_active():
		return false
	match kind:
		AttackConfig.AttackKind.NORMAL:
			return dodge_avoid_normal
		AttackConfig.AttackKind.HEAVY:
			return dodge_avoid_heavy
		AttackConfig.AttackKind.GRAB:
			return dodge_avoid_grab
		AttackConfig.AttackKind.SPECIAL:
			return dodge_avoid_special
		_:
			return true

func force_stun(duration: float, as_parried: bool = true) -> void:
	if as_parried:
		stun_kind = CombatTypes.StunKind.PARRIED
	else:
		stun_kind = CombatTypes.StunKind.BLOCKED
	stun_lockout_override = maxf(duration, 0.0)
	change_state(CombatTypes.CombatState.STUNNED)

func force_guard_broken(duration: float = -1.0) -> void:
	var dur: float = guard_broken_duration
	if duration >= 0.0:
		dur = duration
	guard_broken_lockout_override = dur
	_clear_buffer_and_heavy()
	_override_attack = null
	change_state(CombatTypes.CombatState.GUARD_BROKEN)

func is_guard_broken() -> bool:
	return combat_state == CombatTypes.CombatState.GUARD_BROKEN

func resolve_finisher(attacker: CombatController, defender: CombatController) -> void:
	attacker.force_lockout(finisher_attacker_lockout)
	defender.force_lockout(finisher_defender_lockout)
	attacker.request_push_apart.emit(finisher_push_px)
	defender.request_push_apart.emit(finisher_push_px)

func on_parried() -> void:
	stun_kind = CombatTypes.StunKind.PARRIED
	change_state(CombatTypes.CombatState.STUNNED)

func on_blocked() -> void:
	stun_kind = CombatTypes.StunKind.BLOCKED
	change_state(CombatTypes.CombatState.STUNNED)
	_iface["consume_stamina"].call(block_stamina_cost)

func on_hit() -> void:
	if combat_state == CombatTypes.CombatState.GUARD_BROKEN:
		return
	stun_kind = CombatTypes.StunKind.NONE
	change_state(CombatTypes.CombatState.STUNNED)

func can_act() -> bool:
	return combat_state == CombatTypes.CombatState.IDLE or combat_state == CombatTypes.CombatState.RECOVERING

func apply_effect(name: String, duration: float) -> void:
	status_effects[name] = duration

func has_effect(name: String) -> bool:
	return status_effects.has(name)

func enter_hitstun(duration: float, kind: CombatTypes.StunKind) -> void:
	if combat_state == CombatTypes.CombatState.PARRY_SUCCESS:
		return
	stun_kind = kind
	stun_lockout_override = maxf(duration, 0.0)
	change_state(CombatTypes.CombatState.STUNNED)

# ======================= ATAQUE ATUAL / CHAIN =======================
func get_current_attack():
	return _current_attack()

func _current_attack():
	if _override_attack != null:
		return _override_attack
	var seq: Array = _iface["get_attack_sequence"].call()
	if seq.is_empty():
		return null
	return seq[combo_index]

func _can_chain_next_on_soft(attack) -> bool:
	return attack != null and attack.can_chain_next_attack_on_soft_recovery

func _start_heavy_from_buffer() -> void:
	if _queued_heavy_cfg == null:
		return
	_override_attack = _queued_heavy_cfg
	_queued_heavy_cfg = null
	change_state(CombatTypes.CombatState.STARTUP)

func _finish_recover_and_exit() -> void:
	if _forced_lockout_active or _force_recover_timer >= 0.0:
		_forced_lockout_active = false
		_force_recover_timer = -1.0
		_override_attack = null
		change_state(CombatTypes.CombatState.IDLE)
		return

	actions.on_attack_finished(did_parry_succeed)
	if _queued_heavy_cfg != null and buffer_timer > 0.0:
		current_attack_direction = _queued_heavy_dir
		_start_heavy_from_buffer()
	elif queued_action == ActionType.ATTACK and buffer_timer > 0.0:
		current_attack_direction = queued_direction
		_clear_buffer()
		change_state(CombatTypes.CombatState.STARTUP)
	else:
		change_state(CombatTypes.CombatState.IDLE)

func _check_attack_step(t: float, prev_t: float) -> void:
	var atk = _current_attack()
	if atk == null:
		return
	if step_emitted:
		return
	if atk.step_distance_px == 0.0:
		return
	if not (prev_t < atk.step_time_in_active and t >= atk.step_time_in_active):
		return
	step_emitted = true
	attack_step.emit(atk.step_distance_px)

# ======================= BUFFER HELPERS =======================
func _clear_buffer() -> void:
	queued_action = ActionType.NONE
	queued_direction = Vector2.ZERO
	buffer_timer = 0.0

func _clear_heavy_queue() -> void:
	_queued_heavy_cfg = null
	_queued_heavy_dir = Vector2.ZERO

func _clear_buffer_and_heavy() -> void:
	_clear_buffer()
	_clear_heavy_queue()

# ======================= LOCKOUT HELPER =======================
func force_lockout(duration: float) -> void:
	_force_recover_timer = maxf(duration, 0.0)
	_forced_lockout_active = true
	_clear_buffer_and_heavy()
	_override_attack = null
	change_state(CombatTypes.CombatState.RECOVERING)

func is_within_parry_window(effective_window: float) -> bool:
	if combat_state != CombatTypes.CombatState.PARRY_ACTIVE:
		return false
	return parry_clock <= effective_window

# --- RESOLVERS DE PARRY (exigidos pelo CombatHitResolver) ---
func resolve_parry_light(attacker: CombatController, defender: CombatController) -> void:
	defender.did_parry_succeed = true
	defender.last_parry_was_heavy = false
	defender.parry_success_lockout_override = defender.parry_light_lockout_defender
	if defender.combat_state == CombatTypes.CombatState.PARRY_ACTIVE:
		defender.change_state(CombatTypes.CombatState.PARRY_SUCCESS)
	attacker.force_stun(parry_light_lockout_attacker, true)

func resolve_parry_heavy_neutral(attacker: CombatController, defender: CombatController) -> void:
	defender.did_parry_succeed = true
	defender.last_parry_was_heavy = true
	defender.parry_success_lockout_override = defender.parry_heavy_neutral_lockout
	if defender.combat_state == CombatTypes.CombatState.PARRY_ACTIVE:
		defender.change_state(CombatTypes.CombatState.PARRY_SUCCESS)
	attacker.force_stun(parry_heavy_neutral_lockout, true)
	attacker.request_push_apart.emit(parry_heavy_pushback_pixels)
	defender.request_push_apart.emit(parry_heavy_pushback_pixels)
