extends Node
class_name ScreenClamp

@export var body_path: NodePath            # quem vamos travar (geralmente ".")
@export var margin: Vector2 = Vector2.ZERO # margem pra não “encostar” (ex.: metade do collider)

var _body: Node2D
var _cam: Camera2D

func _ready() -> void:
	_body = get_node_or_null(body_path) as Node2D
	assert(_body, "ScreenClamp: body_path inválido")

	_cam = get_tree().get_first_node_in_group("main_camera") as Camera2D

	assert(_cam, "ScreenClamp: não encontrei Camera2D (defina camera_path ou coloque a câmera no grupo 'main_camera').")

func physics_tick() -> void:
	if not _cam or not _body:
		return

	# tamanho da viewport em pixels e correção pelo zoom da câmera
	var vs: Vector2 = get_viewport().size
	var half := Vector2(vs.x * 0.5 * _cam.zoom.x, vs.y * 0.5 * _cam.zoom.y)
	var center := _cam.global_position

	var min := center - half + margin
	var max := center + half - margin

	var p := _body.global_position
	p.x = clamp(p.x, min.x, max.x)
	p.y = clamp(p.y, min.y, max.y)
	_body.global_position = p
