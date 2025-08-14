extends CharacterBody2D
class_name Enemy

signal stamina_changed
signal health_changed

@export var speed := 100.0
@export var exhausted_lock_duration := 0.35
@export var attack_step_duration := 0.06
@export var sfx_block: AudioStream
@export var sfx_hit: AudioStream
@export var sfx_die: AudioStream

@onready var controller: CombatController = $CombatController
@onready var audio_enemy: AudioStreamPlayer2D = $AudioEnemy
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

var last_direction := "left"
var stunned_block_toggle := false

# Pressão contínua após parry de leve (ataca até acabar stamina ou ser parryado)
var pressuring_after_parry := false
var _pending_auto_attack := false

var attack_sequence: Array[AttackConfig] = []
var exhausted_lock_timer := 0.0

# Guarda último agressor p/ afastamento no parry pesado
var _last_attacker_node: Node2D = null

func _ready() -> void:
	attack_sequence = AttackConfig.default_sequence()

	# encontra o player na árvore
	var p = get_tree().get_first_node_in_group("player")
	if p:
		brain.set_player(p)

	controller.setup(self, {
		"get_attack_sequence": func() -> Array: return attack_sequence,
		"has_stamina": func(cost: float) -> bool: return stats.has_stamina(cost),
		"consume_stamina": func(cost: float) -> void: stats.consume_stamina(cost)
	})

	controller.play_stream.connect(func(s: AudioStream): audio_out.play_stream(s))
	controller.connect("state_changed", _on_state_changed_with_dir)
	controller.hitbox_active_changed.connect(_on_hitbox_active_changed)
	controller.attack_step.connect(func(dist): stepper.start_step(dist, last_direction == "left"))
	# Afastamento solicitado após parry pesado
	controller.request_push_apart.connect(_on_request_push_apart)

	stats.health_changed.connect(func(_c,_m): health_changed.emit())
	stats.stamina_changed.connect(func(_c,_m): stamina_changed.emit())

	_on_state_changed_with_dir(controller.combat_state, controller.combat_state, Vector2(-1, 0))

func _physics_process(delta: float) -> void:
	stats.tick(delta)
	stepper.physics_tick(delta)

	# inimigo simplificado: só anda via step ou fica parado quando não está em IDLE
	if controller.combat_state != CombatController.CombatState.IDLE and not _is_step_active():
		velocity.x = 0.0
	velocity.y = 0.0
	move_and_slide()
	clamp2d.physics_tick()

func _process(delta: float) -> void:
	if exhausted_lock_timer > 0.0:
		exhausted_lock_timer -= delta

	# animação "idle" quando livre
	if controller.combat_state == CombatController.CombatState.IDLE:
		anim.set_exhausted(is_exhausted())
		anim.play_state_anim("idle")

func _on_state_changed_with_dir(old_state: int, new_state: int, attack_direction: Vector2) -> void:
	var resolved_direction := get_label_from_vector(attack_direction)
	last_direction = resolved_direction
	update_attack_hitbox_position(last_direction)

	var attack = controller.get_current_attack()
	anim.set_direction_label(last_direction)
	anim.set_exhausted(is_exhausted())

	match new_state:
		CombatController.CombatState.IDLE:
			anim.play_state_anim("idle")
			attack_hitbox.disable()
			# Loop de pressão após parry leve: tenta atacar enquanto houver stamina
			if pressuring_after_parry and not _pending_auto_attack:
				var next: AttackConfig = controller.get_current_attack()
				if next and stats.has_stamina(next.stamina_cost):
					_pending_auto_attack = true
					var attack_vector := get_vector_from_label(last_direction)
					call_deferred("_auto_attack_from_pressure", attack_vector)
				else:
					pressuring_after_parry = false

		CombatController.CombatState.STARTUP:
			if attack: anim.play_exact(attack.startup_animation)
			attack_hitbox.disable()

		CombatController.CombatState.ATTACKING:
			if attack: anim.play_exact(attack.attack_animation)
			attack_hitbox.enable()

		CombatController.CombatState.RECOVERING:
			if attack: anim.play_exact(attack.recovery_animation)
			attack_hitbox.disable()
			# (não arma nada aqui; quem decide é PARRY_SUCCESS/IDLE acima)

		CombatController.CombatState.PARRY_ACTIVE:
			anim.play_exact("parry")
			attack_hitbox.disable()

		CombatController.CombatState.STUNNED:
			var a := ("stunned_parry" if controller.stun_kind == CombatController.StunKind.PARRIED
				else ("stunned_block_b" if stunned_block_toggle else "stunned_block_a"))
			stunned_block_toggle = not stunned_block_toggle
			controller.stun_kind = CombatController.StunKind.NONE
			anim.play_exact(a)
			# Se fui parryado, cancela pressão (para respeitar “até eu ser parryado”)
			pressuring_after_parry = false

		CombatController.CombatState.PARRY_SUCCESS:
			anim.play_exact("parry_success")
			attack_hitbox.disable()
			# Se parry foi de LEVE → inicia/continua pressão; PESADO → neutro (sem pressão)
			pressuring_after_parry = not controller.last_parry_was_heavy

	# flip centralizado no AnimationDriver
	anim.set_direction_label(last_direction)

