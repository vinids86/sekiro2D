extends CharacterBody2D
class_name Player

@export var attack_set: AttackSet
@export var idle_clip: StringName = &"idle"
@export var hit_clip: StringName = &"hit"

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var controller: CombatController = $CombatController
@onready var hitbox: AttackHitbox = $AttackHitbox
@onready var sfx_attack: AudioStreamPlayer2D = $SfxAttack
@onready var resolver: CombatResolver = $CombatResolver
@onready var stamina: Stamina = $Stamina

var _driver: AnimationDriver

func _ready() -> void:
	assert(sprite != null, "AnimatedSprite2D não encontrado no Player")
	assert(controller != null, "CombatController não encontrado no Player")
	assert(hitbox != null, "AttackHitbox não encontrado no Player")
	assert(sfx_attack != null, "SfxAttack não encontrado no Player")
	assert(resolver != null, "CombatResolver não encontrado no Player")
	assert(stamina != null, "Stamina não encontrado no Player")

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
	_driver.play_idle(idle_clip)

func _unhandled_input(event: InputEvent) -> void:
	if controller.is_stunned():
		return
	if event.is_action_pressed("attack"):
		controller.on_attack_pressed()

func _process(delta: float) -> void:
	controller.update(delta)
