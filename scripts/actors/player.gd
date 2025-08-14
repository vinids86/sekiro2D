extends CharacterBody2D
class_name Player

signal stamina_changed
signal health_changed

@export var speed := 200.0
@export var direction_buffer_duration := 0.2
@export var exhausted_lock_duration := 0.35
@export var attack_step_duration := 0.06
@export var sfx_block: AudioStream
@export var sfx_hit: AudioStream
@export var sfx_die: AudioStream

@onready var controller: CombatController = $CombatController
@onready var audio_player: AudioStreamPlayer2D = $AudioPlayer
@onready var attack_hitbox: Area2D = $AttackHitbox
@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var flash_material: ShaderMaterial = sprite.material as ShaderMaterial

# Componentes
@onready var stats: Stats = $Stats
@onready var anim: AnimationDriver = $AnimationDriver
@onready var audio_out: AudioOutlet = $AudioOutlet
@onready var stepper: AttackStepper = $AttackStepper

var last_direction := "right"
var input_direction_buffer := Vector2.ZERO
var direction_buffer_timer := 0.0
var stunned_block_toggle := false

var attack_sequence: Array[AttackConfig] = []

# Timers auxiliares
var exhausted_lock_timer := 0.0

func _ready() -> void:
	# sequência default (você pode trocar depois por resource no editor)
	attack_sequence = AttackConfig.default_sequence()

	# Interface para desacoplar o controller
	controller.setup(self, {
		"get_attack_sequence": func() -> Array: return attack_sequence,
		"has_stamina": func(cost: float) -> bool: return stats.has_stamina(cost),
		"consume_stamina": func(cost: float) -> void: stats.consume_stamina(cost)
	})

	# sinais do controller
	controller.play_stream.connect(func(s: AudioStream): audio_out.play_stream(s))
	controller.connect("state_changed", _on_state_changed_with_dir)
	controller.hitbox_active_changed.connect(_on_hitbox_active_changed)
	controller.attack_step.connect(func(dist): stepper.start_step(dist, last_direction == "left"))

	# sinais dos stats → propagar para HUD externa se estiver conectada a Player
	stats.health_changed.connect(func(_c,_m): health_changed.emit())
	stats.stamina_changed.connect(func(_c,_m): stamina_changed.emit())

	# garantir pose inicial coerente
	_on_state_changed_with_dir(controller.combat_state, controller.combat_state, Vector2(1, 0))

func _physics_process(delta: float) -> void:
	# recuperação de stamina via componente
	stats.tick(delta)

	# aplica "step" do ataque (empurrão curto) via componente
	stepper.physics_tick(delta)

	# movimento livre só quando IDLE
	var can_move := controller.combat_state == CombatController.CombatState.IDLE
	var input_dir := Input.get_action_strength("move_right") - Input.get_action_strength("move_left")

	if can_move:
		velocity.x = input_dir * speed
	else:
		# se não estiver em step ativo, congela
		if not _is_step_active():
			velocity.x = 0.0

	velocity.y = 0.0
	move_and_slide()

	# animação livre (idle/walk) só no IDLE; demais estados o AnimationDriver decide
	if can_move:
		var moving := absf(velocity.x) > 0.1
		var base := "walk" if moving else "idle"
		anim.set_exhausted(is_exhausted())
		anim.play_state_anim(base)

	# flip é centralizado no AnimationDriver
	anim.set_direction_label(last_direction)

func _process(delta: float) -> void:
	# buffer de direção (igual seu código antigo)
	var dir := get_current_input_direction()
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

	handle_input()

func handle_input() -> void:
	var input_dir := get_current_input_direction()

	# atualizar facing quando puder andar
	if input_dir != Vector2.ZERO and controller.combat_state == CombatController.CombatState.IDLE:
		last_direction = get_label_from_vector(input_dir)

	if Input.is_action_just_pressed("attack"):
		var started := controller.try_attack(false, input_direction_buffer)
		if not started:
			controller.queued_direction = input_direction_buffer

	if Input.is_action_just_pressed("parry"):
		var started := controller.try_parry(false, input_dir)
		if not started:
			controller.queued_direction = input_dir

