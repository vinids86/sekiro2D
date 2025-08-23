extends Area2D
class_name AttackHitbox

@onready var shape: CollisionShape2D = $CollisionShape2D

var _cfg: AttackConfig
var _effective_cfg: AttackConfig   # cópia temporária com overrides runtime (se necessário)
var _attacker: Node2D

var _runtime_damage_mul: float = 1.0

func _ready() -> void:
	monitoring = false
	shape.disabled = true
	visible = false

func enable(cfg: AttackConfig, attacker: Node2D) -> void:
	assert(cfg != null, "AttackHitbox.enable: cfg nulo")
	assert(attacker != null, "AttackHitbox.enable: attacker nulo")

	_cfg = cfg
	_attacker = attacker

	# Prepara uma visão efetiva do config se houver modificadores runtime
	# (evita alterar o Resource original e mantém consumidores lendo via get_current_config())
	if _runtime_damage_mul != 1.0:
		_effective_cfg = cfg.duplicate(true)
		_effective_cfg.damage = maxf(0.0, cfg.damage * _runtime_damage_mul)
	else:
		_effective_cfg = null

	monitoring = true
	shape.disabled = false
	visible = true

func disable() -> void:
	monitoring = false
	shape.disabled = true
	visible = false

	_cfg = null
	_effective_cfg = null
	_attacker = null

	# reseta modificadores runtime para a próxima ativação
	_runtime_damage_mul = 1.0

func set_runtime_damage_multiplier(m: float) -> void:
	# aceita valores >= 0; 1.0 é neutro
	if m < 0.0:
		m = 0.0
	_runtime_damage_mul = m

func get_runtime_damage_multiplier() -> float:
	return _runtime_damage_mul

func get_current_config() -> AttackConfig:
	# Se houver visão efetiva (com overrides), priorize-a
	if _effective_cfg != null:
		return _effective_cfg
	return _cfg

func get_attacker() -> Node2D:
	return _attacker
