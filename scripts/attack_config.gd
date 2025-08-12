# AttackConfig.gd
extends Resource
class_name AttackConfig

var startup: float
var duration: float
var recovery: float
var stamina_cost: float

var attack_animation: String = ""
var startup_animation: String = ""
var recovery_animation: String = ""
var attack_sound: String = ""

func _init(_startup: float, _duration: float, _recovery: float, _stamina_cost: float,
		   _attack_anim := "", _attack_sound := "", _startup_anim := "", _recovery_anim := ""):
	startup = _startup
	duration = _duration
	recovery = _recovery
	stamina_cost = _stamina_cost
	attack_animation = _attack_anim
	startup_animation = _startup_anim
	recovery_animation = _recovery_anim
	attack_sound = _attack_sound


static func default_sequence() -> Array[AttackConfig]:
	return [
		AttackConfig.new(0.3, 0.2, 0.2, 2, "attack_1", "res://audio/attack1.wav", "startup_1", "recover_1"),
		AttackConfig.new(0.1, 0.2, 0.2, 3, "attack_2", "res://audio/attack2.wav", "startup_2", "recover_2"),
		AttackConfig.new(0.3, 0.2, 0.2, 3, "attack_3", "res://audio/attack3.wav", "startup_3", "recover_3"),
	]
