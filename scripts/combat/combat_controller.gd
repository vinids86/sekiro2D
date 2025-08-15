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

# --- Esquiva ---
@export var dodge_startup: float = 0.08
@export var dodge_active_duration: float = 0.16
@export var dodge_recovery: float = 0.22
@export var dodge_stamina_cost: float = 8.0
@export var dodge_cooldown: float = 0.35
@export var dodge_avoid_normal: bool = true
@export var dodge_avoid_heavy: bool = true
@export var dodge_avoid_grab: bool = false
@export var dodge_avoid_special: bool = false

@export var sfx_dodge_startup: AudioStream
@export var sfx_dodge_recover: AudioStream

@onready var _effects: StatusEffects = StatusEffects.new()
@onready var _buffer: InputBuffer = InputBuffer.new()

@onready var timeline: AttackTimeline = AttackTimeline.new()
@onready var parry: ParrySystem = ParrySystem.new()

@onready var lockouts: LockoutManager = LockoutManager.new()

# ---------------- Estado interno ----------------
var owner_node: Node
var current_attack_direction: Vector2 = Vector2.ZERO

enum ActionType { NONE, ATTACK, PARRY, DODGE }

var combo_timeout_timer: float = 0.0
var combo_in_progress: bool = false
var combo_index: int = 0

# Timers/flags auxiliares
var recovering_phase: int = 0

# Próximo ataque a executar (heavy ou override externo)
var _override_attack: AttackConfig = null

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
	timeline.step.connect(func(dist: float) -> void:
		attack_step.emit(dist)
	)
	_effects.expired.connect(_on_effect_expired)

# ======================= LOOP =======================
func _ready() -> void:
	set_process(true)

func _process(delta: float) -> void:
	_buffer.tick(delta)

	if can_act() and _buffer.has_buffer():
		actions.try_execute_buffer()

	fsm.tick(delta)
	_effects.tick(delta)

	if combo_in_progress:
		combo_timeout_timer -= delta
		if combo_timeout_timer <= 0.0:
			combo_index = 0
			combo_in_progress = false

	if combat_state == CombatTypes.CombatState.ATTACKING:
		timeline.tick(delta, get_current_attack())

	if combat_state == CombatTypes.CombatState.PARRY_ACTIVE:
		parry.tick(delta)

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
			# se era lockout forçado, ao fim do timer sai direto
			if lockouts.is_forced_active():
				lockouts.finish_force_recover()
				change_state(CombatTypes.CombatState.IDLE)
				return

			var attack: AttackConfig = get_current_attack()
			if recovering_phase == 1:
				recovering_phase = 2
				var soft: float = (attack.recovery_soft if attack != null else 0.0)
				fsm.state_timer = soft
				if _buffer.buffer_timer > 0.0:
					_buffer.buffer_timer = maxf(_buffer.buffer_timer, chain_grace)

				if has_heavy() and can_chain_next_on_soft(attack):
					actions.on_attack_finished(parry.did_succeed)
					combo_in_progress = true
					combo_timeout_timer = combo_timeout_duration
					current_attack_direction = peek_heavy_dir()
					_start_heavy_from_buffer()
					return
				elif _buffer.queued_action == ActionType.ATTACK and can_chain_next_on_soft(attack):
					actions.on_attack_finished(parry.did_succeed)
					combo_in_progress = true
					combo_timeout_timer = combo_timeout_duration
					current_attack_direction = _buffer.queued_direction
					clear_buffer()
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
			if parry.did_succeed:
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
	if fsm == null:
		return
	if not fsm.can_transition_from(combat_state, new_state):
		return

	var prev: CombatTypes.CombatState = combat_state
	combat_state = new_state

	if debug_logs:
		var owner_name: String = (owner_node.name if owner_node != null else "<?>")
		print("%s mudando estado: %s → %s" % [
			owner_name,
			CombatTypes.CombatState.keys()[prev],
			CombatTypes.CombatState.keys()[new_state]
		])

	fsm.change_state(new_state)

