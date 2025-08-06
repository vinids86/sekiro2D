extends TextureProgressBar

@export var enemy: Enemy

func _ready():
	update()
	enemy.health_changed.connect(update)
	
func update():
	if enemy:
		value = clamp(enemy.current_health, min_value, max_value)
