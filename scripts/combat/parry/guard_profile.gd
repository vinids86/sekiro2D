extends Resource
class_name GuardProfile

# Máximo de dano (em pontos) que a guarda pode absorver POR GOLPE,
# usando stamina numa razão 1:1. Ex.: 20 significa "absorve até 20 do golpe".
@export var defense_absorb_cap: float = 20.0

@export var guard_hit_time: float = 0.10     # feedback curto ao bloquear
@export var guard_recover_time: float = 0.30 # recuperação após block
