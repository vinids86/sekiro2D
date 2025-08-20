extends Area2D
class_name Hurtbox

@onready var shape: CollisionShape2D = $CollisionShape2D

signal got_hit(attacker: Node2D, cfg: AttackConfig) # opcional p/ HUD/SFX

func _ready() -> void:
	monitoring = true
	monitorable = true
	shape.disabled = false
	area_entered.connect(_on_area_entered)

func _on_area_entered(area: Area2D) -> void:
	# Só reage se quem entrou é um AttackHitbox atualmente ativo
	var atk: AttackHitbox = area as AttackHitbox
	if atk == null:
		return

	var cfg: AttackConfig = atk.get_current_config()
	var attacker: Node2D = atk.get_attacker()
	if cfg == null or attacker == null:
		return

	var defender: Node2D = get_parent() as Node2D
	if attacker == defender:
		return # ignora auto-hit
		
	print("[HURTBOX]", defender.name, "recebeu de", attacker.name,
		  "  atkLayer=", atk.collision_layer, "  hbMask=", collision_mask)

	# --- aplica efeitos de gameplay no DEFENSOR ---
	var health: Health = defender.get_node(^"Health") as Health
	var cc: CombatController = defender.get_node(^"CombatController") as CombatController
	assert(health != null, "Health ausente no defensor")
	assert(cc != null, "CombatController ausente no defensor")

	# REGRAS mínimas (ajuste conforme seu AttackConfig):
	health.apply_damage(cfg.damage, attacker)
	cc.enter_stun() # ou cc.enter_stun_hit() quando você tiver esse estado

	# Broadcast opcional para HUD/SFX do defensor
	got_hit.emit(attacker, cfg)
