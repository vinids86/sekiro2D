extends Node2D
class_name Enemy

# ---------------- Exports ----------------
@export var attack_set: AttackSet
@export var idle_clip: StringName = &"idle"
@export var hurtbox: Hurtbox
@export var health: Health
@export var anim_profile: AnimProfile
@export var parry_profile: ParryProfile
@export var hitreact_profile: HitReactProfile
@export var attack_profile: EnemyAttackProfile
@export var parried_profile: ParriedProfile
@export var guard_profile: GuardProfile
@export var counter_profile: CounterProfile
@export var special_sequence_primary: Array[AttackConfig]
@export var dodge_profile: DodgeProfile
@export var finisher_profile: FinisherProfile

# ---------------- Nós da cena ----------------
@onready var facing: Node2D = $Facing
@onready var sprite: AnimatedSprite2D = $Facing/AnimatedSprite2D
@onready var controller: CombatController = $CombatController
@onready var hitbox: AttackHitbox = $Facing/AttackHitbox
@onready var animation: AnimationPlayer = $Facing/AnimationPlayer
@onready var stamina: Stamina = $Stamina

# Listeners (nós filhos dedicados)
@onready var anim_listener: CombatAnimListener = $CombatAnimListener
@onready var sfx_listener: CombatSfxListener = $CombatSfxListener

@onready var sfx_swing: AudioStreamPlayer2D = $Sfx/Swing
@onready var sfx_impact: AudioStreamPlayer2D = $Sfx/Impact
@onready var sfx_parry_startup: AudioStreamPlayer2D = $Sfx/ParryStartup
@onready var sfx_parry_success: AudioStreamPlayer2D = $Sfx/ParrySuccess
@onready var sfx_dodge: AudioStreamPlayer2D = $Sfx/Dodge
@onready var sfx_heavy: AudioStreamPlayer2D = $Sfx/Heavy
@onready var sfx_combo_parry_enter: AudioStreamPlayer2D = $Sfx/ComboParryEnter
@onready var ai_driver: EnemyAIDriver = $EnemyAIDriver

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
	assert(guard_profile != null, "GuardProfile não atribuído no Enemy")
	assert(counter_profile != null, "CounterProfile não atribuído no Enemy")

	_driver = AnimationDriverSprite.new(sprite)
	controller.initialize(attack_set, parry_profile, hitreact_profile, parried_profile, guard_profile, counter_profile, dodge_profile, finisher_profile)

	# Listeners
	anim_listener.setup(
		controller,
		animation,
		sprite,
		parry_profile,
		dodge_profile,
		hitreact_profile,
		parried_profile,
		guard_profile,
	)
	sfx_listener.setup(
		controller,
		parry_profile,
		dodge_profile,
		hitreact_profile,
		parried_profile,
		guard_profile,
	)
	hitbox.setup(controller, self)

	stamina.setup(controller)
	
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


func _on_detection_area_body_entered(body: Node2D) -> void:
	if body == null:
		return
	if body.is_in_group("player") == false:
		return

	var player_cc: CombatController = body.get("controller") as CombatController
	if player_cc == null:
		print("[Enemy] DetectionArea ENTER: player encontrado, MAS sem 'controller' válido. body=", body.name)
	else:
		print("[Enemy] DetectionArea ENTER: player encontrado; controller OK. body=", body.name)
		ai_driver.set_target_controller(player_cc)

	ai_driver.set_target_in_range(true)
	print("[Enemy] in_range=true")


func _on_detection_area_body_exited(body: Node2D) -> void:
	if body == null:
		return
	if body.is_in_group("player") == false:
		return

	ai_driver.set_target_in_range(false)
	print("[Enemy] DetectionArea EXIT: in_range=false. body=", body.name)
