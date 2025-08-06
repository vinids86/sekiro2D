extends CharacterBody2D
class_name Player

signal stamina_changed
signal health_changed

@onready var controller: CombatController = $CombatController
@onready var audio_player: AudioStreamPlayer2D = $AudioPlayer
@onready var attack_hitbox: Area2D = $AttackHitbox

@export var stamina_recovery_rate := 20.0  # unidades por segundo
@export var stamina_recovery_delay := 1.0  # segundos após ação para começar a recuperar
@export var max_stamina := 100.0
@onready var current_stamina := max_stamina
@export var max_health := 100.0
@onready var current_health := max_health
var stamina_recovery_timer := 0.0
var last_direction = "right"
var input_direction_buffer := Vector2.ZERO
@export var direction_buffer_duration := 0.2  # segundos
var direction_buffer_timer := 0.0

@export var speed := 200.0
@export var jump_force := -400.0
@export var gravity := 900.0

@onready var sprite := $AnimatedSprite2D
@onready var flash_material := sprite.material as ShaderMaterial

func _ready():
	controller.connect("play_sound", _on_play_sound)
	controller.connect("state_changed", _on_state_changed_with_dir)
	controller.setup(self)
	health_changed.emit()
	stamina_changed.emit()
	
func _physics_process(delta: float) -> void:
	if controller.combat_state != CombatController.CombatState.IDLE:
		velocity = Vector2.ZERO
		return

	var direction := Input.get_action_strength("move_right") - Input.get_action_strength("move_left")
	velocity.x = direction * speed

	# Aplicar gravidade
	if not is_on_floor():
		velocity.y += gravity * delta
	elif Input.is_action_just_pressed("move_up"):  # Pulo
		velocity.y = jump_force

	move_and_slide()

func update_animation(direction: float) -> void:
	if not is_on_floor():
		$AnimatedSprite2D.play("jump")
	elif direction != 0:
		$AnimatedSprite2D.play("walk")
	else:
		$AnimatedSprite2D.play("idle")

	if direction != 0:
		$AnimatedSprite2D.flip_h = direction < 0
	
func _process(delta: float):
	var dir := get_current_input_direction()
	if dir != Vector2.ZERO:
		input_direction_buffer = dir
		direction_buffer_timer = direction_buffer_duration
	else:
		direction_buffer_timer -= delta
		if direction_buffer_timer <= 0.0 and input_direction_buffer != Vector2.ZERO:
			input_direction_buffer = Vector2.ZERO

	if controller.combat_state == CombatController.CombatState.IDLE:
		update_animation(velocity.x)

	handle_input()

	if controller.can_act():
		if stamina_recovery_timer <= 0.0:
			current_stamina += stamina_recovery_rate * delta
			current_stamina = clamp(current_stamina, 0, max_stamina)
			stamina_changed.emit()
		else:
			stamina_recovery_timer -= delta

func _on_play_sound(path: String):
	audio_player.stream = load(path)
	audio_player.play()

func _on_state_changed_with_dir(old_state: int, new_state: int, attack_direction: Vector2):
	var anim := ""

	if attack_direction != Vector2.ZERO:
		last_direction = "right" if attack_direction.x >= 0 else "left"

	update_attack_hitbox_position(last_direction)

	match new_state:
		CombatController.CombatState.IDLE:
			anim = "idle"
			attack_hitbox.disable()

		CombatController.CombatState.STARTUP:
			anim = "startup_attack"
			attack_hitbox.disable()

		CombatController.CombatState.ATTACKING:
			anim = "attack"
			attack_hitbox.enable()

		CombatController.CombatState.RECOVERING:
			anim = "recoverring_attack"
			attack_hitbox.disable()

		CombatController.CombatState.PARRY_ACTIVE:
			anim = "parry"
			attack_hitbox.disable()

		CombatController.CombatState.PARRY_SUCCESS:
			anim = "parry_success"
			attack_hitbox.disable()

		CombatController.CombatState.GUARD_BROKEN:
			anim = "guard_broken"
			attack_hitbox.disable()

		CombatController.CombatState.STUNNED:
			anim = "stunned"
			attack_hitbox.disable()

	$AnimatedSprite2D.play(anim)
	# Garante que o personagem olhe na direção correta durante qualquer estado
	$AnimatedSprite2D.flip_h = last_direction == "left"

func get_current_input_direction() -> Vector2:
	return Vector2(
		Input.get_action_strength("move_right") - Input.get_action_strength("move_left"),
		0
	).normalized()

func get_label_from_vector(dir: Vector2) -> String:
	if dir == Vector2.ZERO:
		return last_direction
	return "right" if dir.x > 0 else "left"

func handle_input():
	var input_dir := get_current_input_direction()

	if input_dir != Vector2.ZERO and controller.combat_state == CombatController.CombatState.IDLE:
		last_direction = get_label_from_vector(input_dir)

	if Input.is_action_just_pressed("attack"):
		controller.try_attack(false, input_direction_buffer)
		controller.queued_direction = input_direction_buffer
	elif Input.is_action_just_pressed("parry"):
		controller.try_parry(false, input_dir)
		controller.queued_direction = input_dir

func die():
	_on_play_sound("res://audio/die.wav")
	queue_free()
	print("☠ ", self.name, " morreu.")

func on_parried():
	controller.on_parried()

func on_blocked():
	controller.on_blocked()

func get_combat_controller():
	return controller

func has_stamina(amount: float) -> bool:
	return current_stamina >= amount

func consume_stamina(amount: float):
	var previous = current_stamina
	current_stamina = clamp(current_stamina - amount, 0, max_stamina)
	stamina_changed.emit()
	if previous > current_stamina:
		stamina_recovery_timer = stamina_recovery_delay

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

func receive_attack(attacker: Node):
	var controller = get_combat_controller()
	var attacker_controller = attacker.get_combat_controller()

	# Se o parry já estiver ativo, rebate o ataque
	if controller.combat_state == CombatController.CombatState.PARRY_ACTIVE:
		print("⚡ Player executou parry com sucesso")
		controller.did_parry_succeed = true
		attacker.on_parried()
		return

	# Senão tenta bloquear
	if has_stamina(controller.block_stamina_cost):
		print("🛡️ Player bloqueou o ataque")
		_on_play_sound("res://audio/block.wav")
		controller.on_blocked()
		return

	# Caso contrário, sofre dano
	_on_play_sound("res://audio/hit.wav")
	print("💥 Player sofreu dano real")
	take_damage(20)

func take_damage(amount: float):
	current_health -= amount
	health_changed.emit()
	flash_hit_color()
	if current_health <= 0:
		die()

func flash_hit_color(duration := 0.1):
	flash_material.set("shader_parameter/flash", true)
	await get_tree().create_timer(duration).timeout
	flash_material.set("shader_parameter/flash", false)
