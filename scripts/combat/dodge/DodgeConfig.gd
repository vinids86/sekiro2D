# DodgeConfig.gd
extends StateConfig
class_name DodgeConfig

# Propriedades de timing e custo para esta esquiva específica
@export var startup: float = 0.05
@export var active: float = 0.25
@export var recover: float = 0.30
@export var stamina_cost: float = 3.0
@export var has_iframes: bool = true # Controla a invencibilidade

# Propriedades de movimento que o StateDodge vai ler
@export_group("Movimento")
@export var startup_velocity: Vector2 = Vector2.ZERO
@export var active_velocity: Vector2 = Vector2.ZERO
@export var recover_velocity: Vector2 = Vector2.ZERO
