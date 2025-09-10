# EnemyAIProfile.gd
extends Resource
class_name EnemyAIProfile

@export_group("Comportamento Geral")
# Tempo (s) que o jogador precisa ficar em IDLE para a IA considerar atacar.
@export var idle_patience_time: float = 1.0
# Cooldown (s) após a IA ser aparada. Durante este tempo, ela não iniciará ataques.
@export var post_parry_cooldown: float = 1.2

@export_group("Comportamento Ofensivo")
# Chance (0.0 a 1.0) de iniciar um ataque quando o jogador está em IDLE por muito tempo.
@export var idle_attack_chance: float = 1.0
# Se o RECOVER do jogador for >= que isso, a IA pune imediatamente.
@export var punish_recover_threshold: float = 0.4

@export_group("Comportamento Defensivo (Parry Adaptativo)")
# A chance de parry para cada golpe consecutivo que a IA recebe.
# Posição 0 = 1º golpe, Posição 1 = 2º golpe, etc. O último valor se repete.
@export var parry_chance_per_hit: PackedFloat32Array = [0.20, 0.50, 0.80, 0.95]
# Tempo (s) que o jogador precisa parar de atacar para o contador de pressão zerar.
@export var pressure_reset_time: float = 1.5
