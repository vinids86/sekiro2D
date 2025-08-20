extends Node2D
class_name Enemy

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var controller: CombatController = $CombatController
@onready var hitbox: AttackHitbox = $AttackHitbox
@onready var sfx_attack: AudioStreamPlayer2D = $SfxAttack
@onready var resolver: CombatResolver = $CombatResolver

@export var attack_set: AttackSet
@export var idle_clip: StringName = &"idle"
@export var hit_clip: StringName = &"hit"
@export var hurtbox: Hurtbox
@export var health: Health
@export var sfx_hit: AudioStreamPlayer2D

var _last_hp: int = 0
var _driver: AnimationDriver

func _ready() -> void:
	assert(hurtbox != null, "Hurtbox não atribuída no Enemy")
	assert(health != null, "Health não atribuído no Enemy")
	assert(sfx_hit != null, "SfxHit não atribuído no Enemy")

	_driver = AnimationDriverSprite.new(sprite)
	controller.initialize(
		_driver,
		attack_set,
		idle_clip,
		hit_clip,
		hitbox,
		sfx_attack,
		resolver
	)
	_last_hp = health.hp
	health.changed.connect(Callable(self, "_on_health_changed"))
	health.died.connect(Callable(self, "_on_health_died"))
	
	_driver.play_idle(idle_clip)

func _on_health_changed(current: int, maximum: int) -> void:
	if current < _last_hp:
		var dmg: int = _last_hp - current
		print("[Enemy] levou ", dmg, " de dano (", current, "/", maximum, ")")
		sfx_hit.play()
	_last_hp = current

func _on_health_died() -> void:
	print("[Enemy] morreu")
	queue_free()
