extends Area2D

@onready var shape: CollisionShape2D = $CollisionShape2D
var _already_applied := {}  # evita aplicar duas vezes no mesmo alvo enquanto a hitbox está ligada

func _ready():
	monitoring = false
	shape.disabled = true
	connect("area_entered", Callable(self, "_on_area_entered"))
	# opcional, mas recomendo: cobre caso seu alvo seja um Body e não uma Area
	connect("body_entered", Callable(self, "_on_body_entered"))

func enable():
	_already_applied.clear()
	monitoring = true
	shape.disabled = false
	visible = true
	# <<< IMPORTANTE: varrer quem já está dentro após atualizar a física
	call_deferred("_emit_existing_overlaps")

func disable():
	monitoring = false
	shape.disabled = true
	visible = false
	_already_applied.clear()

func _emit_existing_overlaps() -> void:
	# espera um tick de física para as colisões atualizarem
	await get_tree().physics_frame
	for area in get_overlapping_areas():
		_on_area_entered(area)
	# cobre também corpos, se sua máscara alcançar o Player/Enemy diretamente
	for body in get_overlapping_bodies():
		_on_body_entered(body)

func _on_area_entered(area: Area2D) -> void:
	var defender = area.get_parent()
	var attacker = get_parent()
	if defender == attacker:
		return
	if _already_applied.has(defender):
		return
	if defender.has_method("receive_attack"):
		_already_applied[defender] = true
		defender.receive_attack(attacker)

func _on_body_entered(body: Node) -> void:
	var defender = body
	var attacker = get_parent()
	if defender == attacker:
		return
	if _already_applied.has(defender):
		return
	if defender.has_method("receive_attack"):
		_already_applied[defender] = true
		defender.receive_attack(attacker)
