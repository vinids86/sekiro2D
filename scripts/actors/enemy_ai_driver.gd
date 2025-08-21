extends Node
class_name EnemyAIDriver

@export var profile: EnemyAttackProfile
@export var debug_ai: bool = false

var _controller: CombatController
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _timer: Timer
var _wired: bool = false

func setup(controller: CombatController, attack_profile: EnemyAttackProfile) -> void:
	_controller = controller
	profile = attack_profile
	_wire()

func _ready() -> void:
	# suporte a configurar via exports no editor
	if _timer == null:
		_timer = Timer.new()
		_timer.one_shot = true
		add_child(_timer)
		_timer.timeout.connect(_on_timeout)
	if _controller != null and profile != null and not _wired:
		_wire()

func _wire() -> void:
	assert(_controller != null, "EnemyAIDriver: CombatController nulo")
	assert(profile != null, "EnemyAIDriver: EnemyAttackProfile nulo")
	_wired = true
	_rng.randomize()
	var first: float = maxf(profile.start_delay, 0.0)
	first = clampf(first, 0.0, 60.0)
	_start_timer(first)
	if debug_ai:
		print("[AI] armed: start_delay=", str(first),
			" period=", str(profile.period), " jitter=±", str(profile.jitter),
			" press_only_in_idle=", str(profile.press_only_in_idle))

func _on_timeout() -> void:
	if not is_instance_valid(_controller):
		return

	var st: int = _controller.get_state()
	var can_press: bool = true
	if profile.press_only_in_idle:
		can_press = st == CombatController.State.IDLE

	if can_press:
		_controller.on_attack_pressed()
		if debug_ai:
			print("[AI] attack pressed | state=", _state_name(st))
	else:
		if debug_ai:
			print("[AI] skipped (state=", _state_name(st), ")")

	# agenda próxima tentativa
	var next_delay: float = _next_period()
	_start_timer(next_delay)

func _next_period() -> float:
	var base: float = maxf(profile.period, 0.0)
	var jitter: float = maxf(profile.jitter, 0.0)
	var delta: float = 0.0
	if jitter > 0.0:
		delta = _rng.randf_range(-jitter, jitter)
	var v: float = base + delta
	if v < 0.05:
		v = 0.05
	if v > 60.0:
		v = 60.0
	return v

func _start_timer(seconds: float) -> void:
	if seconds <= 0.0:
		seconds = 0.001  # próximo frame
	_timer.start(seconds)

# utilitário de debug
func _state_name(s: int) -> String:
	match s:
		CombatController.State.IDLE: return "IDLE"
		CombatController.State.STARTUP: return "STARTUP"
		CombatController.State.HIT: return "HIT"
		CombatController.State.RECOVER: return "RECOVER"
		CombatController.State.STUN: return "STUN"
		CombatController.State.PARRY_STARTUP: return "PARRY_STARTUP"
		CombatController.State.PARRY_SUCCESS: return "PARRY_SUCCESS"
		CombatController.State.PARRY_RECOVER: return "PARRY_RECOVER"
		CombatController.State.HIT_REACT: return "HIT_REACT"
		_: return "UNKNOWN"
