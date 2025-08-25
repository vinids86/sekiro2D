extends Node
class_name CombatController

signal state_entered(state: int, cfg: AttackConfig)
signal state_exited(state: int, cfg: AttackConfig)

# =========================
# ESTADOS
# =========================
enum State {
	IDLE, STARTUP, HIT, RECOVER, STUN,
	PARRY_STARTUP, PARRY_SUCCESS, PARRY_RECOVER,
	HIT_REACT, PARRIED,
	GUARD_HIT, GUARD_RECOVER,
	COUNTER_STARTUP, COUNTER_HIT, COUNTER_RECOVER,
	GUARD_BROKEN,
	FINISHER_STARTUP, FINISHER_HIT, FINISHER_RECOVER,
	BROKEN_FINISHER_REACT,

	# --- SPECIAL COMBO ---
	COMBO_PARRY,       # (1º) janela de parry do pré-combo
	COMBO_PREP,        # (2º) preparação sem parry window
	COMBO_STARTUP, COMBO_HIT, COMBO_RECOVER,

	# --- DODGE ---
	DODGE_STARTUP, DODGE_ACTIVE, DODGE_RECOVER,
}

const _TIMED_STATES := {
	State.STARTUP: true, State.HIT: true, State.RECOVER: true,
	State.PARRY_STARTUP: true, State.PARRY_SUCCESS: true, State.PARRY_RECOVER: true,
	State.HIT_REACT: true, State.PARRIED: true,
	State.GUARD_HIT: true, State.GUARD_RECOVER: true,
	State.COUNTER_STARTUP: true, State.COUNTER_HIT: true, State.COUNTER_RECOVER: true,
	State.FINISHER_STARTUP: true, State.FINISHER_HIT: true, State.FINISHER_RECOVER: true,
	State.BROKEN_FINISHER_REACT: true,

	# --- SPECIAL COMBO ---
	State.COMBO_PARRY: true,
	State.COMBO_PREP: true,
	State.COMBO_STARTUP: true, State.COMBO_HIT: true, State.COMBO_RECOVER: true,

	# --- DODGE ---
	State.DODGE_STARTUP: true,
	State.DODGE_ACTIVE: true,
	State.DODGE_RECOVER: true,
}

const _REENTER_ON_SAME_STATE := {
	State.HIT_REACT: true,
	State.GUARD_HIT: true,
}

# =========================
# CONFIGS / EXPORTS
# =========================
@export var combo_link_window: float = 12.0 / 12.0
@export var combo_link_damage_mul: float = 1.25

# Pré-combo (config novas)
@export var combo_prep_time: float = 0.20
@export var combo_parry_time: float = 0.70

# Perfil de esquiva (injetado)
var _dodge: DodgeProfile

# =========================
# STATE
# =========================
var _state: int = State.IDLE
var _state_timer: float = 0.0

var _attack_set: AttackSet
var _parry: ParryProfile
var _hitreact: HitReactProfile
var _parried: ParriedProfile
var _guard: GuardProfile

var _combo_index: int = 0
var _current: AttackConfig
var _wants_chain: bool = false

var _state_started_ms: int = 0

var _counter: CounterProfile
var _parry_toggle: bool = true
var _parry_last_ab: int = 0

var _counter_buffered: bool = false

# --- SPECIAL COMBO control ---
var _combo_running: bool = false
var _combo_sequence: Array[AttackConfig] = []

# Perfect Link (bônus runtime)
var _combo_link_pending: bool = false

# Combo-parry: flag de confirmação de parry dentro do COMBO_PARRY
var _combo_parry_confirmed: bool = false

# --- DODGE runtime ---
var _last_dodge_dir: int = 0  # 0 = NEUTRAL, 1 = DOWN (mantemos int simples)

# Callables para custo de esquiva (injetados pelo ImpactDriver)
var _dodge_can_pay: Callable
var _dodge_consume: Callable

