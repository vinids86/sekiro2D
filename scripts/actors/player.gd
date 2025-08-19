extends CharacterBody2D
class_name Player

signal stamina_changed
signal health_changed
signal special_changed

@export var speed: float = 200.0
@export var direction_buffer_duration: float = 0.2
@export var exhausted_lock_duration: float = 0.35
@export var sfx_block: AudioStream
@export var sfx_hit: AudioStream
@export var sfx_die: AudioStream

# HEAVY via hold
@export var heavy_attack: AttackConfig
@export var heavy_hold_threshold: float = 0.33

# FINISHER
@export var finisher_attack: AttackConfig
@export var finisher_max_distance: float = 120.0
@export var finisher_require_facing: bool = true

@export var special_sequence_primary: Array[AttackConfig] = []

@onready var controller: CombatController = $CombatController
@onready var attack_hitbox: Area2D = $AttackHitbox
@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var flash_material: ShaderMaterial = sprite.material as ShaderMaterial

# Componentes
@onready var stats: Stats = $Stats
@onready var anim: AnimationDriver = $AnimationDriver
@onready var audio_out: AudioOutlet = $AudioOutlet
@onready var stepper: AttackStepper = $AttackStepper
@onready var clamp2d: ScreenClamp = $ScreenClamp

# >>> AttackAnimator <<<
@onready var attack_animator: AttackAnimator = $AttackAnimator

var last_direction: String = "right"
var input_direction_buffer: Vector2 = Vector2.ZERO
var direction_buffer_timer: float = 0.0
var stunned_block_toggle: bool = false

var attack_sequence: Array[AttackConfig] = []

# Timers auxiliares
var exhausted_lock_timer: float = 0.0

# Guarda o último agressor
var _last_attacker_node: Node2D = null

# --- Estado do hold para HEAVY ---
var _attack_hold_active: bool = false
var _attack_hold_timer: float = 0.0
var _attack_hold_dir: Vector2 = Vector2.ZERO
var _heavy_sent: bool = false

func _ready() -> void:
	assert(controller != null, "Player.controller não encontrado")
	assert(audio_out != null, "Player.audio_out não encontrado")
	assert(sfx_block != null, "Player.sfx_block não configurado")
	assert(sfx_hit != null, "Player.sfx_hit não configurado")
	assert(attack_animator != null, "Player.attack_animator não encontrado")

	# Garante ligação do sprite no AttackAnimator caso não tenha sido setado no inspector
	if attack_animator.sprite == null:
		attack_animator.sprite = sprite

	attack_sequence = AttackConfig.default_sequence()

	controller.setup(self, {
		"get_attack_sequence": func() -> Array: return attack_sequence,
		"has_stamina": func(cost: float) -> bool: return stats.has_stamina(cost),
		"consume_stamina": func(cost: float) -> void: stats.consume_stamina(cost),
		"apply_attack_effects": func(cfg: AttackConfig) -> void: _apply_attack_effects(cfg),
		"play_block_sfx": func() -> void: audio_out.play_stream(sfx_block),
	})

	controller.play_stream.connect(func(s: AudioStream) -> void: audio_out.play_stream(s))
	controller.state_changed.connect(_on_state_changed_with_dir)

	# Mantemos o controle de hitbox pelo CombatController
	controller.hitbox_active_changed.connect(_on_hitbox_active_changed)

	controller.attack_step.connect(func(dist: float) -> void:
		stepper.start_step(dist, last_direction == "left")
	)

	controller.request_push_apart.connect(_on_request_push_apart)

	stats.health_changed.connect(func(_c: float,_m: float) -> void: health_changed.emit())
	stats.stamina_changed.connect(func(_c: float,_m: float) -> void: stamina_changed.emit())
	stats.special_changed.connect(func(_c: float,_m: float) -> void: special_changed.emit())

	if heavy_attack == null:
		heavy_attack = AttackConfig.heavy_preset()
	if finisher_attack == null:
		finisher_attack = AttackConfig.finisher_preset()
	if special_sequence_primary.is_empty():
		special_sequence_primary = AttackConfig.special_sequence()

	_on_state_changed_with_dir(controller.combat_state, Vector2(1, 0))

