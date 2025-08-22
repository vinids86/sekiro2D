extends Resource
class_name GuardProfile

# Cap absoluto POR GOLPE, absorvido 1:1 pela stamina.
@export var defense_absorb_cap: float = 20.0

# AttackConfig do FINISHER que este personagem executa quando o oponente entra em GUARD_BROKEN.
@export var finisher: AttackConfig

# Tempos utilitários de feedback/estados ligados à guarda.
@export var guard_hit_time: float = 0.10
@export var guard_recover_time: float = 0.30

# Duração do estado após sofrer o FINISHER (animação pós-golpe).
@export var post_finisher_react_time: float = 0.70
