extends CharacterBody2D
class_name Enemy

# ---------------- Exports ----------------
@export var gravity: float = 2500.0
@export var max_fall_speed: float = 1800.0
@export var jump_impulse: float = 750.0

@export var attack_set: AttackSet
@export var idle_clip: StringName = &"idle"
@export var hurtbox: Hurtbox
@export var health: Health
@export var anim_profile: AnimProfile
@export var parry_profile: ParryProfile
@export var hitreact_profile: HitReactProfile
@export var parried_profile: ParriedProfile
@export var guard_profile: GuardProfile
@export var counter_profile: CounterProfile
@export var special_sequence_primary: Array[AttackConfig]
@export var dodge_profile: DodgeProfile
@export var finisher_profile: FinisherProfile
@export var locomotion_profile: LocomotionProfile

# ---------------- Nós da cena ----------------
@onready var facing: Node2D = $Facing
@onready var sprite: AnimatedSprite2D = $Facing/AnimatedSprite2D
@onready var controller: CombatController = $CombatController
@onready var hitbox: AttackHitbox = $Facing/AttackHitbox
@onready var animation: AnimationPlayer = $Facing/AnimationPlayer
@onready var stamina: Stamina = $Stamina

# Listeners e Drivers
@onready var anim_listener: CombatAnimListener = $CombatAnimListener
@onready var sfx_listener: CombatSfxListener = $CombatSfxListener
@onready var ai_driver: EnemyAIDriver = $EnemyAIDriver
@onready var mover: MoveController = $MoveController

# ---------------- Internos ----------------
var _driver: AnimationDriver
var _last_hp: float = 0.0

func _ready() -> void:
	# Sanidade
	assert(attack_set != null, "AttackSet não configurado no Enemy")
	assert(controller != null, "CombatController não encontrado no Enemy")
	# ... (outros asserts continuam importantes)

	# --- MODIFICADO: Simplificamos a inicialização e removemos awaits ---
	_driver = AnimationDriverSprite.new(sprite)
	controller.initialize(attack_set, parry_profile, hitreact_profile, parried_profile, guard_profile, counter_profile, dodge_profile, finisher_profile, 0)

	# Listeners
	anim_listener.setup(controller, animation, sprite, parry_profile, dodge_profile, hitreact_profile, parried_profile, guard_profile, locomotion_profile, mover)
	sfx_listener.setup(controller, parry_profile, dodge_profile, hitreact_profile, parried_profile, guard_profile)
	hitbox.setup(controller, self)
	stamina.setup(controller)
	
	_driver.play_idle(idle_clip)

	health.changed.connect(_on_health_changed)
	health.died.connect(_on_health_died)

func _physics_process(delta: float) -> void:
	if mover == null or controller == null or ai_driver == null:
		return

	# ===== Gravidade (Vertical) - Sem alterações =====
	if not is_on_floor():
		velocity.y += gravity * delta
		velocity.y = min(velocity.y, max_fall_speed)
	else:
		if velocity.y > 0.0:
			velocity.y = 0.0
			
	# --- LÓGICA DE MOVIMENTO REFINADA ---
	
	# 1. Primeiro, verificamos se uma ação (ataque/esquiva) está ditando o movimento.
	var state_velocity: Vector2 = Vector2.ZERO
	var current_state = controller.get_state_instance_for(controller.get_state())
	if current_state.has_method("get_current_movement_velocity"):
		state_velocity = current_state.get_current_movement_velocity(controller)

	# 2. Decidimos qual velocidade usar
	if state_velocity != Vector2.ZERO:
		# Se a ação tem uma velocidade, ela SOBRESCREVE a IA.
		velocity.x = state_velocity.x * facing.scale.x
		if state_velocity.y != 0:
			velocity.y = state_velocity.y
	#else:
		# Se não há ação com movimento, a IA decide o eixo de movimento.
		#var axis: float = ai_driver.get_move_axis()
		#var fd: FacingDriver = facing as FacingDriver
		#var vx: float = mover.compute_vx(self, controller, fd, axis, delta)
		#velocity.x = vx

	move_and_slide()

func _on_health_changed(current: float, _maximum: float) -> void:
	if current < _last_hp:
		var dmg: float = _last_hp - current
	_last_hp = current

func _on_health_died() -> void:
	queue_free()

# --- MODIFICADO: Simplificamos a passagem de informação para a IA ---
func _on_detection_area_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		var player_cc: CombatController = body.get_node_or_null("CombatController") as CombatController
		if player_cc:
			ai_driver.set_target_controller(player_cc)

func _on_detection_area_body_exited(body: Node2D) -> void:
	if body.is_in_group("player"):
		ai_driver.set_target_controller(null)
