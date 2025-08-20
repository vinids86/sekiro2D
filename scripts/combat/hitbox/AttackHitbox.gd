extends Area2D
class_name AttackHitbox

@onready var shape: CollisionShape2D = $CollisionShape2D

var _cfg: AttackConfig
var _attacker: Node2D

func _ready() -> void:
	monitoring = false
	shape.disabled = true
	visible = false

func enable(cfg: AttackConfig, attacker: Node2D) -> void:
	assert(cfg != null, "AttackHitbox.enable: cfg nulo")
	assert(attacker != null, "AttackHitbox.enable: attacker nulo")

	_cfg = cfg
	_attacker = attacker

	monitoring = true
	shape.disabled = false
	visible = true

func disable() -> void:
	monitoring = false
	shape.disabled = true
	visible = false
	_cfg = null
	_attacker = null

func get_current_config() -> AttackConfig: return _cfg
func get_attacker() -> Node2D: return _attacker
