extends TextureProgressBar

@export var player: Player

func _ready():
	update()
	player.health_changed.connect(update)
	
func update():
	if player:
		value = clamp(player.stats.current_health, min_value, max_value)
