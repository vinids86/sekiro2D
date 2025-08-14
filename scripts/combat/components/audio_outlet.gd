extends Node
class_name AudioOutlet

@export var player_path: NodePath
var _player: AudioStreamPlayer2D
var _cache := {}

func _ready() -> void:
	_player = get_node_or_null(player_path) as AudioStreamPlayer2D
	assert(_player, "AudioOutlet: player_path inválido")

func play_stream(stream: AudioStream) -> void:
	if stream == null: return
	_player.stream = stream
	_player.play()