# ======================= FSM: ENTER/EXIT =======================
func _on_enter_state(state: CombatTypes.CombatState) -> void:
	var attack: AttackConfig = get_current_attack()

	match state:
		CombatTypes.CombatState.STARTUP:
			_enter_startup(attack)
		CombatTypes.CombatState.ATTACKING:
			_enter_attacking(attack)
		CombatTypes.CombatState.RECOVERING:
			_enter_recovering(attack)
		CombatTypes.CombatState.PARRY_ACTIVE:
			_enter_parry_active()
		CombatTypes.CombatState.STUNNED:
			_enter_stunned()
		CombatTypes.CombatState.PARRY_SUCCESS:
			_enter_parry_success()
		CombatTypes.CombatState.GUARD_BROKEN:
			_enter_guard_broken()
		CombatTypes.CombatState.DODGE_STARTUP:
			_enter_dodge_startup()
		CombatTypes.CombatState.DODGE_ACTIVE:
			_enter_dodge_active()
		CombatTypes.CombatState.DODGE_RECOVERING:
			_enter_dodge_recovering()
		CombatTypes.CombatState.IDLE:
			_enter_idle()

func _on_exit_state(state: CombatTypes.CombatState) -> void:
	match state:
		CombatTypes.CombatState.ATTACKING:
			_exit_attacking()
		CombatTypes.CombatState.PARRY_ACTIVE:
			_exit_parry_active()
		CombatTypes.CombatState.DODGE_ACTIVE, CombatTypes.CombatState.DODGE_RECOVERING:
			_exit_dodge_chain()
		_:
			pass

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
	lockouts.set_stun_override(maxf(duration, 0.0))
	change_state(CombatTypes.CombatState.STUNNED)

func force_guard_broken(duration: float = -1.0) -> void:
	var dur: float = guard_broken_duration
	if duration >= 0.0:
		dur = duration
	lockouts.set_guard_broken_override(dur)
	clear_all_buffers()
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
	_effects.apply(name, duration)

func has_effect(name: String) -> bool:
	return _effects.has(name)

# ======================= ATAQUE ATUAL / CHAIN =======================
func get_current_attack() -> AttackConfig:
	if _override_attack != null:
		return _override_attack
	var seq: Array = _iface["get_attack_sequence"].call()
	if seq.is_empty():
		return null
	return seq[combo_index] as AttackConfig

func can_chain_next_on_soft(attack: AttackConfig) -> bool:
	return attack != null and attack.can_chain_next_attack_on_soft_recovery

func override_next_attack(cfg: AttackConfig) -> void:
	_override_attack = cfg

func _start_heavy_from_buffer() -> void:
	if not has_heavy():
		return
	_override_attack = peek_heavy_cfg()
	clear_heavy()
	change_state(CombatTypes.CombatState.STARTUP)

func _finish_recover_and_exit() -> void:
	actions.on_attack_finished(parry.did_succeed)

	if has_heavy() and _buffer.buffer_timer > 0.0:
		current_attack_direction = peek_heavy_dir()
		_start_heavy_from_buffer()
	elif _buffer.queued_action == ActionType.ATTACK and _buffer.buffer_timer > 0.0:
		current_attack_direction = _buffer.queued_direction
		clear_buffer()
		change_state(CombatTypes.CombatState.STARTUP)
	else:
		change_state(CombatTypes.CombatState.IDLE)

# ======================= BUFFER: API PÚBLICA =======================
func queue_action(action: int, dir: Vector2, duration: float) -> void:
	_buffer.push_action(action, dir, duration)

func queue_heavy(cfg: AttackConfig, dir: Vector2, duration: float) -> void:
	_buffer.push_heavy(cfg, dir, duration)

func has_buffer() -> bool:
	return _buffer.has_buffer()

func clear_buffer() -> void:
	_buffer.clear_action()

func clear_heavy() -> void:
	_buffer.clear_heavy()

func clear_all_buffers() -> void:
	_buffer.clear_all()

func peek_action() -> int:
	return _buffer.queued_action

func peek_direction() -> Vector2:
	return _buffer.queued_direction

func buffer_time_left() -> float:
	return _buffer.buffer_timer

func has_heavy() -> bool:
	return _buffer.queued_heavy_cfg != null

func peek_heavy_cfg() -> AttackConfig:
	return _buffer.queued_heavy_cfg

func peek_heavy_dir() -> Vector2:
	return _buffer.queued_heavy_dir

# ======================= LOCKOUT HELPER =======================
func force_lockout(duration: float) -> void:
	lockouts.begin_force_recover(maxf(duration, 0.0))
	clear_all_buffers()
	_override_attack = null
	change_state(CombatTypes.CombatState.RECOVERING)

