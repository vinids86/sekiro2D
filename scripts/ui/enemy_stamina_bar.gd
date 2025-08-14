extends TextureProgressBar

@export var enemy: Enemy

func _ready():
	update()
	enemy.stamina_changed.connect(update)
	
func update():
	if enemy:
		value = clamp(enemy.stats.current_stamina, min_value, max_value)
