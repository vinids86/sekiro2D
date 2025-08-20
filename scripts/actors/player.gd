extends CharacterBody2D
class_name Player

@export var attack_set: AttackSet
@export var idle_clip: StringName = &"idle"
@export var hit_clip: StringName = &"hit"

@onready var sprite: AnimatedSprite2D = $Facing/AnimatedSprite2D
@onready var controller: CombatController = $CombatController
@onready var hitbox: AttackHitbox = $Facing/AttackHitbox
@onready var sfx_attack: AudioStreamPlayer2D = $SfxAttack
@onready var facing: Node2D = $Facing
@onready var anim_listener: CombatAnimListener = $CombatAnimListener
@onready var hitbox_driver: HitboxDriver = $HitboxDriver
@onready var sfx_driver: SfxDriver = $SfxDriver

var _driver: AnimationDriver

func _ready() -> void:
	assert(sprite != null)
	assert(controller != null)
	assert(hitbox != null)
	assert(sfx_attack != null)
	assert(attack_set != null)

	# 1) Cria o driver concreto (RefCounted) para animar o sprite
	_driver = AnimationDriverSprite.new(sprite)

	# 2) Inicializa o CombatController
	# Se você já tem initialize_v2 (sem hitbox/sfx/resolver), use:
	# controller.initialize_v2(_driver, attack_set, idle_clip, hit_clip)
	# Caso ainda esteja com o initialize antigo, implemente o wrapper v2 ou ignore os extras:
	controller.initialize(_driver, attack_set, idle_clip, hit_clip,)

	# 3) Liga os listeners (injeção por código, sem NodePath)
	anim_listener.setup(controller, _driver, idle_clip)
	hitbox_driver.setup(controller, hitbox, self, facing)
	sfx_driver.setup(controller, sfx_attack)

	# 4) Estado visual inicial
	_driver.play_idle(idle_clip)

func _unhandled_input(event: InputEvent) -> void:
	if controller.is_stunned():
		return
	if event.is_action_pressed("attack"):
		controller.on_attack_pressed()

func _process(delta: float) -> void:
	controller.update(delta)
