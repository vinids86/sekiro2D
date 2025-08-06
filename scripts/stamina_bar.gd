extends TextureProgressBar

@export var player: Player

func _ready():
	update()
	player.stamina_changed.connect(update)
	
func update():
	if player:
		value = clamp(player.current_stamina, min_value, max_value)
