extends Node2D
class_name Enemy

# ---------------- Exports ----------------
@export var attack_set: AttackSet
@export var idle_clip: StringName = &"idle"
@export var hurtbox: Hurtbox
@export var health: Health
@export var anim_profile: AnimProfile
@export var parry_profile: ParryProfile
@export var parry_ai_profile: ParryAIProfile
@export var hit_react_profile: HitReactProfile
@export var sfx_bank: SfxBank
@export var attack_profile: EnemyAttackProfile
@export var hub: CombatEventHub
@export var parried_profile: ParriedProfile
@export var guard_profile: GuardProfile
@export var counter_profile: CounterProfile
@export var special_sequence_primary: Array[AttackConfig]    # <--- combo do inimigo
@export var dodge_profile: DodgeProfile

# ---------------- Nós da cena ----------------
@onready var facing: Node2D = $Facing
@onready var sprite: AnimatedSprite2D = $Facing/AnimatedSprite2D
@onready var controller: CombatController = $CombatController
@onready var hitbox: AttackHitbox = $Facing/AttackHitbox
@onready var animation: AnimationPlayer = $Facing/AnimationPlayer
@onready var ai_driver: EnemyAIDriver = $EnemyAIDriver
@onready var stamina: Stamina = $Stamina

# Listeners (nós filhos dedicados)
@onready var anim_listener: CombatAnimListener = $CombatAnimListener

@onready var sfx_swing: AudioStreamPlayer2D = $Sfx/Swing
@onready var sfx_impact: AudioStreamPlayer2D = $Sfx/Impact
@onready var sfx_parry_startup: AudioStreamPlayer2D = $Sfx/ParryStartup
@onready var sfx_parry_success: AudioStreamPlayer2D = $Sfx/ParrySuccess
@onready var sfx_dodge: AudioStreamPlayer2D = $Sfx/Dodge
@onready var sfx_heavy: AudioStreamPlayer2D = $Sfx/Heavy
@onready var sfx_driver: SfxDriver = $Sfx/SfxDriver
@onready var sfx_combo_parry_enter: AudioStreamPlayer2D = $Sfx/ComboParryEnter
@onready var recoil: ParryRecoilDriver = $ParryRecoilDriver

# ---------------- Internos ----------------
var _driver: AnimationDriver
var _last_hp: float = 0.0

func _ready() -> void:
	# Sanidade
	assert(attack_set != null, "AttackSet não configurado no Enemy")
	assert(sprite != null, "AnimatedSprite2D não encontrado no Enemy")
	assert(controller != null, "CombatController não encontrado no Enemy")
	assert(hitbox != null, "AttackHitbox não encontrado no Enemy")
	assert(hurtbox != null, "Hurtbox não atribuída no Enemy")
	assert(health != null, "Health não atribuído no Enemy")
	assert(facing != null, "Facing não atribuído no Enemy")
	assert(anim_listener != null, "CombatAnimListener não encontrado no Enemy")
	assert(sfx_driver != null, "SfxDriver não encontrado no Enemy")
	assert(guard_profile != null, "GuardProfile não atribuído no Enemy")
	assert(counter_profile != null, "CounterProfile não atribuído no Enemy")

	_driver = AnimationDriverSprite.new(sprite)
	controller.initialize(attack_set, parry_profile, hit_react_profile, parried_profile, guard_profile, counter_profile, dodge_profile)

	# Listeners
	anim_listener.setup(
		controller,
		animation,
		sprite,
		parry_profile,
		dodge_profile,
		hit_react_profile,
		parried_profile,
		guard_profile,
	)
	hitbox.setup(controller, self)
	sfx_driver.setup(
		controller,
		sfx_bank,
		sfx_swing,
		sfx_impact,
		sfx_parry_startup,
		sfx_parry_success,
		sfx_dodge,
		sfx_heavy,
		sfx_combo_parry_enter
	)
	recoil.setup(self, controller, hub, parried_profile)

	# AI
	ai_driver.setup(controller, attack_profile)
	ai_driver.special_sequence_primary = special_sequence_primary  # <--- entrega a sequência p/ AI

	# Estado visual inicial
	_driver.play_idle(idle_clip)

	# Saúde / dano
	_last_hp = health.current
	health.changed.connect(Callable(self, "_on_health_changed"))
	health.died.connect(Callable(self, "_on_health_died"))

func _process(delta: float) -> void:
	controller.update(delta)

func _on_health_changed(current: float, maximum: float) -> void:
	if current < _last_hp:
		var dmg: float = _last_hp - current
		print("[Enemy] levou ", roundi(dmg), " de dano (", roundi(current), "/", roundi(maximum), ")")
	_last_hp = current

func _on_health_died() -> void:
	print("[Enemy] morreu")
	queue_free()