func get_current_input_direction() -> Vector2:
	return Vector2(
		Input.get_action_strength("move_right") - Input.get_action_strength("move_left"),
		0.0
	).normalized()

func get_label_from_vector(dir: Vector2) -> String:
	if dir == Vector2.ZERO:
		return last_direction
	return "right" if dir.x > 0.0 else "left"

func update_attack_hitbox_position(direction: String) -> void:
	var offset := Vector2.ZERO
	match direction:
		"left":
			offset = Vector2(-45, 0)
			attack_hitbox.rotation_degrees = 180
		"right":
			offset = Vector2(45, 0)
			attack_hitbox.rotation_degrees = 0
	attack_hitbox.position = offset

func _on_state_changed_with_dir(old_state: int, new_state: int, attack_direction: Vector2) -> void:
	# direção de ataque define o facing se houver
	if attack_direction != Vector2.ZERO:
		last_direction = "right" if attack_direction.x >= 0.0 else "left"

	# manter hitbox na frente
	update_attack_hitbox_position(last_direction)

	# animações por estado via AnimationDriver
	var attack = controller.get_current_attack()
	anim.set_direction_label(last_direction)
	anim.set_exhausted(is_exhausted())

	match new_state:
		CombatController.CombatState.IDLE:
			anim.play_state_anim("idle")
		CombatController.CombatState.STARTUP:
			if attack: anim.play_exact(attack.startup_animation)
		CombatController.CombatState.ATTACKING:
			if attack: anim.play_exact(attack.attack_animation)
		CombatController.CombatState.RECOVERING:
			if attack: anim.play_exact(attack.recovery_animation)
		CombatController.CombatState.PARRY_ACTIVE:
			anim.play_exact("parry")
		CombatController.CombatState.PARRY_SUCCESS:
			anim.play_exact("parry_success")
		CombatController.CombatState.STUNNED:
			var a := ("stunned_parry" if controller.stun_kind == CombatController.StunKind.PARRIED
				else ("stunned_block_b" if stunned_block_toggle else "stunned_block_a"))
			stunned_block_toggle = not stunned_block_toggle
			controller.stun_kind = CombatController.StunKind.NONE
			anim.play_exact(a)

func _on_hitbox_active_changed(on: bool) -> void:
	if on: attack_hitbox.enable()
	else: attack_hitbox.disable()

func _is_step_active() -> bool:
	# AttackStepper cuida do velocity.x durante o step;
	# aqui só checamos se o controller está em ATTACKING e o stepper com timer > 0.
	return controller.combat_state == CombatController.CombatState.ATTACKING

# ======= Interface esperada pelo CombatController (seus nomes mantidos) =======

func get_combat_controller() -> CombatController:
	return controller

func has_stamina(amount: float) -> bool:
	return stats.has_stamina(amount)

func consume_stamina(amount: float) -> void:
	var before := stats.current_stamina
	stats.consume_stamina(amount)
	# opcional: trave ações por um curto período ao cruzar o threshold
	if before >= controller.block_stamina_cost and stats.current_stamina < controller.block_stamina_cost:
		exhausted_lock_timer = exhausted_lock_duration

func is_exhausted() -> bool:
	if exhausted_lock_timer > 0.0:
		return true
	return stats.is_exhausted(controller.block_stamina_cost)

func receive_attack(attacker: Node) -> void:
	var c := get_combat_controller()
	if c.combat_state == CombatController.CombatState.PARRY_ACTIVE:
		c.did_parry_succeed = true
		if attacker and attacker.has_method("on_parried"):
			attacker.on_parried()
		return
	if has_stamina(c.block_stamina_cost):
		audio_out.play_stream(sfx_block)
		c.on_blocked()
		return
	audio_out.play_stream(sfx_hit)
	take_damage(20)

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

func _on_cc_play_stream(stream: AudioStream) -> void:
	audio_out.play_stream(stream)

func flash_hit_color(duration := 0.1) -> void:
	if flash_material:
		flash_material.set("shader_parameter/flash", true)
		await get_tree().create_timer(duration).timeout
		flash_material.set("shader_parameter/flash", false)
