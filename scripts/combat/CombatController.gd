extends Node
class_name CombatController

signal state_entered(state: int, cfg: AttackConfig)
signal state_exited(state: int, cfg: AttackConfig)

enum State {
	IDLE, STARTUP, HIT, RECOVER, STUN,
	PARRY_STARTUP, PARRY_SUCCESS, PARRY_RECOVER,
	HIT_REACT, PARRIED,
	GUARD_HIT, GUARD_RECOVER,
	COUNTER_STARTUP, COUNTER_HIT, COUNTER_RECOVER,
	GUARD_BROKEN,
	FINISHER_STARTUP, FINISHER_HIT, FINISHER_RECOVER,
	BROKEN_FINISHER_REACT,
}

const _TIMED_STATES := {
	State.STARTUP: true, State.HIT: true, State.RECOVER: true,
	State.PARRY_STARTUP: true, State.PARRY_SUCCESS: true, State.PARRY_RECOVER: true,
	State.HIT_REACT: true, State.PARRIED: true,
	State.GUARD_HIT: true, State.GUARD_RECOVER: true,
	State.COUNTER_STARTUP: true, State.COUNTER_HIT: true, State.COUNTER_RECOVER: true,
	State.FINISHER_STARTUP: true, State.FINISHER_HIT: true, State.FINISHER_RECOVER: true,
	State.BROKEN_FINISHER_REACT: true,
}

const _REENTER_ON_SAME_STATE := {
	State.HIT_REACT: true,
	State.GUARD_HIT: true,
}

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

func initialize(
		attack_set: AttackSet,
		parry_profile: ParryProfile,
		hit_react_profile: HitReactProfile,
		parried_profile: ParriedProfile,
		guard_profile: GuardProfile,
		counter_profile: CounterProfile,
	) -> void:
	_attack_set = attack_set
	_parry = parry_profile
	_hitreact = hit_react_profile
	_parried = parried_profile
	_guard = guard_profile
	_counter = counter_profile
	
	assert(_attack_set != null, "AttackSet não pode ser nulo")
	assert(_parry != null, "ParryProfile não pode ser nulo")
	assert(_hitreact != null, "HitReactProfile não pode ser nulo")
	assert(_parried != null, "ParriedProfile não pode ser nulo")
	assert(_guard != null)
	assert(_counter != null)
	assert(_counter.counter_a != null)
	assert(_counter.counter_b != null)

	_state_started_ms = Time.get_ticks_msec()
	_change_state(State.IDLE, null, 0.0)

# ---------- Inputs ----------
func on_attack_pressed() -> void:
	if _state == State.GUARD_HIT or _state == State.GUARD_RECOVER \
	or _state == State.HIT_REACT or _state == State.PARRIED \
	or _state == State.PARRY_STARTUP or _state == State.PARRY_RECOVER \
	or _state == State.GUARD_BROKEN \
	or _state == State.FINISHER_STARTUP or _state == State.FINISHER_HIT or _state == State.FINISHER_RECOVER \
	or _state == State.BROKEN_FINISHER_REACT:
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
		or _state == State.RECOVER \
		or _state == State.PARRY_SUCCESS \
		or _state == State.PARRIED \
		or _state == State.GUARD_RECOVER) \
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
	if _state != State.PARRY_STARTUP:
		return

	_parry_toggle = not _parry_toggle
	if _parry_toggle:
		_parry_last_ab = 1
	else:
		_parry_last_ab = 0

	_counter_buffered = false
	_change_state(State.PARRY_SUCCESS, null, _parry.success_time)

func is_parry_window() -> bool:
	return _state == State.PARRY_STARTUP
	
func enter_parried() -> void:
	_wants_chain = false
	_change_state(State.PARRIED, _current, _parried.stagger_time)

func enter_hit_react() -> void:
	_wants_chain = false
	_change_state(State.HIT_REACT, null, _hitreact.react_time)

func enter_guard_hit() -> void:
	_wants_chain = false
	_change_state(State.GUARD_HIT, null, _guard.guard_hit_time)

func enter_stun() -> void:
	_wants_chain = false
	_current = null
	_change_state(State.STUN, null, 0.0)

func is_stunned() -> bool:
	return _state == State.STUN

# ---------- Loop ----------
func update(delta: float) -> void:
	if not _is_timed(_state):
		return
	_state_timer -= delta
	if _state_timer > 0.0:
		return
	_on_state_timeout()

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

		_:
			push_warning("[FSM] Timeout sem handler: %s" % _state_name(_state))

# ---------- Ataque ----------
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

# ---------- Callbacks do AnimationDriver ----------
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
	# nada por enquanto (STUN sem automação visual/sonora)
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
	# Sem ações, travado até o finisher resolver
	_wants_chain = false
	_current = null
	_change_state(State.GUARD_BROKEN, null, 0.0)

func start_finisher() -> void:
	# Evita chamadas inválidas
	if _guard == null or _guard.finisher == null:
		push_warning("[FSM] start_finisher chamado sem GuardProfile/finisher.")
		return
	# Se já estiver em finisher, ignore
	if _state == State.FINISHER_STARTUP or _state == State.FINISHER_HIT or _state == State.FINISHER_RECOVER:
		return

	_current = _guard.finisher
	_wants_chain = false
	_change_state(State.FINISHER_STARTUP, _current, maxf(_current.startup, 0.0))

func enter_broken_after_finisher() -> void:
	# Estado do defensor após levar o hit do finisher
	var t: float = 0.5
	if _guard != null and _guard.post_finisher_react_time > 0.0:
		t = _guard.post_finisher_react_time
	_change_state(State.BROKEN_FINISHER_REACT, null, t)

# ---------- Núcleo de transição + debug ----------
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

# ---------- Helpers ----------
func get_state() -> int:
	return _state

func get_current_attack() -> AttackConfig:
	return _current

func _allows_reenter(s: int) -> bool:
	return _REENTER_ON_SAME_STATE.has(s)

func _is_timed(s: int) -> bool:
	return _TIMED_STATES.has(s)
	
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
		State.FINISHER_STARTUP: return "FINISHER_STARUPT"
		State.FINISHER_HIT: return "FINISHER_HIT"
		State.FINISHER_RECOVER: return "FINISHER_RECOVER"
		State.GUARD_BROKEN: return "GUARD_BROKEN"
		State.BROKEN_FINISHER_REACT: return "BROKEN_FINISHER_REACT"
		_: return "UNKNOWN"

func _actor_label() -> String:
	var p: Node = get_parent()
	if p is Player:
		return "Player"
	if p is Enemy:
		return "Enemy"
	return p.name
