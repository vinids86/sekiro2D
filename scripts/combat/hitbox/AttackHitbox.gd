extends Area2D
class_name AttackHitbox

@export var shape: CollisionShape2D
@export var reset_position_on_disable: bool = true
@export var owner_mirrors_with_scale: bool = true
# Se true: você vira o Player invertendo o scale.x do nó Player (RECOMENDADO).
# Se false: você vira só o sprite (flip_h). Aí a gente precisa multiplicar o offset manualmente.

signal hit_hurtbox(hurtbox: Area2D, cfg: AttackConfig)

var _active: bool = false
var _already_hit: Dictionary = {}
var _current_cfg: AttackConfig
var _owner: Node2D
var _default_local_position: Vector2 = Vector2.ZERO

func _ready() -> void:
	area_entered.connect(Callable(self, "_on_area_entered"))
	_disable_shapes()
	_default_local_position = position

func enable(cfg: AttackConfig, owner: Node) -> void:
	print("HITBOX enable pos=", position)

	_active = true
	_current_cfg = cfg
	_owner = owner as Node2D
	_already_hit.clear()
	monitoring = true

	# posiciona a hitbox à frente do personagem
	var off: Vector2 = cfg.hitbox_offset
	if not owner_mirrors_with_scale:
		# Caso você NÃO espelhe o Player pelo scale.x e sim só o sprite,
		# precisamos descobrir o "facing" e multiplicar o X manualmente.
		var sign: float = 1.0
		if _owner != null and _owner.scale.x < 0.0:
			sign = -1.0
		off.x = off.x * sign
	position = off

	_enable_shapes()

func disable() -> void:
	_active = false
	_current_cfg = null
	_owner = null
	monitoring = false
	_disable_shapes()
	if reset_position_on_disable:
		position = _default_local_position

func _on_area_entered(area: Area2D) -> void:
	print("entered -> ", area.name)

	if not _active:
		return
	if not area.is_in_group("hurtbox"):
		return
	if _already_hit.has(area):
		return
	_already_hit[area] = true
	emit_signal("hit_hurtbox", area, _current_cfg)

func _enable_shapes() -> void:
	if shape != null:
		shape.disabled = false

func _disable_shapes() -> void:
	if shape != null:
		shape.disabled = true
