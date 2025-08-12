extends CharacterBody2D
class_name Player

signal stamina_changed
signal health_changed

@export var speed := 200.0
@export var max_health := 100.0
@export var max_stamina := 100.0
@export var stamina_recovery_rate := 20.0
@export var stamina_recovery_delay := 1.0
@export var direction_buffer_duration := 0.2
@export var exhausted_lock_duration := 0.35

@onready var controller: CombatController = $CombatController
@onready var audio_player: AudioStreamPlayer2D = $AudioPlayer
@onready var attack_hitbox: Area2D = $AttackHitbox
@onready var sprite := $AnimatedSprite2D
@onready var flash_material := sprite.material as ShaderMaterial

var current_health := max_health
var current_stamina := max_stamina
var stamina_recovery_timer := 0.0
var exhausted_lock_timer := 0.0

var last_direction := "right"
var input_direction_buffer := Vector2.ZERO
var direction_buffer_timer := 0.0
var stunned_block_toggle := false

var attack_sequence: Array[AttackConfig] = []
var _sfx_cache := {}

func _ready() -> void:
	attack_sequence = AttackConfig.default_sequence()
	controller.setup(self)
	controller.connect("play_sound", _on_play_sound)
	controller.connect("state_changed", _on_state_changed_with_dir)
	health_changed.emit()
	stamina_changed.emit()
	_on_state_changed_with_dir(controller.combat_state, controller.combat_state, Vector2(1, 0))

func _physics_process(delta: float) -> void:
	var can_move := controller.combat_state == CombatController.CombatState.IDLE
	var direction := Input.get_action_strength("move_right") - Input.get_action_strength("move_left")
	velocity.x = (direction * speed) if can_move else 0.0
	velocity.y = 0.0
	move_and_slide()
	if can_move:
		var moving: bool = absf(velocity.x) > 0.1
		var base := "walk" if moving else "idle"
		var suffix := "_exhausted" if is_exhausted() else ""
		var target := base + suffix
		if sprite.animation != target:
			sprite.play(target)
	sprite.flip_h = last_direction == "left"

func _process(delta: float) -> void:
	var dir := get_current_input_direction()
	if dir != Vector2.ZERO:
		input_direction_buffer = dir
		direction_buffer_timer = direction_buffer_duration
	else:
		direction_buffer_timer -= delta
		if direction_buffer_timer <= 0.0 and input_direction_buffer != Vector2.ZERO:
			input_direction_buffer = Vector2.ZERO
	handle_input()
	if controller.can_act():
		if stamina_recovery_timer <= 0.0:
			current_stamina += stamina_recovery_rate * delta
			current_stamina = clamp(current_stamina, 0, max_stamina)
			stamina_changed.emit()
		else:
			stamina_recovery_timer -= delta
	if exhausted_lock_timer > 0.0:
		exhausted_lock_timer -= delta

func _on_play_sound(path: String) -> void:
	if not _sfx_cache.has(path):
		_sfx_cache[path] = load(path)
	audio_player.stream = _sfx_cache[path]
	audio_player.play()

func _on_state_changed_with_dir(old_state: int, new_state: int, attack_direction: Vector2) -> void:
	var anim := ""
	if attack_direction != Vector2.ZERO:
		last_direction = "right" if attack_direction.x >= 0 else "left"
	update_attack_hitbox_position(last_direction)
	var attack = null
	if not controller.owner_node.attack_sequence.is_empty():
		attack = controller.owner_node.attack_sequence[controller.combo_index]
	if new_state == CombatController.CombatState.IDLE:
		attack_hitbox.disable()
		anim = "idle_exhausted" if is_exhausted() else "idle"
	elif new_state == CombatController.CombatState.STARTUP:
		if attack:
			anim = attack.startup_animation
		attack_hitbox.disable()
	elif new_state == CombatController.CombatState.ATTACKING:
		if attack:
			anim = attack.attack_animation
		attack_hitbox.enable()
	elif new_state == CombatController.CombatState.RECOVERING:
		if attack:
			anim = attack.recovery_animation
		attack_hitbox.disable()
	elif new_state == CombatController.CombatState.PARRY_ACTIVE:
		anim = "parry"
		attack_hitbox.disable()
	elif new_state == CombatController.CombatState.PARRY_SUCCESS:
		anim = "parry_success"
		attack_hitbox.disable()
	elif new_state == CombatController.CombatState.STUNNED:
		if controller.stun_kind == CombatController.StunKind.PARRIED:
			anim = "stunned_parry"
			controller.stun_kind = CombatController.StunKind.NONE
		else:
			anim = "stunned_block_b" if stunned_block_toggle else "stunned_block_a"
			stunned_block_toggle = not stunned_block_toggle
	if anim != "" and sprite.animation != anim:
		sprite.play(anim)
	sprite.flip_h = last_direction == "left"

func get_current_input_direction() -> Vector2:
	return Vector2(
		Input.get_action_strength("move_right") - Input.get_action_strength("move_left"),
		0
	).normalized()

func get_label_from_vector(dir: Vector2) -> String:
	if dir == Vector2.ZERO:
		return last_direction
	return "right" if dir.x > 0 else "left"

func handle_input() -> void:
	var input_dir := get_current_input_direction()
	if input_dir != Vector2.ZERO and controller.combat_state == CombatController.CombatState.IDLE:
		last_direction = get_label_from_vector(input_dir)
	if Input.is_action_just_pressed("attack"):
		var started := controller.try_attack(false, input_direction_buffer)
		if not started:
			controller.queued_direction = input_direction_buffer
	elif Input.is_action_just_pressed("parry"):
		var started := controller.try_parry(false, input_dir)
		if not started:
			controller.queued_direction = input_dir

func die() -> void:
	_on_play_sound("res://audio/die.wav")
	queue_free()

func on_parried() -> void:
	controller.on_parried()

func on_blocked() -> void:
	controller.on_blocked()

func get_combat_controller() -> CombatController:
	return controller

func has_stamina(amount: float) -> bool:
	return current_stamina >= amount

func consume_stamina(amount: float) -> void:
	var previous = current_stamina
	current_stamina = clamp(current_stamina - amount, 0, max_stamina)
	stamina_changed.emit()
	if previous > current_stamina:
		stamina_recovery_timer = stamina_recovery_delay
	if previous >= controller.block_stamina_cost and current_stamina < controller.block_stamina_cost:
		exhausted_lock_timer = exhausted_lock_duration

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

func receive_attack(attacker: Node) -> void:
	var controller := get_combat_controller()
	if controller.combat_state == CombatController.CombatState.PARRY_ACTIVE:
		controller.did_parry_succeed = true
		attacker.on_parried()
		return
	if has_stamina(controller.block_stamina_cost):
		_on_play_sound("res://audio/block.wav")
		controller.on_blocked()
		return
	_on_play_sound("res://audio/hit.wav")
	take_damage(20)

func take_damage(amount: float) -> void:
	current_health -= amount
	health_changed.emit()
	flash_hit_color()
	if current_health <= 0:
		die()

func flash_hit_color(duration := 0.1) -> void:
	flash_material.set("shader_parameter/flash", true)
	await get_tree().create_timer(duration).timeout
	flash_material.set("shader_parameter/flash", false)

func is_exhausted() -> bool:
	if exhausted_lock_timer > 0.0:
		return true
	return current_stamina < controller.block_stamina_cost
