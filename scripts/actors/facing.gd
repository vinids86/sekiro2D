extends Node2D
class_name FacingDriver

@export var auto_find_opponent: bool = true
@export var opponent_node: Node  # opcional: se quiser setar manualmente

# ---- FX (config explícita, sem autodetect) ----
@export var fx_sprite_path: NodePath                      # aponte para o AnimatedSprite2D (ou outro CanvasItem que tem o ShaderMaterial)
@export var fx_flash_duration: float = 0.08               # duração do clarão
@export var fx_flash_color: Color = Color(1.0, 0.95, 0.6, 1.0) # cor do clarão (âmbar/quente). Ajuste à vontade no Inspector.

var opponent: Node2D
var sign: int = 1  # +1 direita, -1 esquerda

# internos de FX
var _fx_sprite: CanvasItem
var _fx_mat: ShaderMaterial
var _fx_tween: Tween

func _ready() -> void:
	# O root do personagem (pai do Facing) deve estar no grupo "fighter"
	if opponent_node != null:
		opponent = opponent_node as Node2D
	elif auto_find_opponent:
		opponent = _find_opponent()
	set_process(true)

	# ----- FX: exige configuração explícita -----
	assert(fx_sprite_path != NodePath(""), "FacingDriver: fx_sprite_path não configurado. Aponte para o AnimatedSprite2D (ou CanvasItem) com o ShaderMaterial do 'flash'.")
	var node_ref: Node = get_node(fx_sprite_path)
	_fx_sprite = node_ref as CanvasItem
	assert(_fx_sprite != null, "FacingDriver: fx_sprite_path deve apontar para um CanvasItem válido.")

	_fx_mat = _fx_sprite.material as ShaderMaterial
	assert(_fx_mat != null, "FacingDriver: o nó alvo não possui ShaderMaterial.")
	# Testa uniforms esperados (lança erro se não existirem)
	_fx_mat.set_shader_parameter("flash", false)
	_fx_mat.set_shader_parameter("flash_color", fx_flash_color)

func _process(_dt: float) -> void:
	if opponent == null or not is_instance_valid(opponent):
		if auto_find_opponent:
			opponent = _find_opponent()
		return

	var me_x: float = get_parent().global_position.x   # root do personagem
	var opp_x: float = opponent.global_position.x
	var new_sign: int = 1
	if opp_x < me_x:
		new_sign = -1
	if new_sign != sign:
		sign = new_sign
		scale = Vector2(float(sign), 1.0)  # espelha AnimatedSprite2D e AttackHitbox

func _find_opponent() -> Node2D:
	var root_char: Node = get_parent()
	var nodes: Array = get_tree().get_nodes_in_group("fighter")
	for n in nodes:
		if n != root_char and n is Node2D:
			return n
	return null

func get_facing_sign() -> int:
	return sign

# -------- FX API --------
func flash() -> void:
	assert(_fx_sprite != null and _fx_mat != null, "FacingDriver.flash: sprite/material não inicializados. Verifique fx_sprite_path e o ShaderMaterial com uniforms 'flash' e 'flash_color'.")

	# mata tween anterior (se houver) pra não acumular
	if _fx_tween != null and _fx_tween.is_running():
		_fx_tween.kill()
		_fx_tween = null

	# seta cor do clarão e liga o flash no shader
	_fx_mat.set_shader_parameter("flash_color", fx_flash_color)
	_fx_mat.set_shader_parameter("flash", true)

	# agenda o desligamento do flash após a duração
	var d: float = fx_flash_duration
	if d <= 0.0:
		d = 0.01
	_fx_tween = create_tween()
	_fx_tween.tween_callback(func() -> void:
		_fx_mat.set_shader_parameter("flash", false)
	).set_delay(d)