func _auto_attack_from_pressure(attack_vector: Vector2) -> void:
	_pending_auto_attack = false
	controller.try_attack(false, attack_vector)

func get_label_from_vector(dir: Vector2) -> String:
	if dir == Vector2.ZERO:
		return last_direction
	return "right" if dir.x >= 0.0 else "left"

func get_vector_from_label(label: String) -> Vector2:
	match label:
		"left": return Vector2(-1, 0)
		"right": return Vector2(1, 0)
		_: return Vector2.ZERO

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

func _on_hitbox_active_changed(on: bool) -> void:
	if on: attack_hitbox.enable()
	else: attack_hitbox.disable()

func _is_step_active() -> bool:
	return controller.combat_state == CombatController.CombatState.ATTACKING

# ======= Interface esperada pelo CombatController =======

func get_combat_controller() -> CombatController:
	return controller

func has_stamina(amount: float) -> bool:
	return stats.has_stamina(amount)

func consume_stamina(amount: float) -> void:
	var before := stats.current_stamina
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

	var c := get_combat_controller()
	var atk_cc: CombatController = null
	var atk_cfg: AttackConfig = null

	if attacker and attacker.has_node("CombatController"):
		atk_cc = attacker.get_node("CombatController") as CombatController
		if atk_cc:
			atk_cfg = atk_cc.get_current_attack()

	# I-FRAMES: durante PARRY_SUCCESS não recebe hit nem auto-block
	if c.combat_state == CombatController.CombatState.PARRY_SUCCESS:
		return

	# >>> NOVO: se estou GUARD_BROKEN, qualquer hit vira FINISHER
	if c.combat_state == CombatController.CombatState.GUARD_BROKEN and atk_cfg:
		_apply_attack_effects(atk_cfg)
		if atk_cc:
			atk_cc.resolve_finisher(atk_cc, c)
		return
	# <<< FIM NOVO

	# 1) PARRY ativo → resolver por tipo (com janela efetiva)
	if c.combat_state == CombatController.CombatState.PARRY_ACTIVE and atk_cfg and atk_cfg.parryable:
		var factor := atk_cfg.parry_window_factor if atk_cfg.parry_window_factor != 0.0 else 1.0
		var eff := c.parry_window * factor
		if c.is_within_parry_window(eff):
			c.did_parry_succeed = true
			if atk_cfg.kind == AttackConfig.AttackKind.HEAVY:
				c.resolve_parry_heavy_neutral(atk_cc, c)
			else:
				c.resolve_parry_light(atk_cc, c)
			return

	# 2) AUTO-BLOCK: só contra leves que não bypassam
	var can_autoblock := false
	if atk_cfg:
		var is_light := (atk_cfg.kind == AttackConfig.AttackKind.NORMAL)
		can_autoblock = is_light and not atk_cfg.bypass_auto_block

	if can_autoblock and has_stamina(c.block_stamina_cost):
		audio_out.play_stream(sfx_block)
		c.on_blocked()
		return

	# 3) HIT real → aplicar dano/stamina
	if atk_cfg:
		_apply_attack_effects(atk_cfg)
	else:
		audio_out.play_stream(sfx_hit)
		take_damage(20)

func _apply_attack_effects(cfg: AttackConfig) -> void:
	var c := get_combat_controller()
	# Guarda stamina antes do hit
	var stamina_before := stats.current_stamina

	# Pressão extra de stamina (antes do dano base)
	if cfg.stamina_damage_extra > 0.0:
		stats.consume_stamina(cfg.stamina_damage_extra)
		stamina_changed.emit()

	# Dano base: stamina absorve antes; sem stamina → vida
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

	# === Regra: se for HEAVY e o hit fez a stamina cair a zero, entra em GUARD_BROKEN ===
	if cfg.kind == AttackConfig.AttackKind.HEAVY and stamina_before > 0.0 and stats.current_stamina <= 0.0:
		c.force_guard_broken()

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
	# se fui parryado, interrompe pressão
	pressuring_after_parry = false

func on_blocked() -> void:
	controller.on_blocked()

func _delayed_attack(attack_vector: Vector2) -> void:
	await get_tree().process_frame
	controller.try_attack(false, attack_vector)

func flash_hit_color(duration := 0.1) -> void:
	if flash_material:
		flash_material.set("shader_parameter/flash", true)
		await get_tree().create_timer(duration).timeout
		flash_material.set("shader_parameter/flash", false)

# Afastamento simples após parry pesado (neutro)
func _on_request_push_apart(pixels: float) -> void:
	if _last_attacker_node == null or not is_instance_valid(_last_attacker_node):
		return
	var a := _last_attacker_node.global_position
	var b := global_position
	var dir := (b - a).normalized()
	if dir == Vector2.ZERO:
		dir = Vector2.RIGHT
	_last_attacker_node.global_position -= dir * pixels
	global_position += dir * pixels
