extends Area2D
class_name Hurtbox

signal contact(attacker: Node2D, cfg: AttackConfig, hitbox: AttackHitbox)

@export var team: int = 0            # 0=neutro, 1=player, 2=inimigo...
@export var invulnerable: bool = false

func _ready() -> void:
	monitoring = true
	monitorable = true
	area_entered.connect(_on_area_entered)

func _on_area_entered(area: Area2D) -> void:
	if invulnerable:
		return

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

	# (opcional) filtro por time se o atacante fornecer time
	var attacker_team_provider := attacker as Node
	if attacker_team_provider != null and attacker_team_provider.has_meta("team"):
		var atk_team: int = int(attacker_team_provider.get_meta("team"))
		if atk_team == team:
			return

	# Apenas broadcast — nada de aplicar dano aqui
	contact.emit(attacker, cfg, atk)
