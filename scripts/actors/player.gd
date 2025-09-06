extends CharacterBody2D
class_name Player

enum DodgeDir { NEUTRAL, DOWN, UP, LEFT, RIGHT }
enum HeavyDir { NEUTRAL, UP }

const DIR_THRESHOLD: float = 0.45

@export var attack_set: AttackSet
@export var anim_profile: AnimProfile
@export var parry_profile: ParryProfile
@export var hit_react_profile: HitReactProfile
@export var parried_profile: ParriedProfile
@export var guard_profile: GuardProfile
@export var counter_profile: CounterProfile
@export var dodge_profile: DodgeProfile
@export var hitreact_profile: HitReactProfile
@export var finisher_profile: FinisherProfile
@export var locomotion_profile: LocomotionProfile

@export var heavy_up_config: AttackConfig
@export var special_sequence_primary: Array[AttackConfig]

@onready var sprite: AnimatedSprite2D = $Facing/AnimatedSprite2D
@onready var animation: AnimationPlayer = $Facing/AnimationPlayer
@onready var controller: CombatController = $CombatController
@onready var hitbox: AttackHitbox = $Facing/AttackHitbox
@onready var facing: Node2D = $Facing
@onready var hurtbox: Hurtbox = $Hurtbox
@onready var mover: MoveController = $MoveController

@onready var health: Health = $Health
@onready var anim_listener: CombatAnimListener = $CombatAnimListener
@onready var sfx_listener: CombatSfxListener = $CombatSfxListener
@onready var stamina: Stamina = $Stamina

@onready var sfx_swing: AudioStreamPlayer2D = $Sfx/Swing
@onready var sfx_impact: AudioStreamPlayer2D = $Sfx/Impact
@onready var sfx_parry_startup: AudioStreamPlayer2D = $Sfx/ParryStartup
@onready var sfx_parry_success: AudioStreamPlayer2D = $Sfx/ParrySuccess
@onready var sfx_dodge: AudioStreamPlayer2D = $Sfx/Dodge
@onready var sfx_heavy: AudioStreamPlayer2D = $Sfx/Heavy
@onready var sfx_combo_parry_enter: AudioStreamPlayer2D = $Sfx/ComboParryEnter

var _driver: AnimationDriver

func _ready() -> void:
	assert(sprite != null)
	assert(controller != null)
	assert(hitbox != null)
	assert(attack_set != null)

	_driver = AnimationDriverSprite.new(sprite)
	controller.initialize(attack_set, parry_profile, hit_react_profile, parried_profile, guard_profile, counter_profile, dodge_profile, finisher_profile)

	hitbox.setup(controller, self)
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
	stamina.setup(controller)

	_driver.play_idle(anim_profile.idle_clip)

func _process(delta: float) -> void:
	controller.update(delta)

func _physics_process(delta: float) -> void:
	if mover == null:
		return

	var axis: float = Input.get_axis("move_left", "move_right")
	var fd: FacingDriver = facing as FacingDriver

	var vx: float = mover.compute_vx(self, controller, fd, axis, delta)
	velocity.x = vx
	velocity.y = 0.0

	move_and_slide()

func _unhandled_input(event: InputEvent) -> void:
	if controller.is_stunned():
		return

	# --- DODGE + direção (queremos só DOWN por enquanto) ---
	if event.is_action_pressed("dodge"):
		var dir: int = _read_dodge_dir()
		controller.on_dodge_pressed(stamina, CombatTypes.DodgeDir.DOWN)
		return
		
	# --- HEAVY + UP (prévia visual) ---
	if event.is_action_pressed("attack_heavy"):
		controller.on_heavy_attack_pressed(heavy_up_config)
		return

	# --- Inputs existentes ---
	if event.is_action_pressed("attack"):
		controller.on_attack_pressed()
		return

	if event.is_action_pressed("parry"):
		controller.on_parry_pressed()
		return

	if event.is_action_pressed("combo1"):
		controller.on_combo_pressed(special_sequence_primary)
		return

# --- helper local (Player.gd) ---
func _opponent_combo_blocks_combo_parry() -> bool:
	# Acessa FacingDriver
	var fd: FacingDriver = facing as FacingDriver
	assert(fd != null, "Player: FacingDriver ausente em ^\"Facing\"")

	var opp: Node2D = fd.opponent
	if opp == null or not is_instance_valid(opp):
		return false

	if not opp.has_node(^"CombatController"):
		return false
	var occ: CombatController = opp.get_node(^"CombatController") as CombatController
	if occ == null:
		return false

	var offense: bool = occ.is_combo_offense_active()
	var last_hit: bool = occ.is_combo_last_attack()
	return offense and not last_hit

func _opponent_combo_offense_active() -> bool:
	# Acessa o FacingDriver para descobrir o oponente
	var facing_driver: FacingDriver = facing as FacingDriver
	if facing_driver == null:
		return false

	var opp: Node2D = facing_driver.opponent
	if opp == null or not is_instance_valid(opp):
		return false

	# Pega o CombatController do oponente
	if not opp.has_node(^"CombatController"):
		return false
	var opp_cc: CombatController = opp.get_node(^"CombatController") as CombatController
	if opp_cc == null:
		return false

	var s: int = opp_cc.get_state()

	# Consideramos "ofensivo" as fases que levam a golpes ou preparam a janela:
	var in_offense: bool = false

	return in_offense

# Lê o vetor de movimento no frame do dodge e resolve para um DodgeDir
func _read_dodge_dir() -> int:
	var axis: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	# Apenas DOWN por enquanto; UP/LEFT/RIGHT ficam reservados para o futuro
	if axis.y > DIR_THRESHOLD:
		return DodgeDir.DOWN
	return DodgeDir.NEUTRAL


# Lê direção para HEAVY: precisamos de UP
func _read_heavy_dir() -> int:
	var axis: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if axis.y < -DIR_THRESHOLD:
		return HeavyDir.UP
	return HeavyDir.NEUTRAL

# Prévia visual: heavy ascendente (só quando UP estiver pressionado)
func _play_heavy_preview(dir: int) -> void:
	if dir == HeavyDir.UP:
		controller.try_attack_heavy(heavy_up_config)
