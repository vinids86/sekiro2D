extends Resource
class_name DodgeProfile

@export var startup: float = 0.01
@export var active: float = 0.25
@export var recover: float = 0.30
@export var anim_fps: float = 12
@export var stamina_cost: float = 3.0

# ===== SONS (diretos) =====
@export var effect_stream: AudioStream
@export var voice_stream: AudioStream
