extends Resource
class_name AttackConfig

@export var name_id: StringName = &"atk1"

@export var startup: float = 0.25
@export var hit: float = 0.10
@export var recovery: float = 0.25

@export var body_clip: StringName = &"atk1"
@export var body_frames: int = 12
@export var body_fps: float = 30.0

@export var to_idle_clip: StringName = &"atk1_to_idle"
@export var to_parried_clip: StringName = StringName()

@export var hitbox_offset: Vector2 = Vector2(60, 0)

@export var sfx_swing: AudioStream
@export var sfx_windup: AudioStream

# dano ÚNICO; a regra global decide spillover para HP
@export var damage: float = 1.0

# finisher segue sua lógica atual
@export var is_finisher: bool = false

# NOVOS CAMPOS (somente o necessário):
# - heavy: define que é ataque pesado (não-parryável por REGRA no controller; startup com hyper armor)
@export var heavy: bool = false

# - required_dodge_dir: direção exigida para esquiva que evita este golpe
#   0 = NEUTRAL, 1 = DOWN (ver CombatTypes.DodgeDir)
#   Para o heavy_up, setar para 1 (DOWN) no resource do editor.
@export var required_dodge_dir: int = 0