func _physics_process(delta: float) -> void:
	if controller.combat_state == CombatTypes.CombatState.IDLE:
		stats.tick(delta)

	stepper.physics_tick(delta)

	var can_move: bool = controller.combat_state == CombatTypes.CombatState.IDLE
	var input_dir_val: float = Input.get_action_strength("move_right") - Input.get_action_strength("move_left")

	if can_move:
		velocity.x = input_dir_val * speed
	else:
		if not _is_step_active():
			velocity.x = 0.0

	velocity.y = 0.0
	move_and_slide()
	clamp2d.physics_tick()

	if can_move:
		var moving: bool = absf(velocity.x) > 0.1
		var base: String = "idle"
		if moving:
			base = "walk"
		anim.set_exhausted(is_exhausted())
		anim.play_state_anim(base)

	anim.set_direction_label(last_direction)

func _process(delta: float) -> void:
	# buffer de direção
	var dir: Vector2 = get_current_input_direction()
	if dir != Vector2.ZERO:
		input_direction_buffer = dir
		direction_buffer_timer = direction_buffer_duration
	else:
		direction_buffer_timer -= delta
		if direction_buffer_timer <= 0.0 and input_direction_buffer != Vector2.ZERO:
			input_direction_buffer = Vector2.ZERO

	# timers auxiliares
	if exhausted_lock_timer > 0.0:
		exhausted_lock_timer -= delta

	_handle_special_input()
	_update_attack_hold(delta)
	handle_input_parry_and_dodge()

func handle_input_parry_and_dodge() -> void:
	var input_dir: Vector2 = get_current_input_direction()

	# atualizar facing quando puder andar
	if input_dir != Vector2.ZERO and controller.combat_state == CombatTypes.CombatState.IDLE:
		last_direction = get_label_from_vector(input_dir)

	# parry
	if Input.is_action_just_pressed("parry"):
		controller.try_parry(false, input_dir)

	# dodge
	if Input.is_action_just_pressed("dodge"):
		var dodge_dir: Vector2 = input_dir
		if dodge_dir == Vector2.ZERO:
			if last_direction == "right":
				dodge_dir = Vector2(-1, 0)
			else:
				dodge_dir = Vector2(1, 0)
		controller.try_dodge(false, dodge_dir)

func _update_attack_hold(delta: float) -> void:
	if Input.is_action_just_pressed("attack"):
		if Input.is_action_pressed("special_modifier"):
			return
		if _try_finisher_input():
			return

		_attack_hold_active = true
		_attack_hold_timer = 0.0
		_heavy_sent = false

		var dir: Vector2 = input_direction_buffer
		if dir == Vector2.ZERO:
			dir = get_current_input_direction()
		if dir == Vector2.ZERO:
			if last_direction == "right":
				dir = Vector2(1, 0)
			else:
				dir = Vector2(-1, 0)
		_attack_hold_dir = dir

	if _attack_hold_active and Input.is_action_pressed("attack"):
		_attack_hold_timer += delta
		if not _heavy_sent and _attack_hold_timer >= heavy_hold_threshold:
			_heavy_sent = true
			_attack_hold_active = false
			if heavy_attack != null and controller.has_method("try_attack_heavy"):
				controller.try_attack_heavy(heavy_attack, _attack_hold_dir)
			else:
				controller.try_attack(false, _attack_hold_dir)
		return

	if _attack_hold_active and Input.is_action_just_released("attack"):
		_attack_hold_active = false
		if not _heavy_sent:
			controller.try_attack(false, _attack_hold_dir)

func _find_guard_broken_target() -> Dictionary:
	var me: Node2D = self as Node2D
	var best_node: Node2D = null
	var best_dist: float = INF
	var dir_label: String = last_direction
	for n in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(n):
			continue
		var e: Node2D = n as Node2D
		if e == null:
			continue
		if not e.has_method("get_combat_controller"):
			continue
		var ecc: CombatController = e.get_combat_controller()
		if ecc == null or not ecc.is_guard_broken():
			continue

		var dx: float = e.global_position.x - me.global_position.x
		var dist: float = absf(dx)
		if dist > finisher_max_distance:
			continue

		if finisher_require_facing:
			if dir_label == "right" and dx < 0.0:
				continue
			if dir_label == "left" and dx > 0.0:
				continue

		if dist < best_dist:
			best_dist = dist
			best_node = e

	if best_node != null:
		var vec: Vector2 = (best_node.global_position - me.global_position).normalized()
		return {"node": best_node, "dir": vec}
	return {}

func _try_finisher_input() -> bool:
	if finisher_attack == null or not controller.has_method("try_attack_heavy"):
		return false
	var target: Dictionary = _find_guard_broken_target()
	if target.is_empty():
		return false
	var dir: Vector2 = target["dir"]
	controller.try_attack_heavy(finisher_attack, dir)
	return true

