extends Resource
class_name AttackConfig

const AttackKind := CombatTypes.AttackKind

@export var startup: float = 0.25
@export var hit: float = 0.08
@export var recovery: float = 0.25

@export var body_clip: StringName = &"atk1"
@export var anim_fps: float = 30.0

@export var hitbox_offset: Vector2 = Vector2(60, 0)

@export var sfx_swing: AudioStream

# dano ÚNICO; a regra global decide spillover para HP
@export var damage: float = 1.0

# finisher segue sua lógica atual

@export_enum("LIGHT", "HEAVY", "COUNTER", "FINISHER", "COMBO")
var kind: int = AttackKind.LIGHT

@export var parryable: bool = true
