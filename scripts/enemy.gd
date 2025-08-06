extends CharacterBody2D

class_name Enemy

signal stamina_changed
signal health_changed

@export var speed := 100.0
@export var stamina_recovery_rate := 20.0  # unidades por segundo
@export var stamina_recovery_delay := 1.0  # segundos após ação para começar a recuperar
@export var max_stamina := 100.0
@onready var current_stamina := max_stamina
@export var max_health := 100.0
@onready var current_health := max_health
var stamina_recovery_timer := 0.0
var last_direction = "left"
@export var parry_chance := 0.6
@export var player_path: NodePath
@onready var attack_hitbox: Area2D = $AttackHitbox
@onready var controller: CombatController = $CombatController
@onready var player: Node = get_node(player_path)
@onready var audio_enemy: AudioStreamPlayer2D = $AudioEnemy
var should_attack_after_parry := false
@onready var sprite := $AnimatedSprite2D
@onready var flash_material := sprite.material as ShaderMaterial

func _ready():
	$AnimatedSprite2D.modulate = Color(1, 0.3, 0.3)  # Vermelho mais suave
	$AnimatedSprite2D.play("idle")
	$CombatController.setup(self)
	controller.connect("play_sound", _on_play_sound)
	controller.connect("state_changed", _on_state_changed_with_dir)
	health_changed.emit()
	stamina_changed.emit()
	$AnimatedSprite2D.flip_h = last_direction == "left"

func _process(delta):

	if is_player_attacking_towards_me():
		if not controller.has_effect("parry_check_cooldown"):
			if randf() < parry_chance:
				print("🎯 Enemy tentou parry preemptivo!")
				var dir = (player.global_position - global_position).normalized()
				controller.try_parry(true, dir)

			# Impede múltiplas tentativas por ataque
			controller.apply_effect("parry_check_cooldown", 0.4)

	if get_combat_controller().can_act():
		if stamina_recovery_timer <= 0.0:
			current_stamina += stamina_recovery_rate * delta
			current_stamina = clamp(current_stamina, 0, max_stamina)
			stamina_changed.emit()
		else:
			stamina_recovery_timer -= delta

func is_player_attacking_towards_me() -> bool:
	var player_controller = player.get_combat_controller()
	if player_controller.combat_state != CombatController.CombatState.STARTUP:
		return false

	# Opcional: verifica distância
	if global_position.distance_to(player.global_position) > 80:
		return false

	return true

func receive_attack(attacker: Node):
	var controller = get_combat_controller()
	var attacker_controller = attacker.get_combat_controller()

	# Se o parry já estiver ativo, rebate o ataque
	if controller.combat_state == CombatController.CombatState.PARRY_ACTIVE:
		print("⚡ Enemy executou parry com sucesso")
		controller.did_parry_succeed = true
		attacker.on_parried()
		return

	# Senão tenta bloquear
	if has_stamina(controller.block_stamina_cost):
		print("🛡️ Enemy bloqueou o ataque")
		consume_stamina(controller.block_stamina_cost)
		_on_play_sound("res://audio/block.wav")
		controller.on_blocked()
		return

	# Caso contrário, sofre dano
	print("💥 Enemy sofreu dano real")
	_on_play_sound("res://audio/hit.wav")
	take_damage(20)

func get_combat_controller():
	return $CombatController

func has_stamina(amount: float) -> bool:
	return current_stamina >= amount

func consume_stamina(amount: float):
	var previous = current_stamina
	current_stamina = clamp(current_stamina - amount, 0, max_stamina)
	stamina_changed.emit()
	stamina_recovery_timer = stamina_recovery_delay

func take_damage(amount: float):
	current_health -= amount
	health_changed.emit()
	flash_hit_color()
	if current_health <= 0:
		die()

func die():
	_on_play_sound("res://audio/die.wav")
	queue_free()
	print("☠ ", self.name, " morreu.")

func on_parried():
	print("⛔ Enemy foi parryado! Entrando em GUARD_BROKEN.")
	get_combat_controller().on_parried()

func on_blocked():
	print("🛡️ Enemy bloqueou o ataque. Entrando em STUNNED.")
	get_combat_controller().on_blocked()

func _on_play_sound(path: String):
	audio_enemy.stream = load(path)
	audio_enemy.play()

func _on_state_changed_with_dir(old_state: int, new_state: int, attack_direction: Vector2):
	var resolved_direction = get_label_from_vector(attack_direction)
	last_direction = resolved_direction
	var anim := ""

	match new_state:
		CombatController.CombatState.IDLE:
			anim = "idle"
			attack_hitbox.disable()
			
			if should_attack_after_parry:
				should_attack_after_parry = false
				var attack_vector = get_vector_from_label(last_direction)
				controller.try_attack(false, attack_vector)

		CombatController.CombatState.STARTUP:
			anim = "startup_attack"
			update_attack_hitbox_position(last_direction)
			# Aqui ainda não ativa — hitbox só será ativada em ATTACKING

		CombatController.CombatState.ATTACKING:
			anim = "attack"
			attack_hitbox.enable()

		CombatController.CombatState.RECOVERING:
			anim = "recoverring_attack"
			attack_hitbox.disable()
			# ⚠️ Continua atacando se o ataque não foi parryado
			if not controller.did_parry_succeed:
				should_attack_after_parry = true
		
		CombatController.CombatState.PARRY_ACTIVE:
			anim = "parry"
			attack_hitbox.disable()

		CombatController.CombatState.GUARD_BROKEN:
			anim = "guard_broken"
			attack_hitbox.disable()

		CombatController.CombatState.STUNNED:
			anim = "stunned"
			attack_hitbox.disable()

		CombatController.CombatState.PARRY_SUCCESS:
			anim = "parry_success"
			attack_hitbox.disable()
			should_attack_after_parry = true

	$AnimatedSprite2D.flip_h = last_direction == "left"
	$AnimatedSprite2D.play(anim)
	
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

func flash_hit_color(duration := 0.1):
	flash_material.set("shader_parameter/flash", true)

	await get_tree().create_timer(duration).timeout

	flash_material.set("shader_parameter/flash", false)