# =========================
# INIT
# =========================
func initialize(
		attack_set: AttackSet,
		parry_profile: ParryProfile,
		hit_react_profile: HitReactProfile,
		parried_profile: ParriedProfile,
		guard_profile: GuardProfile,
		counter_profile: CounterProfile,
		dodge_profile: DodgeProfile
	) -> void:
	_attack_set = attack_set
	_parry = parry_profile
	_hitreact = hit_react_profile
	_parried = parried_profile
	_guard = guard_profile
	_counter = counter_profile
	_dodge = dodge_profile

	assert(_attack_set != null, "AttackSet não pode ser nulo")
	assert(_parry != null, "ParryProfile não pode ser nulo")
	assert(_hitreact != null, "HitReactProfile não pode ser nulo")
	assert(_parried != null, "ParriedProfile não pode ser nulo")
	assert(_guard != null)
	assert(_counter != null)
	assert(_counter.counter_a != null)
	assert(_counter.counter_b != null)
	assert(_dodge != null, "DodgeProfile não pode ser nulo")

	_state_started_ms = Time.get_ticks_msec()
	_change_state(State.IDLE, null, 0.0)

# Permite ao ImpactDriver injetar handlers de custo sem acoplamento com Stamina
func bind_dodge_cost_handlers(can_pay: Callable, consume: Callable) -> void:
	_dodge_can_pay = can_pay
	_dodge_consume = consume

# =========================
# INPUTS
# =========================
func on_attack_pressed() -> void:
	# Perfect Link: aceitar input no finzinho do COMBO_STARTUP
	if _state == State.COMBO_STARTUP:
		print("[LINK] press during COMBO_STARTUP | idx=", str(_combo_index),
			" time_left=", str(_state_timer), " window=", str(combo_link_window))
		if _state_timer <= combo_link_window:
			_combo_link_pending = true
			print("[LINK] ARMED at idx=", str(_combo_index))
		else:
			print("[LINK] ignored (outside window)")
		return

	# Bloqueia entrada durante estados que não aceitam novo ataque
	if _state == State.GUARD_HIT or _state == State.GUARD_RECOVER \
	or _state == State.HIT_REACT or _state == State.PARRIED \
	or _state == State.PARRY_STARTUP or _state == State.PARRY_RECOVER \
	or _state == State.GUARD_BROKEN \
	or _state == State.FINISHER_STARTUP or _state == State.FINISHER_HIT or _state == State.FINISHER_RECOVER \
	or _state == State.BROKEN_FINISHER_REACT \
	or _is_combo_state(_state):
		return

	if _state == State.PARRY_SUCCESS:
		_counter_buffered = true
		return

	if _state == State.IDLE:
		_start_attack(0)
	else:
		_wants_chain = true

func can_start_parry() -> bool:
	return (_state == State.IDLE \
		or _state == State.STARTUP \
		or _state == State.PARRY_SUCCESS \
		or _state == State.PARRIED \
		or _state == State.GUARD_RECOVER \
		or _state == State.DODGE_RECOVER) \
		and _state != State.GUARD_BROKEN \
		and _state != State.FINISHER_STARTUP \
		and _state != State.FINISHER_HIT \
		and _state != State.FINISHER_RECOVER \
		and _state != State.BROKEN_FINISHER_REACT

func on_parry_pressed() -> void:
	if _state == State.PARRY_SUCCESS:
		_counter_buffered = false
	if not can_start_parry():
		return
	_change_state(State.PARRY_STARTUP, null, _parry.startup_time)

func enter_parry_success() -> void:
	# Parry tradicional
	if _state == State.PARRY_STARTUP:
		_parry_toggle = not _parry_toggle
		if _parry_toggle:
			_parry_last_ab = 1
		else:
			_parry_last_ab = 0
		_counter_buffered = false
		_change_state(State.PARRY_SUCCESS, null, _parry.success_time)
		return

	# Parry dentro do COMBO_PARRY: não muda de estado, só marca a confirmação
	if _state == State.COMBO_PARRY:
		_combo_parry_confirmed = true
		print("[COMBO] parry confirmado durante COMBO_PARRY")
		return

func is_parry_window() -> bool:
	return _state == State.PARRY_STARTUP or _state == State.COMBO_PARRY

