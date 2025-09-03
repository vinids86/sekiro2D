extends Node
class_name Stamina

signal changed(current: float, maximum: float)
signal emptied

@export var maximum: float = 100.0
@export var current: float = 100.0

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
		var ratio: float = current / prev_max
		current = clampf(maximum * ratio, 0.0, maximum)
	else:
		current = clampf(current, 0.0, maximum)
	_emit_changed()

# Consome até 'amount' e retorna QUANTO foi consumido (0..amount).
func consume(amount: float) -> float:
	if amount <= 0.0:
		return 0.0
	var take: float = amount
	if current < take:
		take = current
	set_current(current - take)
	return take

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

func is_empty() -> bool:
	return current <= 0.0

func get_percentage() -> float:
	if maximum <= 0.0:
		return 0.0
	return clampf(current / maximum, 0.0, 1.0)

func _emit_changed() -> void:
	emit_signal("changed", current, maximum)
