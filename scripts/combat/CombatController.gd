extends Node
class_name CombatController

enum State { IDLE, STARTUP, HIT, RECOVER, STUN }

var _state: int = State.IDLE
var _state_timer: float = 0.0

var _attack_set: AttackSet
var _driver: AnimationDriver
var _idle_clip: StringName = &"idle"
var _hit_clip: StringName = StringName()

var _combo_index: int = 0
var _current: AttackConfig
var _wants_chain: bool = false

var _hitbox: AttackHitbox
var _attack_sfx: AudioStreamPlayer2D

var _resolver: CombatResolver

# ---------- API pública ----------
func initialize(
		driver: AnimationDriver,
		attack_set: AttackSet,
		idle_clip: StringName,
		hit_clip: StringName,
		hitbox: AttackHitbox,
		attack_sfx: AudioStreamPlayer2D,
		resolver: CombatResolver,
	) -> void:
	_driver = driver
	_attack_set = attack_set
	_idle_clip = idle_clip
	_hit_clip = hit_clip
	_hitbox = hitbox
	_attack_sfx = attack_sfx
	_resolver = resolver
	assert(_driver != null, "AnimationDriver não pode ser nulo")
	assert(_attack_set != null, "AttackSet não pode ser nulo")
	assert(_hit_clip != StringName(), "Hit clip não pode ser nulo")
	assert(_hitbox != null, "AttackHitbox não pode ser nulo")

	_driver.connect_body_end(self, &"_on_body_end")
	_driver.connect_to_idle_end(self, &"_on_to_idle_end")
	_hitbox.hit_hurtbox.connect(Callable(self, "_on_hit_hurtbox"))

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
	
	_hitbox.disable()

	_combo_index = index
	_current = cfg
	_state = State.STARTUP
	_state_timer = maxf(cfg.startup, 0.0)

	var total: float = cfg.startup + cfg.hit + cfg.recovery
	_driver.play_attack_body(cfg.body_clip, cfg.body_frames, cfg.body_fps, total)

func _enter_hit() -> void:
	_state = State.HIT
	_state_timer = maxf(_current.hit, 0.0)
	_hitbox.enable(_current, get_parent())

	_attack_sfx.stream = _current.sfx_swing
	_attack_sfx.play()

func _enter_recover() -> void:
	_state = State.RECOVER
	_state_timer = 0.0
	_hitbox.disable()

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
		_state = State.IDLE
		_current = null

		if last != null and last.to_idle_clip != StringName():
			_driver.play_to_idle(last.to_idle_clip)
		else:
			_driver.play_idle(_idle_clip)

func _on_to_idle_end(_clip: StringName) -> void:
	if _state == State.STUN:
		_state = State.IDLE
		_driver.play_idle(_idle_clip)
	elif _state == State.IDLE:
		_driver.play_idle(_idle_clip)

func _on_hit_hurtbox(area: Area2D, cfg: AttackConfig) -> void:
	if _state != State.HIT:
		return
	_resolver.resolve_hit(get_parent(), area, cfg)

func enter_stun() -> void:
	_hitbox.disable()
	_wants_chain = false
	_current = null

	_state = State.STUN
	_driver.play_to_idle(_hit_clip)

func is_stunned() -> bool:
	return _state == State.STUN
