extends Node
class_name Health

signal changed(current: float, maximum: float)
signal died

@export var maximum: float = 100.0
@export var current: float = 100.0

func _ready() -> void:
	current = clampf(current, 0.0, maximum)
	_emit_changed()

func set_current(value: float) -> void:
	var prev: float = current
	current = clampf(value, 0.0, maximum)
	if current != prev:
		_emit_changed()
		if current <= 0.0:
			emit_signal("died")

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

func damage(amount: float) -> void:
	if amount <= 0.0:
		return
	set_current(current - amount)

func heal(amount: float) -> void:
	if amount <= 0.0:
		return
	set_current(current + amount)

func is_dead() -> bool:
	return current <= 0.0

func get_percentage() -> float:
	if maximum <= 0.0:
		return 0.0
	return clampf(current / maximum, 0.0, 1.0)

func _emit_changed() -> void:
	emit_signal("changed", current, maximum)

# ===== LISTENER DO ARBITER (DEFENSOR) =====
func _on_defender_impact(cfg: AttackConfig, metrics: ImpactMetrics, result: int) -> void:
	if metrics == null:
		return
	var hp_dmg: float = metrics.hp_damage
	if hp_dmg <= 0.0:
		return
	damage(hp_dmg)
	# Log opcional (curto)
	# print("[Health] hp_damage=%.2f -> new=%.2f" % [hp_dmg, current])
