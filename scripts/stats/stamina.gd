extends Node
class_name Stamina

signal changed(current: float, maximum: float)

@export var maximum: float = 100.0
@export var current: float = 100.0

# Regen apenas em IDLE após um pequeno warmup parado.
@export var idle_regen_per_second: float = 10.0
@export var idle_warmup: float = 0.35

var _is_idle: bool = false
var _idle_elapsed: float = 0.0

var _controller: CombatController
var _wired: bool = false

func _ready() -> void:
	current = clampf(current, 0.0, maximum)
	_emit_changed()

# Conexão explícita com o CombatController (sem "magias")
func setup(controller: CombatController) -> void:
	if controller == null:
		return
	# Evita conexões duplicadas e troca segura de controller
	if _wired and _controller == controller:
		return
	if _wired and _controller != null:
		if _controller.state_entered.is_connected(_on_state_entered):
			_controller.state_entered.disconnect(_on_state_entered)
		if _controller.state_exited.is_connected(_on_state_exited):
			_controller.state_exited.disconnect(_on_state_exited)
	_controller = controller
	_controller.state_entered.connect(_on_state_entered)
	_controller.state_exited.connect(_on_state_exited)
	_wired = true

func _on_state_entered(state: int, cfg: AttackConfig) -> void:
	# Entra em IDLE: inicia warmup; qualquer outro estado: corta regen imediatamente
	if state == CombatController.State.IDLE:
		_is_idle = true
		_idle_elapsed = 0.0
	else:
		_is_idle = false
		_idle_elapsed = 0.0

func _on_state_exited(state: int, cfg: AttackConfig) -> void:
	# Saiu de IDLE: para regen no mesmo frame da troca
	if state == CombatController.State.IDLE:
		_is_idle = false
		_idle_elapsed = 0.0

func _process(delta: float) -> void:
	if _is_idle:
		if _idle_elapsed < idle_warmup:
			_idle_elapsed += delta
		if _idle_elapsed >= idle_warmup and idle_regen_per_second > 0.0 and current < maximum:
			recover(idle_regen_per_second * delta)

func set_current(value: float) -> void:
	var prev: float = current
	current = clampf(value, 0.0, maximum)
	if current != prev:
		_emit_changed()

# “Tudo ou nada”: só consome se houver stamina suficiente.
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
