extends Node
class_name Stamina

signal changed(current: float, maximum: float)

@export var max_stamina: float = 100.0
@export var regen_rate: float = 25.0      # por segundo
@export var regen_delay: float = 0.5      # segundos sem regen após gastar

var stamina: float = 0.0
var _cooldown: float = 0.0

func _ready() -> void:
	# inicia cheio se vier 0.0 do editor
	if stamina <= 0.0:
		stamina = max_stamina
	else:
		if stamina > max_stamina:
			stamina = max_stamina
	# liga atualização e notifica HUD
	set_process(true)
	emit_signal("changed", stamina, max_stamina)

func _process(delta: float) -> void:
	if _cooldown > 0.0:
		_cooldown -= delta
		if _cooldown < 0.0:
			_cooldown = 0.0
		return

	if stamina < max_stamina and regen_rate > 0.0:
		stamina += regen_rate * delta
		if stamina > max_stamina:
			stamina = max_stamina
		emit_signal("changed", stamina, max_stamina)

# ---- API nova (compatível com o ImpactDriver) ----
func get_current() -> float:
	return stamina

func get_max() -> float:
	return max_stamina

# Consome até 'amount' (parcial é permitido). Retorna quanto foi realmente consumido.
func consume(amount: float) -> float:
	if amount <= 0.0:
		return 0.0
	var take: float = amount
	if take > stamina:
		take = stamina
	if take <= 0.0:
		return 0.0
	stamina -= take
	_cooldown = regen_delay
	emit_signal("changed", stamina, max_stamina)
	return take

# ---- API antiga (mantida) ----
func can_spend(cost: float) -> bool:
	return stamina >= cost

# Tenta gastar o valor integral. Retorna true se conseguiu tudo.
func spend(cost: float) -> bool:
	if cost <= 0.0:
		return true
	if stamina < cost:
		return false
	# usa a mesma mecânica de consumo (mas exigindo integral)
	var taken: float = consume(cost)
	return taken >= cost - 0.0001

# Utilitários
func refill() -> void:
	stamina = max_stamina
	emit_signal("changed", stamina, max_stamina)

func add(amount: float) -> void:
	if amount <= 0.0:
		return
	stamina += amount
	if stamina > max_stamina:
		stamina = max_stamina
	emit_signal("changed", stamina, max_stamina)

func pause_regen(seconds: float) -> void:
	if seconds <= 0.0:
		return
	_cooldown = seconds