func is_within_parry_window(effective_window: float) -> bool:
	if combat_state != CombatTypes.CombatState.PARRY_ACTIVE:
		return false
	return parry.within(effective_window)

# --- RESOLVERS DE PARRY (exigidos pelo CombatHitResolver) ---
func resolve_parry_light(attacker: CombatController, defender: CombatController) -> void:
	defender.parry.set_success(false)
	defender.lockouts.set_parry_success_override(defender.parry_light_lockout_defender)
	if defender.combat_state == CombatTypes.CombatState.PARRY_ACTIVE:
		defender.change_state(CombatTypes.CombatState.PARRY_SUCCESS)
	attacker.force_stun(parry_light_lockout_attacker, true)

func resolve_parry_heavy_neutral(attacker: CombatController, defender: CombatController) -> void:
	defender.parry.set_success(true)
	defender.lockouts.set_parry_success_override(defender.parry_heavy_neutral_lockout)
	if defender.combat_state == CombatTypes.CombatState.PARRY_ACTIVE:
		defender.change_state(CombatTypes.CombatState.PARRY_SUCCESS)
	attacker.force_stun(parry_heavy_neutral_lockout, true)
	attacker.request_push_apart.emit(parry_heavy_pushback_pixels)
	defender.request_push_apart.emit(parry_heavy_pushback_pixels)

func _on_effect_expired(name: String) -> void:
	if debug_logs:
		print("Effect expired: ", name)

func _enter_startup(attack: AttackConfig) -> void:
	if attack != null:
		fsm.state_timer = attack.startup
		_iface["consume_stamina"].call(attack.stamina_cost)

func _enter_attacking(attack: AttackConfig) -> void:
	if attack != null:
		fsm.state_timer = attack.active_duration
		timeline.start()
		hitbox_active_changed.emit(true)
		if attack.attack_sound != null:
			play_stream.emit(attack.attack_sound)

func _enter_recovering(attack: AttackConfig) -> void:
	var forced: float = lockouts.pop_force_recover()
	if forced >= 0.0:
		recovering_phase = 0
		fsm.state_timer = forced
		_override_attack = null
		return

	recovering_phase = 1
	var hard: float = 0.0
	if attack != null:
		hard = attack.recovery_hard
	fsm.state_timer = hard
	if _buffer.buffer_timer > 0.0:
		_buffer.buffer_timer = maxf(_buffer.buffer_timer, chain_grace)

func _enter_parry_active() -> void:
	fsm.state_timer = parry_window
	parry.begin()
	play_stream.emit(sfx_parry_active)

func _enter_stunned() -> void:
	var dur: float = lockouts.consume_stun_duration(block_stun)
	fsm.state_timer = dur
	clear_all_buffers()
	_override_attack = null

func _enter_parry_success() -> void:
	var dur_ps: float = lockouts.consume_parry_success_duration(parry_success_base_lockout)
	fsm.state_timer = dur_ps
	play_stream.emit(sfx_parry_success)

func _enter_guard_broken() -> void:
	var dur_gb: float = lockouts.consume_guard_broken_duration(guard_broken_duration)
	fsm.state_timer = dur_gb
	clear_all_buffers()
	_override_attack = null

func _enter_dodge_startup() -> void:
	fsm.state_timer = dodge_startup
	_iface["consume_stamina"].call(dodge_stamina_cost)
	play_stream.emit(sfx_dodge_startup)

func _enter_dodge_active() -> void:
	fsm.state_timer = dodge_active_duration

func _enter_dodge_recovering() -> void:
	fsm.state_timer = dodge_recovery
	play_stream.emit(sfx_dodge_recover)

func _enter_idle() -> void:
	recovering_phase = 0
	# dar 1 frame para outros componentes enfileirarem entradas
	await get_tree().process_frame
	actions.try_execute_buffer()

func _exit_attacking() -> void:
	# Desliga hitbox ao sair da fase ativa
	hitbox_active_changed.emit(false)

func _exit_parry_active() -> void:
	# Entra em cooldown de parry ao sair da janela
	apply_effect(EFFECT_PARRY_COOLDOWN, parry_cooldown)

func _exit_dodge_chain() -> void:
	# Qualquer saída de DODGE_* aplica cooldown de dodge
	apply_effect(EFFECT_DODGE_COOLDOWN, dodge_cooldown)
