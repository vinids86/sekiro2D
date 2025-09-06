extends StateConfig
class_name AttackConfig

const AttackKind := CombatTypes.AttackKind

@export var startup: float = 0.25
@export var hit: float = 0.08
@export var recovery: float = 0.25

@export var body_clip: StringName = &"atk1"
@export var anim_fps: float = 30.0

@export var hitbox_offset: Vector2 = Vector2(60, 0)

# ===== SONS DO ATAQUE (effects) =====
@export var sfx_startup_stream: AudioStream
@export var sfx_swing_stream: AudioStream
@export var sfx_recover_stream: AudioStream

# ===== VOZ DO ATAQUE (voice) =====
@export var voice_startup_stream: AudioStream
@export var voice_swing_stream: AudioStream
@export var voice_recover_stream: AudioStream

# dano ÚNICO; a regra global decide spillover para HP
@export var damage: float = 1.0

@export_enum("LIGHT", "HEAVY", "COUNTER", "FINISHER", "COMBO")
var kind: int = AttackKind.LIGHT

@export var parryable: bool = true

# ====== POISE / INTERRUPÇÃO ======
# Quanto este golpe consegue "quebrar" poise do alvo ao tentar interrompê-lo.
@export var poise_break: float = 10.0

# Quanto de poise o ATACANTE ganha enquanto executa este golpe (ATTACK).
@export var action_poise: float = 4.0
