extends CharacterBody2D
class_name Enemy

signal stamina_changed
signal health_changed

@export var speed: float = 100.0
@export var exhausted_lock_duration: float = 0.35
@export var sfx_block: AudioStream
@export var sfx_hit: AudioStream
@export var sfx_die: AudioStream

# Ataques configuráveis p/ o Brain
@export var heavy_attack: AttackConfig
@export var finisher_attack: AttackConfig
@export var finisher_max_distance: float = 120.0
@export var finisher_require_facing: bool = true

@onready var controller: CombatController = $CombatController
@onready var attack_hitbox: Area2D = $AttackHitbox
@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var flash_material: ShaderMaterial = sprite.material as ShaderMaterial

# Componentes
@onready var stats: Stats = $Stats
@onready var anim: AnimationDriver = $AnimationDriver
@onready var audio_out: AudioOutlet = $AudioOutlet
@onready var stepper: AttackStepper = $AttackStepper
@onready var brain: EnemyBrain = $EnemyBrain
@onready var clamp2d: ScreenClamp = $ScreenClamp

var last_direction: String = "left"
var stunned_block_toggle: bool = false

var attack_sequence: Array[AttackConfig] = []
var exhausted_lock_timer: float = 0.0

# Guarda último agressor p/ afastamento no parry pesado
var _last_attacker_node: Node2D = null

func _ready() -> void:
	assert(controller != null, "Enemy.controller não encontrado")
	assert(audio_out != null, "Enemy.audio_out não encontrado")
	assert(sfx_block != null, "Enemy.sfx_block não configurado")
	assert(sfx_hit != null, "Enemy.sfx_hit não configurado")

	attack_sequence = AttackConfig.default_sequence()

	if heavy_attack == null:
		heavy_attack = AttackConfig.heavy_preset()
	if finisher_attack == null:
		finisher_attack = AttackConfig.finisher_preset()

	var p: Node = get_tree().get_first_node_in_group("player")
	if p != null:
		brain.set_player(p)

	controller.setup(self, {
		"get_attack_sequence": func() -> Array: return attack_sequence,
		"has_stamina": func(cost: float) -> bool: return stats.has_stamina(cost),
		"consume_stamina": func(cost: float) -> void: stats.consume_stamina(cost),
		"apply_attack_effects": func(cfg: AttackConfig) -> void: _apply_attack_effects(cfg),
		"play_block_sfx": func() -> void: audio_out.play_stream(sfx_block),
	})

	brain.bind_controller(controller)

	controller.play_stream.connect(func(s: AudioStream) -> void: audio_out.play_stream(s))
	controller.state_changed.connect(_on_state_changed_with_dir)
	controller.hitbox_active_changed.connect(_on_hitbox_active_changed)

	controller.attack_step.connect(func(dist: float) -> void:
		stepper.start_step(dist, last_direction == "left")
	)

	controller.request_push_apart.connect(_on_request_push_apart)

	stats.health_changed.connect(func(_c: float, _m: float) -> void: health_changed.emit())
	stats.stamina_changed.connect(func(_c: float, _m: float) -> void: stamina_changed.emit())

	_on_state_changed_with_dir(controller.combat_state, Vector2(-1, 0))

func _physics_process(delta: float) -> void:
	if controller.combat_state == CombatTypes.CombatState.IDLE:
		stats.tick(delta)

	stepper.physics_tick(delta)

	if controller.combat_state != CombatTypes.CombatState.IDLE and not _is_step_active():
		velocity.x = 0.0

	velocity.y = 0.0
	move_and_slide()
	clamp2d.physics_tick()

func _process(delta: float) -> void:
	if exhausted_lock_timer > 0.0:
		exhausted_lock_timer -= delta

	if controller.combat_state == CombatTypes.CombatState.IDLE:
		anim.set_exhausted(is_exhausted())
		anim.play_state_anim("idle")

