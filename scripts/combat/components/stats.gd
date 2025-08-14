extends Node
class_name Stats

signal stamina_changed(current: float, max_value: float)
signal health_changed(current: float, max_value: float)
signal died

@export var max_health := 100.0
@export var max_stamina := 100.0
@export var stamina_recovery_rate := 20.0     # por segundo
@export var stamina_recovery_delay := 1.0     # segundos sem recuperar após gasto
@export var exhausted_threshold := 10.0       # opcional: limiar (pode ser sincronizado com block_stamina_cost)

var current_health := 0.0
var current_stamina := 0.0
var _stamina_recovery_timer := 0.0

func _ready() -> void:
	current_health = max_health
	current_stamina = max_stamina
	stamina_changed.emit(current_stamina, max_stamina)
	health_changed.emit(current_health, max_health)

func tick(delta: float) -> void:
	if _stamina_recovery_timer > 0.0:
		_stamina_recovery_timer -= delta
	else:
		if current_stamina < max_stamina:
			current_stamina = clamp(current_stamina + stamina_recovery_rate * delta, 0.0, max_stamina)
			stamina_changed.emit(current_stamina, max_stamina)

func has_stamina(amount: float) -> bool:
	return current_stamina >= amount

func consume_stamina(amount: float) -> void:
	var before := current_stamina
	current_stamina = clamp(current_stamina - amount, 0.0, max_stamina)
	if current_stamina != before:
		stamina_changed.emit(current_stamina, max_stamina)
		_stamina_recovery_timer = stamina_recovery_delay

func add_stamina(amount: float) -> void:
	current_stamina = clamp(current_stamina + amount, 0.0, max_stamina)
	stamina_changed.emit(current_stamina, max_stamina)

func take_damage(amount: float) -> void:
	current_health = clamp(current_health - amount, 0.0, max_health)
	health_changed.emit(current_health, max_health)
	if current_health <= 0.0:
		died.emit()

func is_exhausted(threshold: float) -> bool:
	return current_stamina < threshold
