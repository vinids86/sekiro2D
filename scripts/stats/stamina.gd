extends Node
class_name Stamina

signal changed(current: float, maximum: float)

@export var max_stamina: float = 100.0
@export var regen_rate: float = 25.0      # por segundo
@export var regen_delay: float = 0.5      # segundos sem regen após gastar

var stamina: float
var _cooldown: float = 0.0

func _ready() -> void:
	stamina = clampf(stamina if stamina != 0.0 else max_stamina, 0.0, max_stamina)
	emit_signal("changed", stamina, max_stamina)
	set_process(true)

func _process(delta: float) -> void:
	if _cooldown > 0.0:
		_cooldown -= delta
		if _cooldown < 0.0:
			_cooldown = 0.0
		return
	if stamina < max_stamina:
		stamina = minf(max_stamina, stamina + regen_rate * delta)
		emit_signal("changed", stamina, max_stamina)

func can_spend(cost: float) -> bool:
	return stamina >= cost

func spend(cost: float) -> bool:
	if cost <= 0.0:
		return true
	if stamina < cost:
		return false
	stamina -= cost
	_cooldown = regen_delay
	emit_signal("changed", stamina, max_stamina)
	return true

func refill() -> void:
	stamina = max_stamina
	emit_signal("changed", stamina, max_stamina)
