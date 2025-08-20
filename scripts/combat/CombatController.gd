extends Node
class_name CombatController

enum State { IDLE, STARTUP, HIT, RECOVER }

var _state: int = State.IDLE
var _state_timer: float = 0.0

var _attack_set: AttackSet
var _driver: AnimationDriver
var _idle_clip: StringName = &"idle"

var _combo_index: int = 0
var _current: AttackConfig
var _wants_chain: bool = false

var _hitbox: AttackHitbox

# ---------- API pública ----------
func initialize(driver: AnimationDriver, set: AttackSet, idle_clip: StringName, hitbox: AttackHitbox) -> void:
	_driver = driver
	_attack_set = set
	_idle_clip = idle_clip
	_hitbox = hitbox
	assert(_driver != null, "AnimationDriver não pode ser nulo")
	assert(_attack_set != null, "AttackSet não pode ser nulo")
	_driver.connect_body_end(self, &"_on_body_end")
	_driver.connect_to_idle_end(self, &"_on_to_idle_end")

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
	if _state == State.IDLE:
		_driver.play_idle(_idle_clip)
