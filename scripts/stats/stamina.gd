extends Node
class_name Stamina

signal changed(current: float, maximum: float)

@export var maximum: float = 100.0
@export var current: float = 100.0

# Se você já tem regen/consumo alhures, pode remover/mesclar estes helpers.
@export var regen_per_second: float = 0.0
@export var can_regen: bool = false

func _ready() -> void:
	current = clampf(current, 0.0, maximum)
	_emit_changed()

func _process(delta: float) -> void:
	if can_regen and regen_per_second > 0.0 and current < maximum:
		recover(regen_per_second * delta)

func set_current(value: float) -> void:
	var prev: float = current
	current = clampf(value, 0.0, maximum)
	if current != prev:
		_emit_changed()

func set_maximum(value: float, keep_ratio: bool = true) -> void:
	var prev_max: float = maximum
	maximum = maxf(0.0, value)
	if keep_ratio and prev_max > 0.0:
		var ratio: float = 0.0
		ratio = current / prev_max
		current = clampf(maximum * ratio, 0.0, maximum)
	else:
		current = clampf(current, 0.0, maximum)
	_emit_changed()

func consume(amount: float) -> bool:
	if amount <= 0.0:
		return true
	var ok: bool = current >= amount
	set_current(current - amount)
	return ok

func recover(amount: float) -> void:
	if amount <= 0.0:
		return
	set_current(current + amount)

func is_empty() -> bool:
	return current <= 0.0

func get_percentage() -> float:
	if maximum <= 0.0:
		return 0.0
	return clampf(current / maximum, 0.0, 1.0)

func _emit_changed() -> void:
	emit_signal("changed", current, maximum)
