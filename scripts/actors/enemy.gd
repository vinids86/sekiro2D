extends Node2D
class_name Enemy

# ---------------- Exports ----------------
@export var attack_set: AttackSet
@export var idle_clip: StringName = &"idle"
@export var hit_clip: StringName = &"hit"
@export var hurtbox: Hurtbox
@export var health: Health
@export var sfx_hit: AudioStreamPlayer2D
@export var anim_profile: AnimProfile
@export var parry_profile: ParryProfile

# ---------------- Nós da cena ----------------
@onready var facing: Node2D = $Facing
@onready var sprite: AnimatedSprite2D = $Facing/AnimatedSprite2D
@onready var controller: CombatController = $CombatController
@onready var hitbox: AttackHitbox = $Facing/AttackHitbox
@onready var sfx_attack: AudioStreamPlayer2D = $SfxAttack

# Listeners (nós filhos dedicados)
@onready var anim_listener: CombatAnimListener = $CombatAnimListener
@onready var hitbox_driver: HitboxDriver = $HitboxDriver
@onready var sfx_driver: SfxDriver = $SfxDriver
@onready var impact: ImpactDriver = $ImpactDriver

# ---------------- Internos ----------------
var _driver: AnimationDriver
var _last_hp: int = 0

func _ready() -> void:
	# Sanidade
	assert(attack_set != null, "AttackSet não configurado no Enemy")
	assert(sprite != null, "AnimatedSprite2D não encontrado no Enemy")
	assert(controller != null, "CombatController não encontrado no Enemy")
	assert(hitbox != null, "AttackHitbox não encontrado no Enemy")
	assert(sfx_attack != null, "SfxAttack não encontrado no Enemy")
	assert(hurtbox != null, "Hurtbox não atribuída no Enemy")
	assert(health != null, "Health não atribuído no Enemy")
	assert(sfx_hit != null, "SfxHit não atribuído no Enemy")

	assert(anim_listener != null, "CombatAnimListener não encontrado no Enemy")
	assert(hitbox_driver != null, "HitboxDriver não encontrado no Enemy")
	assert(sfx_driver != null, "SfxDriver não encontrado no Enemy")

	_driver = AnimationDriverSprite.new(sprite)
	controller.initialize(_driver, attack_set, parry_profile)

	# 3) Liga os listeners (injeção direta, sem NodePath)
	anim_listener.setup(controller, _driver, anim_profile)
	hitbox_driver.setup(controller, hitbox, self, facing)
	sfx_driver.setup(controller, sfx_attack)
	impact.setup(hurtbox, health, controller)

	# 4) Estado visual inicial
	_driver.play_idle(idle_clip)

	# 5) Saúde / dano
	_last_hp = health.hp
	health.changed.connect(Callable(self, "_on_health_changed"))
	health.died.connect(Callable(self, "_on_health_died"))

func _process(delta: float) -> void:
	controller.update(delta)

func _on_health_changed(current: int, maximum: int) -> void:
	if current < _last_hp:
		var dmg: int = _last_hp - current
		print("[Enemy] levou ", dmg, " de dano (", current, "/", maximum, ")")
		sfx_hit.play()
	_last_hp = current

func _on_health_died() -> void:
	print("[Enemy] morreu")
	queue_free()
