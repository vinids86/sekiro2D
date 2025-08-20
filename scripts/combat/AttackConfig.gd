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

@export var hitbox_offset: Vector2 = Vector2(60, 0)
