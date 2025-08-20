extends Node
class_name CombatController

enum State { IDLE, STARTUP, HIT, RECOVER, STUN }

signal state_entered(state: int, cfg: AttackConfig) 
signal state_exited(state: int, cfg: AttackConfig)

var _state: int = State.IDLE
var _state_timer: float = 0.0

var _attack_set: AttackSet
var _driver: AnimationDriver
var _idle_clip: StringName = &"idle"
var _hit_clip: StringName = StringName()

var _combo_index: int = 0
var _current: AttackConfig
var _wants_chain: bool = false

# ---------- Getters p/ drivers (evita acessar "_" direto) ----------
func get_idle_clip() -> StringName: return _idle_clip
func get_hit_clip() -> StringName: return _hit_clip

# ---------- API pública ----------
func initialize(
		driver: AnimationDriver,
		attack_set: AttackSet,
		idle_clip: StringName,
		hit_clip: StringName,
	) -> void:
	_driver = driver
	_attack_set = attack_set
	_idle_clip = idle_clip
	_hit_clip = hit_clip
	assert(_driver != null, "AnimationDriver não pode ser nulo")
	assert(_attack_set != null, "AttackSet não pode ser nulo")
	assert(_hit_clip != StringName(), "Hit clip não pode ser vazio")

	_driver.connect_body_end(self, &"_on_body_end")
	_driver.connect_to_idle_end(self, &"_on_to_idle_end")
	# OBS: removido: _hitbox, _attack_sfx, _resolver

func on_attack_pressed() -> void:
	if _state == State.IDLE:
		_start_attack(0)
	else:
		_wants_chain = true

func update(delta: float) -> void:
	if _state == State.STARTUP or _state == State.HIT:
		_state_timer -= delta
		if _state_timer <= 0.0:
			if _state == State.STARTUP:
				_enter_hit()
			elif _state == State.HIT:
				_enter_recover()

# ---------- Estados ----------
func _start_attack(index: int) -> void:
	var cfg: AttackConfig = _attack_set.get_attack(index)
	assert(cfg != null, "AttackConfig inválido no índice: %d" % index)

	# sai do estado anterior
	_emit_exit(_state, _current)

	_combo_index = index
	_current = cfg
	_state = State.STARTUP
	_state_timer = maxf(cfg.startup, 0.0)

	# entra no STARTUP carregando o cfg atual
	_emit_enter(_state, _current)

	# Importante: quem toca animação é um listener que ouviu o ENTER de STARTUP

func _enter_hit() -> void:
	var prev: int = _state
	_state = State.HIT
	_state_timer = maxf(_current.hit, 0.0)

	_emit_exit(prev, _current)
	_emit_enter(_state, _current)

func _enter_recover() -> void:
	var prev: int = _state
	_state = State.RECOVER
	_state_timer = 0.0  # o fim do "body" vem do AnimationDriver (body_end)

	_emit_exit(prev, _current)
	_emit_enter(_state, _current)

func _on_body_end(_clip: StringName) -> void:
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
		var prev: int = _state
		_state = State.IDLE
		_current = null

		# Ao entrar no IDLE, passamos o "last" no cfg para o listener decidir o to_idle
		_emit_exit(prev, last)
		_emit_enter(_state, last)

func _on_to_idle_end(_clip: StringName) -> void:
	# fim da reação de STUN → vai pra IDLE
	if _state == State.STUN:
		var prev: int = _state
		_state = State.IDLE
		_emit_exit(prev, null)
		_emit_enter(_state, null)

func enter_stun() -> void:
	_wants_chain = false
	_current = null

	var prev: int = _state
	_state = State.STUN
	_emit_exit(prev, null)
	_emit_enter(_state, null)

func is_stunned() -> bool:
	return _state == State.STUN

# ---------- Helpers de emissão ----------
func _emit_enter(state: int, cfg: AttackConfig) -> void:
	state_entered.emit(state, cfg)

func _emit_exit(state: int, cfg: AttackConfig) -> void:
	state_exited.emit(state, cfg)

# CombatController.gd (adicione no final)
func get_state() -> int:
	return _state

func get_current_attack() -> AttackConfig:
	return _current

func on_body_end(clip: StringName) -> void:
	_on_body_end(clip)

func on_to_idle_end(clip: StringName) -> void:
	_on_to_idle_end(clip)
