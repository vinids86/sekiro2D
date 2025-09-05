extends Resource
class_name ParryProfile

@export var window: float = 0.20     # duração da janela ativa do parry
@export var recover: float = 0.60    # tempo de recover após falha
@export var success: float = 1.00    # lock após parry bem-sucedido

# ===== SONS (diretos) por fase do estado PARRY =====
@export var startup_effect_stream: AudioStream   # toca na fase ACTIVE do PARRY (início da janela)
@export var startup_voice_stream: AudioStream

@export var success_effect_stream: AudioStream   # toca na fase SUCCESS do PARRY
@export var success_voice_stream: AudioStream

@export var recover_effect_stream: AudioStream   # toca na fase RECOVER do PARRY
@export var recover_voice_stream: AudioStream