# === ESQUIVA (DODGE) ===
func on_dodge_pressed(dir: int) -> void:
	# Estados que bloqueiam ação
	if _state == State.STUN \
	or _state == State.PARRY_STARTUP \
	or _state == State.PARRY_SUCCESS \
	or _state == State.PARRY_RECOVER \
	or _state == State.GUARD_BROKEN \
	or _state == State.COMBO_PARRY \
	or _state == State.COMBO_PREP \
	or _state == State.DODGE_STARTUP \
	or _state == State.DODGE_ACTIVE \
	or _state == State.COMBO_STARTUP \
	or _state == State.COMBO_HIT:
		return

	# Por agora, aceitamos apenas DOWN (0 = NEUTRAL, 1 = DOWN)
	if dir == 0:
		return

	# Validação obrigatória via callables injetados
	assert(_dodge_can_pay.is_valid(), "Dodge can_pay handler não vinculado")
	assert(_dodge_consume.is_valid(), "Dodge consume handler não vinculado")

	var cost: float = _dodge.stamina_cost
	var can_pay: bool = bool(_dodge_can_pay.call(cost))
	if not can_pay:
		return

	_dodge_consume.call(cost)

	_last_dodge_dir = dir
	_change_state(State.DODGE_STARTUP, null, maxf(_dodge.startup, 0.0))

# Heavy via config recebido do Player/Enemy (não no Controller)
func try_attack_heavy(cfg: AttackConfig) -> void:
	# Gate: estados que não aceitam novo ataque
	if _state == State.GUARD_HIT or _state == State.GUARD_RECOVER \
	or _state == State.HIT_REACT or _state == State.PARRIED \
	or _state == State.PARRY_STARTUP or _state == State.PARRY_RECOVER \
	or _state == State.GUARD_BROKEN \
	or _state == State.FINISHER_STARTUP or _state == State.FINISHER_HIT or _state == State.FINISHER_RECOVER \
	or _state == State.BROKEN_FINISHER_REACT \
	or _is_combo_state(_state):
		return

	assert(cfg != null, "try_attack_heavy: cfg nulo")

	# Garantir que qualquer estado/flag de combo ofensivo não vaze
	_cancel_combo_offense()
	_wants_chain = false

	_current = cfg
	_change_state(State.STARTUP, _current, maxf(_current.startup, 0.0))

# =========================
# REAÇÕES / ENTRADAS
# =========================
func enter_parried() -> void:
	# Hyper-armor apenas em combo protegido OU startup de heavy
	if _has_combo_hyper_armor(_state) or _is_heavy_startup_armored():
		return
	_wants_chain = false
	_change_state(State.PARRIED, _current, _parried.stagger_time)

func enter_hit_react() -> void:
	# Hyper-armor apenas em combo protegido OU startup de heavy
	if _has_combo_hyper_armor(_state) or _is_heavy_startup_armored():
		return
	_wants_chain = false
	_change_state(State.HIT_REACT, null, _hitreact.react_time)

func enter_guard_hit() -> void:
	# Hyper-armor apenas em combo protegido OU startup de heavy
	if _has_combo_hyper_armor(_state) or _is_heavy_startup_armored():
		return
	_wants_chain = false
	_change_state(State.GUARD_HIT, null, _guard.guard_hit_time)

func enter_stun() -> void:
	_wants_chain = false
	_current = null
	_change_state(State.STUN, null, 0.0)

func is_stunned() -> bool:
	return _state == State.STUN

# ---------- SPECIAL COMBO ----------
func start_special_combo(sequence: Array[AttackConfig]) -> void:
	if _state != State.IDLE or _state == State.PARRIED:
		return
	assert(sequence != null and sequence.size() > 0, "start_special_combo: sequence vazia")

	_combo_sequence = sequence.duplicate()
	_combo_running = true
	_combo_index = 0
	_wants_chain = false
	_combo_link_pending = false
	_combo_parry_confirmed = false

	_current = _combo_sequence[_combo_index]
	_change_state(State.COMBO_STARTUP, _current, maxf(_current.startup, 0.0))

func start_combo_with_parry_prep(sequence: Array[AttackConfig]) -> void:
	if not can_start_parry():
		return
	assert(sequence != null and sequence.size() > 0, "start_combo_with_parry_prep: sequence vazia")

	_combo_sequence = sequence.duplicate()
	_combo_running = true
	_combo_index = 0
	_wants_chain = false
	_combo_link_pending = false
	_combo_parry_confirmed = false

	_current = null  # PREP/PARRY não usam AttackConfig
	_change_state(State.COMBO_PARRY, _current, maxf(combo_parry_time, 0.0))

# =========================
# LOOP
# =========================
func update(delta: float) -> void:
	var remaining: float = delta

	while remaining > 0.0:
		if not _is_timed(_state):
			return

		if remaining < _state_timer:
			_state_timer -= remaining
			return

		remaining -= _state_timer
		_state_timer = 0.0
		_on_state_timeout()

		if not _is_timed(_state) or _state_timer <= 0.0:
			return

