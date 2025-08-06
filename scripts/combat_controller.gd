extends Node
class_name CombatController

enum CombatState {
	IDLE,
	STARTUP,
	ATTACKING,
	PARRY_ACTIVE,
	PARRY_SUCCESS,
	PARRY_MISS,
	RECOVERING,
	STUNNED,
	GUARD_BROKEN
}

enum ActionType {
	NONE,
	ATTACK,
	PARRY
}

signal state_changed(old_state: int, new_state: int, attack_direction: Vector2)
signal play_sound(path: String)

@export var attack_startup := 1.6
@export var attack_duration := 0.3
@export var recovery_duration := 0.3
@export var parry_window := 0.4
@export var parry_cooldown := 0.2
@export var block_stun := 1.0
@export var guard_break_stun := 3
@export var input_buffer_duration := 0.4
@export var attack_stamina_cost := 5.0
@export var block_stamina_cost := 10.0

var combat_state: CombatState = CombatState.IDLE
var previous_state: CombatState = CombatState.IDLE
var state_timer: float = 0.0
var owner_node: Node

var queued_action: ActionType = ActionType.NONE
var queued_direction: Vector2 = Vector2.ZERO
var buffer_timer: float = 0.0
var current_attack_direction: Vector2 = Vector2.ZERO

var status_effects: Dictionary = {}

var did_parry_succeed := false

var transitions := {
	CombatState.IDLE: [CombatState.STARTUP, CombatState.PARRY_ACTIVE, CombatState.STUNNED],
	CombatState.STARTUP: [CombatState.ATTACKING, CombatState.PARRY_ACTIVE],
	CombatState.ATTACKING: [CombatState.RECOVERING, CombatState.GUARD_BROKEN],
	CombatState.RECOVERING: [CombatState.IDLE],
	CombatState.PARRY_ACTIVE: [CombatState.PARRY_SUCCESS, CombatState.PARRY_MISS],
	CombatState.PARRY_SUCCESS: [CombatState.IDLE],
	CombatState.PARRY_MISS: [CombatState.STUNNED],
	CombatState.STUNNED: [CombatState.IDLE, CombatState.STUNNED, CombatState.PARRY_ACTIVE],
	CombatState.GUARD_BROKEN: [CombatState.IDLE, CombatState.STUNNED, CombatState.PARRY_ACTIVE]
}

func setup(owner: Node):
	owner_node = owner

func _process(delta):
	if buffer_timer > 0:
		buffer_timer -= delta
		if buffer_timer <= 0:
			queued_action = ActionType.NONE
			
	# Tenta executar a ação buffered se possível
	if can_act() and queued_action != ActionType.NONE:
		try_execute_buffer()

	if state_timer > 0:
		state_timer -= delta
		if state_timer <= 0 and can_auto_advance():
			auto_advance_state()

	var expired = []
	for effect_name in status_effects.keys():
		status_effects[effect_name] -= delta
		if status_effects[effect_name] <= 0:
			expired.append(effect_name)
	for effect_name in expired:
		status_effects.erase(effect_name)

func can_auto_advance() -> bool:
	return [CombatState.STARTUP, CombatState.ATTACKING, CombatState.RECOVERING,
			CombatState.STUNNED, CombatState.GUARD_BROKEN,
			CombatState.PARRY_ACTIVE, CombatState.PARRY_SUCCESS,
			CombatState.PARRY_MISS].has(combat_state)

func auto_advance_state():
	match combat_state:
		CombatState.STARTUP:
			change_state(CombatState.ATTACKING)
		CombatState.ATTACKING:
			change_state(CombatState.RECOVERING)
		CombatState.RECOVERING:
			change_state(CombatState.IDLE)
		CombatState.STUNNED:
			change_state(CombatState.IDLE)
		CombatState.GUARD_BROKEN:
			change_state(CombatState.IDLE)
		CombatState.PARRY_SUCCESS:
			change_state(CombatState.IDLE)
		CombatState.PARRY_MISS:
			change_state(CombatState.STUNNED)
		CombatState.PARRY_ACTIVE:
			if did_parry_succeed:
				change_state(CombatState.PARRY_SUCCESS)
			else:
				change_state(CombatState.PARRY_MISS)

