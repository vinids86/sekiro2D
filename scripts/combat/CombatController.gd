extends Node
class_name CombatController

signal state_entered(state: int, cfg: AttackConfig)
signal state_exited(state: int, cfg: AttackConfig)

enum State {
	IDLE, STARTUP, HIT, RECOVER, STUN,
	PARRY_STARTUP, PARRY_SUCCESS, PARRY_RECOVER,
	HIT_REACT, PARRIED,
	GUARD_HIT, GUARD_RECOVER
}

const _REENTER_ON_SAME_STATE := {
	State.HIT_REACT: true,
	State.GUARD_HIT: true,
}

var _state: int = State.IDLE
var _state_timer: float = 0.0

var _attack_set: AttackSet
var _driver: AnimationDriver
var _parry: ParryProfile
var _hitreact: HitReactProfile
var _parried: ParriedProfile
var _guard: GuardProfile

var _combo_index: int = 0
var _current: AttackConfig
var _wants_chain: bool = false

var _state_started_ms: int = 0

func initialize(
		driver: AnimationDriver,
		attack_set: AttackSet,
		parry_profile: ParryProfile,
		hit_react_profile: HitReactProfile,
		parried_profile: ParriedProfile,
		guard_profile: GuardProfile
	) -> void:
	_driver = driver
	_attack_set = attack_set
	_parry = parry_profile
	_hitreact = hit_react_profile
	_parried = parried_profile
	_guard = guard_profile
	
	assert(_driver != null, "AnimationDriver não pode ser nulo")
	assert(_attack_set != null, "AttackSet não pode ser nulo")
	assert(_parry != null, "ParryProfile não pode ser nulo")
	assert(_hitreact != null, "HitReactProfile não pode ser nulo")
	assert(_parried != null, "ParriedProfile não pode ser nulo")
	assert(_guard != null)

	_state_started_ms = Time.get_ticks_msec()
	_change_state(State.IDLE, null, 0.0)

# ---------- Inputs ----------
func on_attack_pressed() -> void:
	if _state == State.GUARD_HIT or _state == State.GUARD_RECOVER \
	or _state == State.HIT_REACT or _state == State.PARRIED \
	or _state == State.PARRY_STARTUP or _state == State.PARRY_SUCCESS or _state == State.PARRY_RECOVER:
		return

	if _state == State.IDLE:
		_start_attack(0)
	else:
		_wants_chain = true

func can_start_parry() -> bool:
	return _state == State.IDLE \
		or _state == State.STARTUP \
		or _state == State.RECOVER \
		or _state == State.PARRY_SUCCESS \
		or _state == State.GUARD_RECOVER


func on_parry_pressed() -> void:
	if not can_start_parry():
		return
	_change_state(State.PARRY_STARTUP, null, _parry.startup_time)

func enter_parry_success() -> void:
	if _state != State.PARRY_STARTUP:
		return
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
	if _state == State.STARTUP or _state == State.HIT or _state == State.RECOVER \
	or _state == State.PARRY_STARTUP or _state == State.PARRY_SUCCESS or _state == State.PARRY_RECOVER \
	or _state == State.HIT_REACT or _state == State.PARRIED or _state == State.GUARD_HIT or _state == State.GUARD_RECOVER:
		_state_timer -= delta
		if _state_timer <= 0.0:
			match _state:
				State.STARTUP: _enter_hit()
				State.HIT: _enter_recover()
				State.RECOVER: pass
				State.PARRY_STARTUP: _change_state(State.PARRY_RECOVER, null, _parry.recover_time)
				State.PARRY_SUCCESS: _change_state(State.IDLE, null, 0.0)
				State.PARRY_RECOVER: _change_state(State.IDLE, null, 0.0)
				State.HIT_REACT: _change_state(State.IDLE, null, 0.0)
				State.PARRIED: _change_state(State.IDLE, null, 0.0)
				State.GUARD_HIT: _change_state(State.GUARD_RECOVER, null, _guard.guard_recover_time)
				State.GUARD_RECOVER: _change_state(State.IDLE, null, 0.0)
	
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
		_: return "UNKNOWN"

func _actor_label() -> String:
	var p: Node = get_parent()
	if p is Player:
		return "Player"
	if p is Enemy:
		return "Enemy"
	return p.name