func _cancel_combo_offense() -> void:
	_combo_running = false
	_combo_sequence = []
	_combo_index = 0
	_combo_link_pending = false
	_combo_parry_confirmed = false

func _on_state_timeout() -> void:
	match _state:
		State.STARTUP: _enter_hit()
		State.HIT: _enter_recover()
		State.RECOVER: pass
		State.PARRY_STARTUP: _change_state(State.PARRY_RECOVER, null, _parry.recover_time)
		State.PARRY_SUCCESS:
			if _counter_buffered:
				_counter_buffered = false
				_start_counter()
			else:
				_change_state(State.IDLE, null, 0.0)
		State.PARRY_RECOVER: _change_state(State.IDLE, null, 0.0)
		State.HIT_REACT: _change_state(State.IDLE, null, 0.0)
		State.PARRIED: _change_state(State.IDLE, null, 0.0)
		State.GUARD_HIT: _change_state(State.GUARD_RECOVER, null, _guard.guard_recover_time)
		State.GUARD_RECOVER: _change_state(State.IDLE, null, 0.0)
		State.COUNTER_STARTUP: _change_state(State.COUNTER_HIT, _current, maxf(_current.hit, 0.0))
		State.COUNTER_HIT: _change_state(State.COUNTER_RECOVER, _current, maxf(_current.recovery, 0.0))
		State.COUNTER_RECOVER:
			if _wants_chain:
				_wants_chain = false
				_start_attack(0)
			else:
				_change_state(State.IDLE, null, 0.0)

		# ---- FINISHER do atacante ----
		State.FINISHER_STARTUP:
			_change_state(State.FINISHER_HIT, _current, maxf(_current.hit, 0.0))
		State.FINISHER_HIT:
			_change_state(State.FINISHER_RECOVER, _current, maxf(_current.recovery, 0.0))
		State.FINISHER_RECOVER:
			_change_state(State.IDLE, null, 0.0)

		# ---- Reação do defensor após levar o finisher ----
		State.BROKEN_FINISHER_REACT:
			_change_state(State.IDLE, null, 0.0)

		# ---- SPECIAL COMBO ----
		State.COMBO_PARRY:
			_change_state(State.COMBO_PREP, null, maxf(combo_prep_time, 0.0))
		State.COMBO_PREP:
			assert(_combo_sequence.size() > 0, "COMBO_PREP timeout sem sequence")
			_combo_index = 0
			_current = _combo_sequence[_combo_index]
			_change_state(State.COMBO_STARTUP, _current, maxf(_current.startup, 0.0))
		State.COMBO_STARTUP:
			_enter_combo_hit()
		State.COMBO_HIT:
			_advance_combo_or_recover()
		State.COMBO_RECOVER:
			_end_combo_to_idle()

		# ---- DODGE ----
		State.DODGE_STARTUP:
			_change_state(State.DODGE_ACTIVE, null, maxf(_dodge.active, 0.0))
		State.DODGE_ACTIVE:
			_change_state(State.DODGE_RECOVER, null, maxf(_dodge.recover, 0.0))
		State.DODGE_RECOVER:
			_change_state(State.IDLE, null, 0.0)

		_:
			push_warning("[FSM] Timeout sem handler: %s" % _state_name(_state))

# =========================
# ATAQUE
# =========================
func _start_attack(index: int) -> void:
	var cfg: AttackConfig = _attack_set.get_attack(index)
	assert(cfg != null, "AttackConfig inválido no índice: %d" % index)
	_combo_index = index
	_current = cfg
	_change_state(State.STARTUP, _current, maxf(cfg.startup, 0.0))

func _enter_hit() -> void:
	assert(_current != null, "_enter_hit sem AttackConfig")
	_change_state(State.HIT, _current, maxf(_current.hit, 0.0))

func _enter_recover() -> void:
	assert(_current != null, "_enter_recover sem AttackConfig")
	_change_state(State.RECOVER, _current, maxf(_current.recovery, 0.0))

# =========================
# SPECIAL COMBO internals
# =========================
func _enter_combo_hit() -> void:
	assert(_current != null, "_enter_combo_hit sem AttackConfig")
	_change_state(State.COMBO_HIT, _current, maxf(_current.hit, 0.0))

