extends Resource
class_name EnemyAttackProfile

@export_category("General")
@export var enabled_default: bool = true
@export var think_interval: float = 0.10
# Não iniciar ataques se o oponente já estiver em ATTACK (STARTUP/ACTIVE).
@export var respect_opponent_turn: bool = true

@export_category("Normal Sequence")
# O próximo input é agendado durante o RECOVER com clamp (recovery - margem de segurança).
@export var inter_hit_delay: float = 0.18
# Dica de comprimento da sequência normal (para pausar no fim e “trocar de turno”).
@export var normal_chain_length_hint: int = 4
# Pausa após concluir a sequência longa (troca de turno provável).
@export var post_sequence_cooldown: float = 0.80

@export_category("Parry (fora de PARRIED)")
# Quatro níveis [1º hit, 2º, 3º, 4º+] (0..1). Ex.: [0.05, 0.15, 0.30, 0.50]
@export var parry_chance_by_hit: PackedFloat32Array = PackedFloat32Array([0.05, 0.15, 0.30, 0.50])

@export_category("Turn-taking / Defesa")
# Pausa após ser parryado (entrega o turno).
@export var post_parried_cooldown: float = 0.60
# Viés defensivo após levar um hit (focar em parry por um tempo).
@export var defense_bias_time: float = 0.50
# Se o RECOVER do player for >= esse limiar, pode atacar mesmo sob viés (punição).
@export var big_recovery_threshold: float = 0.35

@export_category("Parry enquanto PARRIED")
# Chance (0..1) de armar um parry específico para o PRÓXIMO ataque do player enquanto a IA está em PARRIED.
@export var parried_parry_chance: float = 0.25
# Atraso de reação antes de apertar parry nesse caso (segundos).
@export var parried_parry_react_delay: float = 0.04
