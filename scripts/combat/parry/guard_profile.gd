extends Resource
class_name GuardProfile

@export var defense_power: int = 20            # quanto DANO por hit a guarda absorve usando stamina (1:1)
@export var guard_hit_time: float = 0.10       # tranco curto ao bloquear (feedback)
@export var guard_recover_time: float = 0.30   # recuperação: não pode atacar, pode iniciar parry
