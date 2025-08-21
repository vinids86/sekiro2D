extends CharacterBody2D
class_name Player

@export var attack_set: AttackSet
@export var anim_profile: AnimProfile
@export var parry_profile: ParryProfile
@export var hit_react_profile: HitReactProfile
@export var sfx_bank: SfxBank

@onready var sprite: AnimatedSprite2D = $Facing/AnimatedSprite2D
@onready var controller: CombatController = $CombatController
@onready var hitbox: AttackHitbox = $Facing/AttackHitbox
@onready var facing: Node2D = $Facing
@onready var hurtbox: Hurtbox = $Hurtbox

@onready var health: Health = $Health
@onready var anim_listener: CombatAnimListener = $CombatAnimListener
@onready var hitbox_driver: HitboxDriver = $HitboxDriver
@onready var impact: ImpactDriver = $ImpactDriver

@onready var sfx_swing: AudioStreamPlayer2D = $Sfx/Swing
@onready var sfx_impact: AudioStreamPlayer2D = $Sfx/Impact
@onready var sfx_parry_startup: AudioStreamPlayer2D = $Sfx/ParryStartup
@onready var sfx_parry_success: AudioStreamPlayer2D = $Sfx/ParrySuccess
@onready var sfx_driver: SfxDriver = $Sfx/SfxDriver

var _driver: AnimationDriver

func _ready() -> void:
	assert(sprite != null)
	assert(controller != null)
	assert(hitbox != null)
	assert(attack_set != null)

	_driver = AnimationDriverSprite.new(sprite)
	controller.initialize(_driver, attack_set, parry_profile, hit_react_profile)

	impact.setup(hurtbox, health, controller)
	anim_listener.setup(controller, _driver, anim_profile)
	hitbox_driver.setup(controller, hitbox, self, facing)
	
	sfx_driver.setup(controller, sfx_bank, sfx_swing, sfx_impact, sfx_parry_startup, sfx_parry_success)

	_driver.play_idle(anim_profile.idle_clip)

func _unhandled_input(event: InputEvent) -> void:
	if controller.is_stunned():
		return
	if event.is_action_pressed("attack"):
		controller.on_attack_pressed()
	if event.is_action_pressed("parry"):
		controller.on_parry_pressed()

func _process(delta: float) -> void:
	controller.update(delta)