func _advance_combo_or_recover() -> void:
	var last_cfg: AttackConfig = _current
	_combo_index += 1
	if _combo_index < _combo_sequence.size():
		_current = _combo_sequence[_combo_index]
		_change_state(State.COMBO_STARTUP, _current, maxf(_current.startup, 0.0))
	else:
		_current = last_cfg
		_change_state(State.COMBO_RECOVER, _current, maxf(_current.recovery, 0.0))

func _end_combo_to_idle() -> void:
	_combo_running = false
	_combo_sequence = []
	_wants_chain = false

	var last: AttackConfig = _current
	_current = null
	_change_state(State.IDLE, last, 0.0)

# =========================
# Callbacks do AnimationDriver
# =========================
func on_body_end(_clip: StringName) -> void:
	if _state != State.RECOVER:
		return
	var next_index: int = -1
	if _wants_chain:
		next_index = _attack_set.next_index(_combo_index)
	_wants_chain = false
	if next_index >= 0:
		_start_attack(next_index)
	else:
		var last: AttackConfig = _current
		_current = null
		_change_state(State.IDLE, last, 0.0)

func on_to_idle_end(_clip: StringName) -> void:
	pass

func _start_counter() -> void:
	var cfg: AttackConfig = null
	if _parry_last_ab == 0:
		cfg = _counter.counter_a
	else:
		cfg = _counter.counter_b

	assert(cfg != null, "Counter AttackConfig inválido")
	_current = cfg
	_change_state(State.COUNTER_STARTUP, _current, maxf(_current.startup, 0.0))

func enter_guard_broken() -> void:
	_wants_chain = false
	_current = null
	_change_state(State.GUARD_BROKEN, null, 0.0)

func start_finisher() -> void:
	if _guard == null or _guard.finisher == null:
		push_warning("[FSM] start_finisher chamado sem GuardProfile/finisher.")
		return
	if _state == State.FINISHER_STARTUP or _state == State.FINISHER_HIT or _state == State.FINISHER_RECOVER:
		return

	_current = _guard.finisher
	_wants_chain = false
	_change_state(State.FINISHER_STARTUP, _current, maxf(_current.startup, 0.0))

func enter_broken_after_finisher() -> void:
	var t: float = 0.5
	if _guard != null and _guard.post_finisher_react_time > 0.0:
		t = _guard.post_finisher_react_time
	_change_state(State.BROKEN_FINISHER_REACT, null, t)

# =========================
# Núcleo de transição + debug
# =========================
func _change_state(new_state: int, cfg: AttackConfig, timer: float) -> void:
	var same: bool = (new_state == _state)
	var re: String = ""
	if same:
		re = " (reenter)"
	print("[FSM] ", _actor_label(), " | ", _state_name(_state), " -> ", _state_name(new_state), re)
	if same and not _allows_reenter(new_state):
		_state_timer = timer
		return

	var old_state: int = _state
	var old_cfg: AttackConfig = _current
	emit_signal("state_exited", old_state, old_cfg)

	_state = new_state
	_state_timer = timer
	emit_signal("state_entered", _state, cfg)

# =========================
# Consultas p/ ImpactDriver e helpers
# =========================
func is_autoblock_enabled_now() -> bool:
	# ON em estados defensivos/ neutros
	if _state == State.IDLE:
		return true
	if _state == State.RECOVER:
		return true
	if _state == State.GUARD_HIT:
		return true
	if _state == State.GUARD_RECOVER:
		return true
	if _state == State.HIT_REACT:
		return true
	if _state == State.PARRY_RECOVER:
		return true
	if _state == State.PARRY_SUCCESS:
		return true
	if _state == State.COUNTER_RECOVER:
		return true
	if _state == State.FINISHER_RECOVER:
		return true
	if _state == State.COMBO_RECOVER:
		return true

	# STARTUP de ataque leve (cancela o ataque ao ser atingido)
	if _state == State.STARTUP and _current != null and not _current.heavy:
		return true

	# OFF em janelas específicas ou fases ofensivas/incapacitantes
	if _state == State.PARRY_STARTUP:
		return false
	if _state == State.STARTUP and _current != null and _current.heavy:
		return false
	if _state == State.HIT:
		return false
	if _state == State.COMBO_STARTUP or _state == State.COMBO_HIT:
		return false
	if _state == State.COUNTER_STARTUP or _state == State.COUNTER_HIT:
		return false
	if _state == State.FINISHER_STARTUP or _state == State.FINISHER_HIT:
		return false
	if _state == State.STUN or _state == State.GUARD_BROKEN or _state == State.BROKEN_FINISHER_REACT:
		return false

	# Demais estados: por segurança, considerar OFF
	return true

