extends Resource
class_name EnemyAttackProfile

@export_category("General")
@export var enabled_default: bool = true
@export var think_interval: float = 0.10
# NÃO iniciar ataques se o oponente já estiver em ATTACK (STARTUP/ACTIVE).
@export var respect_opponent_turn: bool = true

@export_category("Normal Sequence")
# A IA tenta ir até o fim da sequência normal (multi-inputs).
# O próximo input é agendado durante o RECOVER com clamp pela janela (usa recovery - segurança).
@export var inter_hit_delay: float = 0.18
# Quantos golpes compõem a sequência "longa" (para acionar pausa pós-sequência).
@export var normal_chain_length_hint: int = 4
# Pausa após concluir a sequência longa (troca de turno provável).
@export var post_sequence_cooldown: float = 0.80

@export_category("Parry Probability by Pressure")
# Quatro níveis [1º hit, 2º, 3º, 4º+] (0..1). Ex.: [0.05, 0.15, 0.30, 0.50]
@export var parry_chance_by_hit: PackedFloat32Array = PackedFloat32Array([0.05, 0.15, 0.30, 0.50])

@export_category("Turn-taking Cooldowns")
# Pausa após ser parryado (entrega o turno).
@export var post_parried_cooldown: float = 0.60
# Viés defensivo após levar um hit (focar em parry por um tempo).
@export var defense_bias_time: float = 0.50
# Se o RECOVER do player for >= esse limiar, pode atacar mesmo sob viés (punição).
@export var big_recovery_threshold: float = 0.35

@export_category("Parried Dodge")
# Chance (0..1) de armar um dodge quando o inimigo entra em PARRIED.
@export var parried_dodge_chance: float = 0.35
# Atraso de reação antes de apertar dodge ao detectar o STARTUP do próximo ataque do player.
@export var parried_dodge_react_delay: float = 0.06

@export_category("Special Combo (one input, runs to end)")
# Dispara o combo especial após N sequências normais tentadas.
@export var normal_sequences_until_special: int = 3
# A sequência especial (na ordem). Controller executa até o fim com um input.
@export var special_combo: Array[AttackConfig] = []

@export_category("Heavy After Successful Parries")
# Dispara heavy após N parries bem-sucedidos da IA.
@export var heavy_after_successful_parries: int = 2
# Cooldown mínimo entre heavies para não spammar.
@export var min_seconds_between_heavies: float = 2.0
# O golpe heavy (sugestão: configurar kind = HEAVY no AttackConfig).
@export var heavy_attack: AttackConfig
