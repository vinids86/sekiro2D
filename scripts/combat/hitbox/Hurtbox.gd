extends Area2D
class_name Hurtbox

signal contact(attacker: Node2D, cfg: AttackConfig, hitbox: AttackHitbox)

func _ready() -> void:
	monitoring = true
	monitorable = true
	area_entered.connect(_on_area_entered)

func _on_area_entered(area: Area2D) -> void:
	var atk: AttackHitbox = area as AttackHitbox
	if atk == null:
		return

	var cfg: AttackConfig = atk.get_current_config()
	var attacker: Node2D = atk.get_attacker()
	if cfg == null or attacker == null:
		return

	var defender: Node2D = get_parent() as Node2D
	if attacker == defender:
		return

	contact.emit(attacker, cfg, atk)
