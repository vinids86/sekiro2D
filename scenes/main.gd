extends Node2D

@onready var hub: CombatEventHub = $CombatEventHub

@onready var player: Player = $Player
@onready var enemy: Enemy = $Enemy

func _ready() -> void:
	# registrar lutadores para o Hub ouvir os STARTUPs
	hub.register_fighter(player, player.controller)
	hub.register_fighter(enemy, enemy.controller)

	# IA de parry do Enemy (para parryar o Player)
	$Enemy/ParryAIDriver.setup(enemy, enemy.controller, hub, enemy.parry_profile, enemy.parry_ai_profile)

	# Se quiser que o Player (controlado por IA) parrye o Enemy, faça o simétrico:
	# $Player/ParryAIDriver.setup(player, player.controller, hub, player.parry_profile, player.parry_ai_profile)
