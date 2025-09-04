extends Node
class_name Stamina

signal changed(current: float, maximum: float)

@export var maximum: float = 100.0
@export var current: float = 100.0

@export var idle_regen_per_second: float = 10.0
@export var idle_warmup: float = 0.35

var _can_regen: bool = false
var _idle_elapsed: float = 0.0

var _controller: CombatController

func _ready() -> void:
	current = clampf(current, 0.0, maximum)
	_emit_changed()

func setup(controller: CombatController) -> void:
	assert(controller != null)
	_controller = controller
	_controller.state_entered.connect(_on_state_entered)
	_controller.state_exited.connect(_on_state_exited)

func _on_state_entered(state: int, cfg: AttackConfig) -> void:
	var st: StateBase = CombatStateRegistry.get_state_for(state)
	_can_regen = st.allows_stamina_regen(_controller)
	_idle_elapsed = 0.0

func _on_state_exited(state: int, cfg: AttackConfig) -> void:
	var st: StateBase = CombatStateRegistry.get_state_for(state)
	if st.refills_stamina_on_exit(_controller):
		set_current(maximum)

	_can_regen = false
	_idle_elapsed = 0.0

func _process(delta: float) -> void:
	if _can_regen:
		if _idle_elapsed < idle_warmup:
			_idle_elapsed += delta
		if _idle_elapsed >= idle_warmup and idle_regen_per_second > 0.0 and current < maximum:
			recover(idle_regen_per_second * delta)

func set_current(value: float) -> void:
	var prev: float = current
	current = clampf(value, 0.0, maximum)
	if current != prev:
		_emit_changed()

func try_consume(amount: float) -> bool:
	if amount <= 0.0:
		return true
	if current >= amount:
		set_current(current - amount)
		return true
	return false

func recover(amount: float) -> void:
	if amount <= 0.0:
		return
	set_current(current + amount)

func _emit_changed() -> void:
	emit_signal("changed", current, maximum)
