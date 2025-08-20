extends Node
class_name CombatController

signal state_entered(state: int, cfg: AttackConfig)
signal state_exited(state: int, cfg: AttackConfig)

enum State { IDLE, STARTUP, HIT, RECOVER, STUN, PARRY_STARTUP, PARRY_SUCCESS, PARRY_RECOVER }

var _state: int = State.IDLE
var _state_timer: float = 0.0

var _attack_set: AttackSet
var _driver: AnimationDriver     # mantido apenas para wiring de callbacks via listener
var _parry: ParryProfile

var _combo_index: int = 0
var _current: AttackConfig
var _wants_chain: bool = false

var _state_started_ms: int = 0

# ---------- Inicialização ----------
func initialize(driver: AnimationDriver, attack_set: AttackSet, parry_profile: ParryProfile) -> void:
	_driver = driver
	_attack_set = attack_set
	_parry = parry_profile

	assert(_driver != null, "AnimationDriver não pode ser nulo")
	assert(_attack_set != null, "AttackSet não pode ser nulo")
	assert(_parry != null, "ParryProfile não pode ser nulo")

	_state_started_ms = Time.get_ticks_msec()
	_change_state(State.IDLE, null, 0.0)

# ---------- API de input ----------
func on_attack_pressed() -> void:
	if _state == State.IDLE:
		_start_attack(0)
	else:
		_wants_chain = true

func can_start_parry() -> bool:
	return _state == State.IDLE or _state == State.STARTUP

func on_parry_pressed() -> void:
	if not can_start_parry():
		print("[FSM] parry ignorado em ", _state_name(_state), " | rem=",
				str(snappedf(_state_timer, 0.001)), "s")
		return
	_change_state(State.PARRY_STARTUP, null, _parry.startup_time)

# Chamado pelo defensor (ImpactDriver) ao detectar hit dentro da janela
func enter_parry_success() -> void:
	if _state != State.PARRY_STARTUP:
		return
	_change_state(State.PARRY_SUCCESS, null, _parry.success_time)

func is_parry_window() -> bool:
	return _state == State.PARRY_STARTUP

# Reação a dano “stun” comum (mantido para fluxo normal)
func enter_stun() -> void:
	_wants_chain = false
	_current = null
	_change_state(State.STUN, null, 0.0)

func is_stunned() -> bool:
	return _state == State.STUN

# ---------- Loop ----------
func update(delta: float) -> void:
	# timers dirigem transições “temporizadas”
	if _state == State.STARTUP or _state == State.HIT or _state == State.RECOVER \
	or _state == State.PARRY_STARTUP or _state == State.PARRY_SUCCESS or _state == State.PARRY_RECOVER:
		_state_timer -= delta
		if _state_timer <= 0.0:
			if _state == State.STARTUP:
				_enter_hit()
			elif _state == State.HIT:
				_enter_recover()
			elif _state == State.RECOVER:
				# aguarda body_end para finalizar (ver on_body_end)
				pass
			elif _state == State.PARRY_STARTUP:
				_change_state(State.PARRY_RECOVER, null, _parry.recover_time)
			elif _state == State.PARRY_SUCCESS:
				_change_state(State.IDLE, null, 0.0)
			elif _state == State.PARRY_RECOVER:
				_change_state(State.IDLE, null, 0.0)

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

# ---------- Callbacks de animação (wire pelo CombatAnimListener) ----------
func on_body_end(_clip: StringName) -> void:
	# Chamado ao fim do body (startup+hit+recovery). Finaliza/encadeia combo.
	if _state != State.RECOVER:
		return

	var next_index: int = -1
	if _wants_chain:
		next_index = _attack_set.next_index(_combo_index)

	_wants_chain = false

	if next_index >= 0:
		_start_attack(next_index)
	else:
		# volta para IDLE
		var last: AttackConfig = _current
		_current = null
		_change_state(State.IDLE, last, 0.0)

func on_to_idle_end(_clip: StringName) -> void:
	# Segurança para encerrar transições animadas
	if _state == State.STUN:
		_change_state(State.IDLE, null, 0.0)

# ---------- Núcleo de transição ----------
func _change_state(new_state: int, cfg: AttackConfig, timer: float) -> void:
	var now_ms: int = Time.get_ticks_msec()

	var elapsed_s: float = float(now_ms - _state_started_ms) / 1000.0
	print("[FSM] ", get_parent().name, " ",
		_state_name(_state), " -> ", _state_name(new_state),
		" | prev=", str(snappedf(elapsed_s, 0.001)), "s",
		" | next_timer=", str(snappedf(timer, 0.001)), "s")
	_state_started_ms = now_ms
	
	if _state == new_state:
		_state_timer = timer
		return

	var old_state: int = _state
	var old_cfg: AttackConfig = _current

	emit_signal("state_exited", old_state, old_cfg)

	_state = new_state
	_state_timer = timer
	emit_signal("state_entered", _state, cfg)

# ---------- Getters auxiliares ----------
func get_state() -> int:
	return _state

func get_current_attack() -> AttackConfig:
	return _current

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
		_: return "UNKNOWN"