func is_dodge_active() -> bool:
	return _state == State.DODGE_ACTIVE

func get_last_dodge_dir() -> int:
	return _last_dodge_dir

func _is_heavy_startup_armored() -> bool:
	if _state != State.STARTUP:
		return false
	if _current == null:
		return false
	if not _current.heavy:
		return false
	return true

func get_state() -> int:
	return _state

func get_current_attack() -> AttackConfig:
	return _current

func consume_combo_link_multiplier() -> float:
	if _combo_link_pending:
		_combo_link_pending = false
		var v: float = maxf(combo_link_damage_mul, 1.0)
		print("[LINK] CONSUME mul=", str(v))
		return v
	print("[LINK] CONSUME mul=1.0 (no bonus)")
	return 1.0

func consume_combo_parry_confirmed() -> bool:
	if _combo_parry_confirmed:
		_combo_parry_confirmed = false
		return true
	return false

func is_combo_prep_active() -> bool:
	return _state == State.COMBO_PARRY or _state == State.COMBO_PREP

func _allows_reenter(s: int) -> bool:
	return _REENTER_ON_SAME_STATE.has(s)

func _is_timed(s: int) -> bool:
	return _TIMED_STATES.has(s)

func _is_combo_state(s: int) -> bool:
	return s == State.COMBO_PARRY or s == State.COMBO_PREP \
		or s == State.COMBO_STARTUP or s == State.COMBO_HIT or s == State.COMBO_RECOVER

func is_combo_offense_active() -> bool:
	var s: int = _state
	return s == State.COMBO_PARRY \
		or s == State.COMBO_PREP \
		or s == State.COMBO_STARTUP \
		or s == State.COMBO_HIT

func is_combo_last_attack() -> bool:
	if _state != State.COMBO_STARTUP and _state != State.COMBO_HIT:
		return false
	var sz: int = _combo_sequence.size()
	if sz <= 0:
		return false
	var last_index: int = sz - 1
	return _combo_index == last_index

func _has_combo_hyper_armor(s: int) -> bool:
	return s == State.COMBO_PARRY \
		or s == State.COMBO_PREP \
		or s == State.COMBO_STARTUP \
		or s == State.COMBO_HIT

func _state_name(s: int) -> String:
	match s:
		State.IDLE: return "IDLE"
		State.STARTUP: return "STARTUP"
		State.HIT: return "HIT"
		State.RECOVER: return "RECOVER"
		State.STUN: return "STUN"
		State.PARRY_STARTUP: return "PARRY_STARTUP"
		State.PARRY_SUCCESS: return "PARRY_SUCCESS"
		State.PARRY_RECOVER: return "PARRY_RECOVER"
		State.HIT_REACT: return "HIT_REACT"
		State.PARRIED: return "PARRIED"
		State.GUARD_HIT: return "GUARD_HIT"
		State.GUARD_RECOVER: return "GUARD_RECOVER"
		State.COUNTER_STARTUP: return "COUNTER_STARTUP"
		State.COUNTER_HIT: return "COUNTER_HIT"
		State.COUNTER_RECOVER: return "COUNTER_RECOVER"
		State.FINISHER_STARTUP: return "FINISHER_STARTUP"
		State.FINISHER_HIT: return "FINISHER_HIT"
		State.FINISHER_RECOVER: return "FINISHER_RECOVER"
		State.GUARD_BROKEN: return "GUARD_BROKEN"
		State.BROKEN_FINISHER_REACT: return "BROKEN_FINISHER_REACT"
		State.COMBO_PARRY: return "COMBO_PARRY"
		State.COMBO_PREP: return "COMBO_PREP"
		State.COMBO_STARTUP: return "COMBO_STARTUP"
		State.COMBO_HIT: return "COMBO_HIT"
		State.COMBO_RECOVER: return "COMBO_RECOVER"
		State.DODGE_STARTUP: return "DODGE_STARTUP"
		State.DODGE_ACTIVE: return "DODGE_ACTIVE"
		State.DODGE_RECOVER: return "DODGE_RECOVER"
		_: return "UNKNOWN"

func _actor_label() -> String:
	var p: Node = get_parent()
	if p is Player:
		return "Player"
	if p is Enemy:
		return "Enemy"
	return p.name
