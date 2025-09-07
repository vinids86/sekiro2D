# Anexe este script ao seu nó "NuvemAnimada" (Node2D)

extends Node2D

@onready var sprite: Sprite2D = $Cloud
@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var timer: Timer = $Timer

# Definimos as posições de início e fim aqui para fácil ajuste
# Assumindo uma tela de 1920 de largura. (1920 / 2 = 960)
var start_x_position: float = 1100.0
# A posição Y será aleatória

func _ready() -> void:
	# Conectamos os dois sinais que vão controlar nosso loop
	timer.timeout.connect(_on_timer_timeout)
	animation_player.animation_finished.connect(_on_animation_finished)
	
	# Começamos o primeiro ciclo do timer manualmente
	# Ele vai esperar o tempo definido no inspetor e então chamar _on_timer_timeout
	timer.start()

# Esta função é chamada apenas quando o TEMPO DE ESPERA do timer acaba
func _on_timer_timeout() -> void:
	# 1. Prepara a nuvem para sua entrada (ainda fora da tela)
	sprite.position.x = start_x_position
	sprite.position.y = randf_range(-200.0, 200.0) # Ajuste a altura se desejar
	var random_scale = randf_range(0.15, 0.2)
	sprite.scale = Vector2(random_scale, random_scale)
	
	# 2. Torna a nuvem visível e toca a animação
	sprite.visible = true
	animation_player.play("DriftAcross")

# Esta função é chamada apenas quando a ANIMAÇÃO "DriftAcross" TERMINA
func _on_animation_finished(_anim_name: StringName) -> void:
	# 1. Esconde a nuvem novamente, pois ela já saiu da tela
	sprite.visible = false
	
	# 2. Define um novo tempo de espera e reinicia o timer para a PRÓXIMA nuvem
	timer.wait_time = randf_range(15.0, 45.0) # Intervalo aleatório para a próxima
	timer.start()