func get_current_input_direction() -> Vector2:
	return Vector2(
		Input.get_action_strength("move_right") - Input.get_action_strength("move_left"),
		0.0
	).normalized()

func get_label_from_vector(dir: Vector2) -> String:
	if dir == Vector2.ZERO:
		return last_direction
	if dir.x > 0.0:
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

func _on_state_changed_with_dir(new_state: int, attack_direction: Vector2) -> void:
	if should_update_facing(new_state, attack_direction):
		if attack_direction.x >= 0.0:
			last_direction = "right"
		else:
			last_direction = "left"

	update_attack_hitbox_position(last_direction)

	var attack: AttackConfig = controller.get_current_attack() as AttackConfig
	anim.set_direction_label(last_direction)
	anim.set_exhausted(is_exhausted())

	match new_state:
		CombatTypes.CombatState.IDLE:
			_stop_attack_animator()
			anim.play_state_anim("idle")

		CombatTypes.CombatState.STARTUP:
			# Agora o AttackAnimator cuida do visual do ataque
			if attack != null:
				var anims: AttackPhaseAnims = _make_phase_anims_from_attack(attack)
				attack_animator.play_attack(anims, attack.startup, attack.active_duration, attack.recovery_hard)

		CombatTypes.CombatState.ATTACKING:
			# Nada aqui: o AttackAnimator já está tocando a fase ACTIVE
			pass

		CombatTypes.CombatState.RECOVERING_SOFT:
			# Nada aqui: o AttackAnimator já cobre a RECOVERY (tempo e frames)
			pass

		CombatTypes.CombatState.PARRY_ACTIVE:
			_stop_attack_animator()
			anim.play_exact("parry")

		CombatTypes.CombatState.PARRY_SUCCESS:
			_stop_attack_animator()
			anim.play_exact("parry_success")
			attack_hitbox.disable()

		CombatTypes.CombatState.LOCKOUT:
			_stop_attack_animator()
			anim.play_state_anim("idle")
			attack_hitbox.disable()

		CombatTypes.CombatState.STUNNED:
			_stop_attack_animator()
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
			_stop_attack_animator()
			anim.play_exact("dodge_startup")

		CombatTypes.CombatState.DODGE_ACTIVE:
			_stop_attack_animator()
			anim.play_exact("dodge")

		CombatTypes.CombatState.DODGE_RECOVERING:
			_stop_attack_animator()
			anim.play_exact("dodge_recover")

		CombatTypes.CombatState.GUARD_BROKEN:
			_stop_attack_animator()
			anim.play_exact("guard_broken")

func _stop_attack_animator() -> void:
	if attack_animator != null:
		attack_animator.set_process(false)
	if sprite != null:
		# o animator tinha setado 0.0; precisamos soltar o freio
		sprite.speed_scale = 1.0

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
		controller.force_guard_broken()

func should_update_facing(new_state: int, attack_direction: Vector2) -> bool:
	var has_direction: bool = attack_direction != Vector2.ZERO
	var is_dodge_state: bool = (
		new_state == CombatTypes.CombatState.DODGE_STARTUP
		or new_state == CombatTypes.CombatState.DODGE_ACTIVE
		or new_state == CombatTypes.CombatState.DODGE_RECOVERING
	)
	return has_direction and not is_dodge_state

func _handle_special_input() -> void:
	if Input.is_action_just_pressed("special_attack_1"):
		if special_sequence_primary.is_empty():
			push_warning("special_sequence_primary vazio")
			return

		var dir: Vector2 = input_direction_buffer
		if dir == Vector2.ZERO:
			dir = get_current_input_direction()
		if dir == Vector2.ZERO:
			if last_direction == "right":
				dir = Vector2(1, 0)
			else:
				dir = Vector2(-1, 0)

		controller.start_forced_sequence(special_sequence_primary.duplicate(), dir)

# ---------- Helpers de animação ----------
func _make_phase_anims_from_attack(attack: AttackConfig) -> AttackPhaseAnims:
	var res: AttackPhaseAnims = AttackPhaseAnims.new()
	# Usa os nomes já definidos no AttackConfig
	res.startup_anim = StringName(attack.startup_animation)
	res.active_anim = StringName(attack.attack_animation)
	res.recovery_anim = StringName(attack.recovery_animation)
	return res
