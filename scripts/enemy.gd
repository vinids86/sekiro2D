extends CharacterBody2D
class_name Enemy

signal stamina_changed
signal health_changed

@export var speed := 100.0
@export var max_health := 100.0
@export var max_stamina := 100.0
@export var stamina_recovery_rate := 20.0
@export var stamina_recovery_delay := 1.0
@export var parry_chance := 0.3
@export var exhausted_lock_duration := 0.35
@export var player_path: NodePath

@onready var controller: CombatController = $CombatController
@onready var audio_enemy: AudioStreamPlayer2D = $AudioEnemy
@onready var attack_hitbox: Area2D = $AttackHitbox
@onready var player: Player = get_node(player_path) as Player
@onready var sprite := $AnimatedSprite2D
@onready var flash_material := sprite.material as ShaderMaterial

var current_health := max_health
var current_stamina := max_stamina
var stamina_recovery_timer := 0.0
var exhausted_lock_timer := 0.0

var last_direction := "left"
var stunned_block_toggle := false
var should_attack_after_parry := false

var attack_sequence: Array[AttackConfig] = []
var _sfx_cache := {}

func _ready() -> void:
	attack_sequence = AttackConfig.default_sequence()
	controller.setup(self)
	controller.connect("play_sound", _on_play_sound)
	controller.connect("state_changed", _on_state_changed_with_dir)
	health_changed.emit()
	stamina_changed.emit()
	_on_state_changed_with_dir(controller.combat_state, controller.combat_state, Vector2(-1, 0))

func _process(delta: float) -> void:
	if is_player_attacking_towards_me():
		if not controller.has_effect("parry_check_cooldown"):
			if randf() < parry_chance:
				var dir: Vector2 = (player.global_position - global_position).normalized()
				controller.try_parry(true, dir)
			controller.apply_effect("parry_check_cooldown", 0.4)

	if controller.can_act():
		if stamina_recovery_timer <= 0.0:
			current_stamina += stamina_recovery_rate * delta
			current_stamina = clamp(current_stamina, 0, max_stamina)
			stamina_changed.emit()
		else:
			stamina_recovery_timer -= delta

	if exhausted_lock_timer > 0.0:
		exhausted_lock_timer -= delta
	
	if controller.combat_state == CombatController.CombatState.IDLE:
		var target := "idle_exhausted" if is_exhausted() else "idle"
		if sprite.animation != target:
			sprite.play(target)

func is_player_attacking_towards_me() -> bool:
	var player_controller: CombatController = player.get_combat_controller()
	if player_controller.combat_state != CombatController.CombatState.STARTUP:
		return false
	if global_position.distance_to(player.global_position) > 80:
		return false
	return true

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

func get_combat_controller() -> CombatController:
	return controller

func has_stamina(amount: float) -> bool:
	return current_stamina >= amount

func consume_stamina(amount: float) -> void:
	var previous := current_stamina
	current_stamina = clamp(current_stamina - amount, 0, max_stamina)
	stamina_changed.emit()
	stamina_recovery_timer = stamina_recovery_delay
	if previous >= controller.block_stamina_cost and current_stamina < controller.block_stamina_cost:
		exhausted_lock_timer = exhausted_lock_duration

func take_damage(amount: float) -> void:
	current_health -= amount
	health_changed.emit()
	flash_hit_color()
	if current_health <= 0:
		die()

func die() -> void:
	_on_play_sound("res://audio/die.wav")
	queue_free()

func on_parried() -> void:
	controller.on_parried()

func on_blocked() -> void:
	controller.on_blocked()

func _on_play_sound(path: String) -> void:
	if not _sfx_cache.has(path):
		_sfx_cache[path] = load(path)
	audio_enemy.stream = _sfx_cache[path]
	audio_enemy.play()

func _on_state_changed_with_dir(old_state: int, new_state: int, attack_direction: Vector2) -> void:
	var resolved_direction := get_label_from_vector(attack_direction)
	last_direction = resolved_direction
	update_attack_hitbox_position(last_direction)

	var anim := ""
	var attack = null
	if not controller.owner_node.attack_sequence.is_empty():
		attack = controller.owner_node.attack_sequence[controller.combo_index]

	match new_state:
		CombatController.CombatState.IDLE:
			anim = "idle_exhausted" if is_exhausted() else "idle"
			attack_hitbox.disable()
			if should_attack_after_parry:
				should_attack_after_parry = false
				var attack_vector := get_vector_from_label(last_direction)
				call_deferred("_delayed_attack", attack_vector)

		CombatController.CombatState.STARTUP:
			if attack:
				anim = attack.startup_animation
			attack_hitbox.disable()

		CombatController.CombatState.ATTACKING:
			if attack:
				anim = attack.attack_animation
			attack_hitbox.enable()

		CombatController.CombatState.RECOVERING:
			if attack:
				anim = attack.recovery_animation
			attack_hitbox.disable()
			if not controller.did_parry_succeed:
				should_attack_after_parry = true

		CombatController.CombatState.PARRY_ACTIVE:
			anim = "parry"
			attack_hitbox.disable()

		CombatController.CombatState.STUNNED:
			if controller.stun_kind == CombatController.StunKind.PARRIED:
				anim = "stunned_parry"
				controller.stun_kind = CombatController.StunKind.NONE
			else:
				anim = "stunned_block_b" if stunned_block_toggle else "stunned_block_a"
				stunned_block_toggle = not stunned_block_toggle

		CombatController.CombatState.PARRY_SUCCESS:
			anim = "parry_success"
			attack_hitbox.disable()
			should_attack_after_parry = true

	sprite.flip_h = last_direction == "left"
	if anim != "" and sprite.animation != anim:
		sprite.play(anim)

func get_label_from_vector(dir: Vector2) -> String:
	if dir == Vector2.ZERO:
		return last_direction
	return "right" if dir.x >= 0 else "left"

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

func get_vector_from_label(label: String) -> Vector2:
	match label:
		"left":
			return Vector2(-1, 0)
		"right":
			return Vector2(1, 0)
		_:
			return Vector2.ZERO

func flash_hit_color(duration := 0.1) -> void:
	flash_material.set("shader_parameter/flash", true)
	await get_tree().create_timer(duration).timeout
	flash_material.set("shader_parameter/flash", false)

func _delayed_attack(attack_vector: Vector2) -> void:
	await get_tree().process_frame
	controller.try_attack(false, attack_vector)

func is_exhausted() -> bool:
	if exhausted_lock_timer > 0.0:
		return true
	return current_stamina < controller.block_stamina_cost
