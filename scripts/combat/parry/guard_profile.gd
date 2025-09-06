extends Resource
class_name GuardProfile

# Cap absoluto POR GOLPE, absorvido 1:1 pela stamina.
@export var defense_absorb_cap: float = 5.0

# Tempos utilitários de feedback/estados ligados à guarda.

# Duração do estado após sofrer o FINISHER (animação pós-golpe).
@export var block_recover: float = 2.2

@export var broken_finisher_lock: float = 10.0 # OBRIGATÓRIO configurar (> 0), validado em runtime

# ===== SONS (diretos) =====
# Block normal (auto-block)
@export var block_effect_stream: AudioStream
@export var block_voice_stream: AudioStream

# Guard quebrada
@export var broken_effect_stream: AudioStream
@export var broken_voice_stream: AudioStream
