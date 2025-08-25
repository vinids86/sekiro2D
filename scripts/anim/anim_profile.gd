extends Resource
class_name AnimProfile

@export var idle_clip: StringName = &"idle"
@export var hit_clip: StringName = &"hit"

@export var parry_startup_clip: StringName = &"parry_startup"
@export var parry_success_clip_a: StringName = &"parry_success_a"
@export var parry_success_clip_b: StringName = &"parry_success_b"
@export var parry_recover_clip: StringName = &"parry_recover"

@export var guard_hit_clip: StringName = &"block_hit"
@export var guard_recover_clip: StringName = &"guard_recover"

@export var guard_broken_clip: StringName = &"guard_broken"
@export var broken_finisher_clip: StringName = &"broken_finisher"
@export var pre_combo: StringName = &"pre_combo"
@export var dodge_down_clip: StringName = &"dodge_down"
