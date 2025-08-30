extends Resource
class_name GuardProfile

# Cap absoluto POR GOLPE, absorvido 1:1 pela stamina.
@export var defense_absorb_cap: float = 20.0

# AttackConfig do FINISHER que este personagem executa quando o oponente entra em GUARD_BROKEN.
@export var finisher: AttackConfig

# Tempos utilitários de feedback/estados ligados à guarda.

# Duração do estado após sofrer o FINISHER (animação pós-golpe).

@export var block_recover: float = 0.2
