extends CharacterBody2D
class_name Player

@export var attack_set: AttackSet
@export var idle_clip: StringName = &"idle"
@export var hit_clip: StringName = &"hit"
@export var anim_profile: AnimProfile

@onready var sprite: AnimatedSprite2D = $Facing/AnimatedSprite2D
@onready var controller: CombatController = $CombatController
@onready var hitbox: AttackHitbox = $Facing/AttackHitbox
@onready var sfx_attack: AudioStreamPlayer2D = $SfxAttack
@onready var facing: Node2D = $Facing
@onready var hurtbox: Hurtbox = $Hurtbox

@onready var health: Health = $Health
@onready var anim_listener: CombatAnimListener = $CombatAnimListener
@onready var hitbox_driver: HitboxDriver = $HitboxDriver
@onready var sfx_driver: SfxDriver = $SfxDriver
@onready var impact: ImpactDriver = $ImpactDriver

var _driver: AnimationDriver

func _ready() -> void:
	assert(sprite != null)
	assert(controller != null)
	assert(hitbox != null)
	assert(sfx_attack != null)
	assert(attack_set != null)

	_driver = AnimationDriverSprite.new(sprite)
	controller.initialize(_driver, attack_set, idle_clip, hit_clip,)

	impact.setup(hurtbox, health, controller)
	anim_listener.setup(controller, _driver, anim_profile)
	hitbox_driver.setup(controller, hitbox, self, facing)
	sfx_driver.setup(controller, sfx_attack)

	_driver.play_idle(idle_clip)

func _unhandled_input(event: InputEvent) -> void:
	if controller.is_stunned():
		return
	if event.is_action_pressed("attack"):
		controller.on_attack_pressed()

func _process(delta: float) -> void:
	controller.update(delta)