func _on_state_changed_with_dir(new_state: int, attack_direction: Vector2) -> void:
	if attack_direction != Vector2.ZERO:
		var is_dodge: bool = (
			new_state == CombatTypes.CombatState.DODGE_STARTUP
			or new_state == CombatTypes.CombatState.DODGE_ACTIVE
			or new_state == CombatTypes.CombatState.DODGE_RECOVERING
		)
		if not is_dodge:
			last_direction = get_label_from_vector(attack_direction)

	update_attack_hitbox_position(last_direction)

	var attack: AttackConfig = controller.get_current_attack() as AttackConfig
	anim.set_direction_label(last_direction)
	anim.set_exhausted(is_exhausted())

	match new_state:
		CombatTypes.CombatState.IDLE:
			anim.play_state_anim("idle")
			attack_hitbox.disable()

		CombatTypes.CombatState.STARTUP:
			if attack != null:
				anim.play_exact(attack.startup_animation)
			attack_hitbox.disable()

		CombatTypes.CombatState.ATTACKING:
			if attack != null:
				anim.play_exact(attack.attack_animation)
			attack_hitbox.enable()

		CombatTypes.CombatState.RECOVERING_SOFT:
			if attack != null:
				anim.play_exact(attack.recovery_animation)
			attack_hitbox.disable()

		CombatTypes.CombatState.PARRY_ACTIVE:
			anim.play_exact("parry")
			attack_hitbox.disable()

		CombatTypes.CombatState.PARRY_SUCCESS:
			anim.play_exact("parry_success")
			attack_hitbox.disable()

		CombatTypes.CombatState.LOCKOUT:
			anim.play_state_anim("idle")
			attack_hitbox.disable()

		CombatTypes.CombatState.STUNNED:
			var anim_name: String = ""
			match controller.stun_kind:
				CombatTypes.StunKind.PARRIED:
					anim_name = "stunned_parry"
				CombatTypes.StunKind.BLOCKED:
					if stunned_block_toggle:
						anim_name = "stunned_block_b"
					else:
						anim_name = "stunned_block_a"
					stunned_block_toggle = not stunned_block_toggle
				CombatTypes.StunKind.NONE:
					anim_name = "stunned_hit"
			controller.stun_kind = CombatTypes.StunKind.NONE
			anim.play_exact(anim_name)

		CombatTypes.CombatState.DODGE_STARTUP:
			anim.play_exact("dodge_startup")
			attack_hitbox.disable()

		CombatTypes.CombatState.DODGE_ACTIVE:
			anim.play_exact("dodge")
			attack_hitbox.disable()

		CombatTypes.CombatState.DODGE_RECOVERING:
			anim.play_exact("dodge_recover")
			attack_hitbox.disable()

		CombatTypes.CombatState.GUARD_BROKEN:
			anim.play_exact("guard_broken")

	anim.set_direction_label(last_direction)

func get_label_from_vector(dir: Vector2) -> String:
	if dir == Vector2.ZERO:
		return last_direction
	if dir.x >= 0.0:
		return "right"
	return "left"

func update_attack_hitbox_position(direction: String) -> void:
	var offset: Vector2 = Vector2.ZERO
	match direction:
		"left":
			offset = Vector2(-45, 0)
			attack_hitbox.rotation_degrees = 180
		"right":
			offset = Vector2(45, 0)
			attack_hitbox.rotation_degrees = 0
	attack_hitbox.position = offset

func _on_hitbox_active_changed(on: bool) -> void:
	if on:
		attack_hitbox.enable()
	else:
		attack_hitbox.disable()

func _is_step_active() -> bool:
	return controller.combat_state == CombatTypes.CombatState.ATTACKING

# ======= Interface esperada pelo CombatController =======
func get_combat_controller() -> CombatController:
	return controller

func has_stamina(amount: float) -> bool:
	return stats.has_stamina(amount)

func consume_stamina(amount: float) -> void:
	var before: float = stats.current_stamina
	stats.consume_stamina(amount)
	if before >= controller.block_stamina_cost and stats.current_stamina < controller.block_stamina_cost:
		exhausted_lock_timer = exhausted_lock_duration

func is_exhausted() -> bool:
	if exhausted_lock_timer > 0.0:
		return true
	return stats.is_exhausted(controller.block_stamina_cost)

# ============================ COMBATE: RECEBER ATAQUE ============================
func receive_attack(attacker: Node) -> void:
	_last_attacker_node = attacker as Node2D
	controller.process_incoming_hit(attacker)

# ============================ Utilidades ============================
func take_damage(amount: float) -> void:
	stats.take_damage(amount)
	flash_hit_color()
	if stats.current_health <= 0.0:
		die()

func die() -> void:
	audio_out.play_stream(sfx_die)
	queue_free()

func on_parried() -> void:
	controller.on_parried()

func on_blocked() -> void:
	controller.on_blocked()

func _delayed_attack(attack_vector: Vector2) -> void:
	await get_tree().process_frame
	controller.try_attack(false, attack_vector)

func flash_hit_color(duration: float = 0.1) -> void:
	if flash_material:
		flash_material.set("shader_parameter/flash", true)
		await get_tree().create_timer(duration).timeout
		flash_material.set("shader_parameter/flash", false)

# Afastamento simples após parry pesado (neutro)
func _on_request_push_apart(pixels: float) -> void:
	if _last_attacker_node == null or not is_instance_valid(_last_attacker_node):
		return
	var a: Vector2 = _last_attacker_node.global_position
	var b: Vector2 = global_position
	var dir: Vector2 = (b - a).normalized()
	if dir == Vector2.ZERO:
		dir = Vector2.RIGHT
	_last_attacker_node.global_position -= dir * pixels
	global_position += dir * pixels

func _apply_attack_effects(cfg: AttackConfig) -> void:
	var c: CombatController = get_combat_controller()
	var stamina_before: float = stats.current_stamina

	if cfg.stamina_damage_extra > 0.0:
		stats.consume_stamina(cfg.stamina_damage_extra)
		stamina_changed.emit()

	if stats.current_stamina > 0.0:
		stats.consume_stamina(cfg.damage)
		stamina_changed.emit()
	else:
		stats.take_damage(cfg.damage)
		flash_hit_color()
		health_changed.emit()
		if stats.current_health <= 0.0:
			die()

	audio_out.play_stream(sfx_hit)

	if cfg.kind == AttackConfig.AttackKind.HEAVY and stamina_before > 0.0 and stats.current_stamina <= 0.0:
		c.force_guard_broken()
