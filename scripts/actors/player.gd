extends CharacterBody2D
class_name Player

@export var attack_set: AttackSet
@export var anim_profile: AnimProfile
@export var parry_profile: ParryProfile
@export var hit_react_profile: HitReactProfile
@export var sfx_bank: SfxBank
@export var hub: CombatEventHub
@export var parried_profile: ParriedProfile
@export var guard_profile: GuardProfile
@export var counter_profile: CounterProfile
@export var special_sequence_primary: Array[AttackConfig]

@onready var sprite: AnimatedSprite2D = $Facing/AnimatedSprite2D
@onready var controller: CombatController = $CombatController
@onready var hitbox: AttackHitbox = $Facing/AttackHitbox
@onready var facing: Node2D = $Facing
@onready var hurtbox: Hurtbox = $Hurtbox

@onready var health: Health = $Health
@onready var anim_listener: CombatAnimListener = $CombatAnimListener
@onready var hitbox_driver: HitboxDriver = $HitboxDriver
@onready var impact: ImpactDriver = $ImpactDriver
@onready var recoil: ParryRecoilDriver = $ParryRecoilDriver
@onready var stamina: Stamina = $Stamina 

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
	controller.initialize(attack_set, parry_profile, hit_react_profile, parried_profile, guard_profile, counter_profile)

	impact.setup(hurtbox, health, stamina, controller, hub, guard_profile)
	anim_listener.setup(controller, _driver, anim_profile)
	hitbox_driver.setup(controller, hitbox, self, facing)
	recoil.setup(self, controller, hub, parried_profile)

	sfx_driver.setup(controller, sfx_bank, sfx_swing, sfx_impact, sfx_parry_startup, sfx_parry_success)

	# Configura tempos do combo especial com base nos frames do clip único
	_prepare_special_combo_timings()

	_driver.play_idle(anim_profile.idle_clip)

func _unhandled_input(event: InputEvent) -> void:
	if controller.is_stunned():
		return
	if event.is_action_pressed("attack"):
		controller.on_attack_pressed()
	if event.is_action_pressed("parry"):
		controller.on_parry_pressed()
	if event.is_action_pressed("combo1"):
		controller.start_special_combo(special_sequence_primary)

func _process(delta: float) -> void:
	controller.update(delta)

# ------------------------------------------------------------
# Converte frames de HIT do clip único (57 frames) nos tempos
# startup/hit/recovery de cada AttackConfig da sequência.
#
# Premissas:
# - Frames zero-based: 0..56
# - HIT spans (fornecidos por você):
#   1) 4..5
#   2) 10..11
#   3) 15..17
#   4) 22..23
#   5) 28
#   6) 35
# - O clip único (body_clip) está configurado no primeiro AttackConfig
#   com body_frames = 57 e body_fps > 0.
# - Deve haver 6 AttackConfig em special_sequence_primary (um por hit).
# ------------------------------------------------------------
func _prepare_special_combo_timings() -> void:
	assert(special_sequence_primary != null, "special_sequence_primary nulo")
	assert(special_sequence_primary.size() == 6, "Esperado 6 AttackConfig em special_sequence_primary para coincidir com 6 hits do clip.")

	var first_cfg: AttackConfig = special_sequence_primary[0]
	assert(first_cfg != null, "Primeiro AttackConfig do combo nulo")
	assert(first_cfg.body_fps > 0.0, "body_fps deve ser > 0 no primeiro AttackConfig do combo")
	assert(first_cfg.body_frames > 0, "body_frames deve ser > 0 no primeiro AttackConfig do combo")

	var total_frames: int = int(first_cfg.body_frames)        # esperado: 57
	var fps: float = first_cfg.body_fps

	# Definição dos frames de HIT por golpe (zero-based)
	var hit_spans: Array[PackedInt32Array] = [
		PackedInt32Array([4, 5]),
		PackedInt32Array([10, 11]),
		PackedInt32Array([15, 16, 17]),
		PackedInt32Array([22, 23]),
		PackedInt32Array([28]),
		PackedInt32Array([35]),
	]

	# Sanidade: garantir ordem crescente e dentro do range
	for i in hit_spans.size():
		var span: PackedInt32Array = hit_spans[i]
		assert(span.size() >= 1, "Span de HIT vazio no índice %d" % i)
		for f in span:
			assert(f >= 0 and f < total_frames, "Frame %d fora do range 0..%d (índice %d)" % [f, total_frames - 1, i])

	var last_end: int = -1
	for i in hit_spans.size():
		var cfg: AttackConfig = special_sequence_primary[i]
		assert(cfg != null, "AttackConfig nulo no índice %d" % i)

		var span: PackedInt32Array = hit_spans[i]
		var first_hit_frame: int = span[0]
		var last_hit_frame: int = span[span.size() - 1]

		# Startup: frames "vazios" entre o fim do último hit (ou -1) e o início deste
		var startup_frames: int = (first_hit_frame - (last_end + 1))
		if startup_frames < 0:
			startup_frames = 0

		# Hit: quantidade de frames ativos deste golpe
		var hit_frames: int = (last_hit_frame - first_hit_frame + 1)

		cfg.startup = float(startup_frames) / fps
		cfg.hit = float(hit_frames) / fps
		cfg.recovery = 0.0   # a não ser no último; ajustado abaixo

		last_end = last_hit_frame

	# Recovery só no último hit: do fim do último hit até o fim do clip
	var last_cfg: AttackConfig = special_sequence_primary[special_sequence_primary.size() - 1]
	var recovery_frames_last: int = (total_frames - 1 - last_end)
	if recovery_frames_last < 0:
		recovery_frames_last = 0
	last_cfg.recovery = float(recovery_frames_last) / fps
