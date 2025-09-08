extends StateConfig
class_name AttackConfig

const AttackKind := CombatTypes.AttackKind

@export var startup: float = 0.25
@export var hit: float = 0.10
@export var recovery: float = 0.25

@export var body_clip: StringName = &"atk1"
@export var anim_fps: float = 30.0

@export var hitbox_offset: Vector2 = Vector2(120, 0)

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
@export var poise_break: float = 10.0
@export var action_poise: float = 4.0
@export var grants_momentum_poise: float = 1.0

# --- NOVO: Grupo de Movimento ---
@export_group("Movimento")
@export var startup_velocity: Vector2 = Vector2.ZERO
@export var active_velocity: Vector2 = Vector2.ZERO
@export var recover_velocity: Vector2 = Vector2.ZERO