func change_state(new_state: CombatState):
	if not transitions.get(combat_state, []).has(new_state):
		if owner_node:
			print("❌ Transição inválida para %s: %s → %s" % [
				owner_node.name,
				CombatState.keys()[combat_state],
				CombatState.keys()[new_state]
			])
		else:
			print("❌ Transição inválida: %s → %s (sem owner_node)" % [
				CombatState.keys()[combat_state],
				CombatState.keys()[new_state]
			])
		return

	print("🔁 %s mudando estado: %s → %s" % [
		owner_node.name,
		CombatState.keys()[combat_state],
		CombatState.keys()[new_state]
	])

	previous_state = combat_state
	_on_exit_state(combat_state)
	combat_state = new_state
	_on_enter_state(combat_state)
		# ⚠️ Atualiza direção para o ataque
	if new_state == CombatState.STARTUP and queued_action == ActionType.ATTACK:
		current_attack_direction = queued_direction

	emit_signal("state_changed", previous_state, new_state, current_attack_direction)

func _on_enter_state(state: CombatState):
	did_parry_succeed = false

	match state:
		CombatState.STARTUP:
			state_timer = attack_startup
			owner_node.consume_stamina(attack_stamina_cost)
		CombatState.ATTACKING:
			state_timer = attack_duration
			play_sound.emit("res://audio/attack.wav")
		CombatState.PARRY_ACTIVE:
			state_timer = parry_window
			play_sound.emit("res://audio/parry_active.wav")
		CombatState.RECOVERING:
			state_timer = recovery_duration
		CombatState.STUNNED:
			state_timer = block_stun
			queued_action = ActionType.NONE
			buffer_timer = 0
		CombatState.GUARD_BROKEN:
			state_timer = guard_break_stun
			apply_effect("post_guard_break", 0.3)
		CombatState.PARRY_SUCCESS:
			state_timer = 0.4
			play_sound.emit("res://audio/parry_success.wav")
		CombatState.PARRY_MISS:
			state_timer = 0.2
		CombatState.IDLE:
			if previous_state != CombatState.GUARD_BROKEN:
				try_execute_buffer()

func _on_exit_state(state: CombatState):
	match state:
		CombatState.STARTUP, CombatState.ATTACKING, CombatState.PARRY_ACTIVE:
			if state == CombatState.PARRY_ACTIVE:
				apply_effect("parry_cooldown", parry_cooldown)

func apply_effect(name: String, duration: float):
	status_effects[name] = duration

func has_effect(name: String) -> bool:
	return status_effects.has(name)

func try_execute_buffer():
	if not can_act():
		return

	match queued_action:
		ActionType.ATTACK:
			if try_attack(true, queued_direction):
				current_attack_direction = queued_direction
				queued_action = ActionType.NONE
				queued_direction = Vector2.ZERO

func try_attack(from_buffer := false, dir := Vector2.ZERO):
	if owner_node.has_method("has_stamina") and not owner_node.has_stamina(attack_stamina_cost):
		return false

	if combat_state in [CombatState.STUNNED, CombatState.GUARD_BROKEN]:
		return false

	if combat_state == CombatState.IDLE:
		current_attack_direction = dir
		change_state(CombatState.STARTUP)
		return true

	elif not from_buffer:
		queued_action = ActionType.ATTACK
		queued_direction = dir
		buffer_timer = input_buffer_duration

	return false

func try_parry(from_buffer := false, dir := Vector2.ZERO):
	if combat_state in [CombatState.PARRY_ACTIVE]:
		return false

	if has_effect("parry_cooldown"):
		return false

	if combat_state in [CombatState.IDLE, CombatState.STARTUP, CombatState.STUNNED, CombatState.GUARD_BROKEN]:
		change_state(CombatState.PARRY_ACTIVE)
		if not from_buffer:
			queued_action = ActionType.NONE
			queued_direction = dir
			buffer_timer = 0
		return true

	return false

func on_parried():
	change_state(CombatState.GUARD_BROKEN)

func on_blocked():
	change_state(CombatState.STUNNED)
	owner_node.consume_stamina(block_stamina_cost)

func can_act() -> bool:
	return combat_state in [CombatState.IDLE, CombatState.RECOVERING]
