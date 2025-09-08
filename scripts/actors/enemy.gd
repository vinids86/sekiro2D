extends CharacterBody2D
class_name Enemy

# ---------------- Exports ----------------
@export var gravity: float = 2500.0
@export var max_fall_speed: float = 1800.0
@export var jump_impulse: float = 750.0 # só para o próximo passo (pulo)

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
@export var locomotion_profile: LocomotionProfile

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
@onready var ai_driver: EnemyAIDriver = $EnemyAIDriver
@onready var mover: MoveController = $MoveController

# ---------------- Internos ----------------
var _driver: AnimationDriver
var _last_hp: float = 0.0

func _ready() -> void:
	print("--- Enemy _ready() INICIOU ---")
	print("Controller antes do await: ", controller)
	print("controller: ", controller)
	#await controller.ready
	print("controller await: ", controller)
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
	controller.initialize(attack_set, parry_profile, hitreact_profile, parried_profile, guard_profile, counter_profile, dodge_profile, finisher_profile, 0)

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
		locomotion_profile,
		mover,
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
	pass

func _physics_process(delta: float) -> void:
	if mover == null:
		return
	if controller == null:
		return

	# ===== Gravidade (Vertical) =====
	if not is_on_floor():
		velocity.y += gravity * delta
		if velocity.y > max_fall_speed:
			velocity.y = max_fall_speed
	else:
		if velocity.y > 0.0:
			velocity.y = 0.0
			
	# --- NOVA LÓGICA DE MOVIMENTO HORIZONTAL ---
	
	# 1. Primeiro, pegamos a velocidade definida pelo estado atual
	var state_velocity: Vector2 = Vector2.ZERO
	if controller:
		var current_state = controller.get_state_instance_for(controller.get_state())
		if current_state.has_method("get_current_movement_velocity"):
			state_velocity = current_state.get_current_movement_velocity(controller)

	# 2. Agora, decidimos como combinar com o input da IA
	if state_velocity != Vector2.ZERO:
		# Se a ação do estado tem uma velocidade definida, ela SOBRESCREVE a IA.
		velocity.x = state_velocity.x * facing.scale.x # Multiplica pela direção
		if state_velocity.y != 0:
			velocity.y = state_velocity.y
	else:
		# Se a ação do estado não tem movimento, usamos o input da IA.
		var fd: FacingDriver = facing as FacingDriver
		if fd == null: return
		var stamina_inimigo: Stamina = _try_get_opponent_stamina(fd)
		var ai: EnemyAIDriver = ai_driver as EnemyAIDriver
		if ai == null: return
		var axis: float = ai.get_move_axis(self, fd, stamina, stamina_inimigo, delta)
		var vx: float = mover.compute_vx(self, controller, fd, axis, delta)
		velocity.x = vx

	move_and_slide()

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

# Helper completo e tipado para buscar a Stamina do oponente por convenção de nó
func _try_get_opponent_stamina(fd: FacingDriver) -> Stamina:
	if fd == null:
		return null
	var opp: Node = fd.opponent
	if opp == null:
		return null
	# Ajuste este caminho se sua cena do Player organizar diferente
	var s: Stamina = opp.get_node_or_null("Stamina") as Stamina
	return s
