extends Node
class_name CombatController

enum StunKind { NONE, BLOCKED, PARRIED }
var stun_kind: StunKind = StunKind.NONE

enum CombatState {
	IDLE,
	STARTUP,
	ATTACKING,
	PARRY_ACTIVE,
	PARRY_SUCCESS,
	RECOVERING,
	STUNNED
}

enum ActionType {
	NONE,
	ATTACK,
	PARRY
}

signal state_changed(old_state: int, new_state: int, attack_direction: Vector2)
signal play_sound(path: String)

@export var parry_window := 0.4
@export var parry_cooldown := 0.2
@export var block_stun := 1.0
@export var input_buffer_duration := 0.4
@export var block_stamina_cost := 10.0
@export var combo_timeout_duration := 2.0
@export var chain_grace := 0.12

var combo_timeout_timer := 0.0
var combo_in_progress := false
var combo_index := 0

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
	CombatState.IDLE:          [CombatState.STARTUP, CombatState.PARRY_ACTIVE, CombatState.STUNNED],
	CombatState.STARTUP:       [CombatState.ATTACKING, CombatState.PARRY_ACTIVE, CombatState.STUNNED],
	CombatState.ATTACKING:     [CombatState.RECOVERING, CombatState.STUNNED],
	CombatState.RECOVERING:    [CombatState.IDLE, CombatState.STUNNED, CombatState.STARTUP],
	CombatState.PARRY_ACTIVE:  [CombatState.PARRY_SUCCESS, CombatState.IDLE, CombatState.STUNNED],
	CombatState.PARRY_SUCCESS: [CombatState.IDLE, CombatState.STUNNED],
	CombatState.STUNNED:       [CombatState.IDLE, CombatState.STUNNED, CombatState.PARRY_ACTIVE]
}

func setup(owner: Node) -> void:
	owner_node = owner

func _process(delta: float) -> void:
	if buffer_timer > 0.0:
		buffer_timer -= delta
		if buffer_timer <= 0.0:
			queued_action = ActionType.NONE

	if can_act() and queued_action != ActionType.NONE:
		try_execute_buffer()

	if state_timer > 0.0:
		state_timer -= delta
		if state_timer <= 0.0 and can_auto_advance():
			auto_advance_state()

	var expired := []
	for effect_name in status_effects.keys():
		status_effects[effect_name] -= delta
		if status_effects[effect_name] <= 0.0:
			expired.append(effect_name)
	for effect_name in expired:
		status_effects.erase(effect_name)

	if combo_in_progress:
		combo_timeout_timer -= delta
		if combo_timeout_timer <= 0.0:
			combo_index = 0
			combo_in_progress = false

func can_auto_advance() -> bool:
	return [CombatState.STARTUP, CombatState.ATTACKING, CombatState.RECOVERING,
			CombatState.STUNNED, CombatState.PARRY_ACTIVE, CombatState.PARRY_SUCCESS].has(combat_state)

func auto_advance_state() -> void:
	match combat_state:
		CombatState.STARTUP:
			change_state(CombatState.ATTACKING)
		CombatState.ATTACKING:
			change_state(CombatState.RECOVERING)
		CombatState.RECOVERING:
			on_attack_finished(did_parry_succeed)
			if queued_action == ActionType.ATTACK and buffer_timer > 0.0:
				current_attack_direction = queued_direction
				queued_action = ActionType.NONE
				queued_direction = Vector2.ZERO
				change_state(CombatState.STARTUP)
			else:
				change_state(CombatState.IDLE)
		CombatState.STUNNED:
			change_state(CombatState.IDLE)
		CombatState.PARRY_SUCCESS:
			change_state(CombatState.IDLE)
		CombatState.PARRY_ACTIVE:
			if did_parry_succeed:
				change_state(CombatState.PARRY_SUCCESS)
			else:
				change_state(CombatState.IDLE)

func change_state(new_state: CombatState) -> void:
	if not transitions.get(combat_state, []).has(new_state):
		return
	print("%s mudando estado: %s → %s" % [
		owner_node.name,
		CombatState.keys()[combat_state],
		CombatState.keys()[new_state]
	])
	previous_state = combat_state
	_on_exit_state(combat_state)
	combat_state = new_state
	_on_enter_state(combat_state)
	emit_signal("state_changed", previous_state, new_state, current_attack_direction)

func _on_enter_state(state: CombatState) -> void:
	did_parry_succeed = false

	var attack = null
	if owner_node and not owner_node.attack_sequence.is_empty():
		attack = owner_node.attack_sequence[combo_index]

	match state:
		CombatState.STARTUP:
			if attack:
				state_timer = attack.startup
				if owner_node.has_method("consume_stamina"):
					owner_node.consume_stamina(attack.stamina_cost)

		CombatState.ATTACKING:
			if attack:
				state_timer = attack.duration
				if attack.attack_sound != "":
					play_sound.emit(attack.attack_sound)

		CombatState.RECOVERING:
			if attack:
				state_timer = attack.recovery
			if buffer_timer > 0.0:
				buffer_timer = max(buffer_timer, chain_grace)

		CombatState.PARRY_ACTIVE:
			state_timer = parry_window
			play_sound.emit("res://audio/parry_active.wav")

		CombatState.STUNNED:
			state_timer = block_stun
			queued_action = ActionType.NONE
			buffer_timer = 0.0

		CombatState.PARRY_SUCCESS:
			state_timer = 0.4
			play_sound.emit("res://audio/parry_success.wav")

		CombatState.IDLE:
			await get_tree().process_frame
			try_execute_buffer()

func _on_exit_state(state: CombatState) -> void:
	match state:
		CombatState.STARTUP, CombatState.ATTACKING, CombatState.PARRY_ACTIVE:
			if state == CombatState.PARRY_ACTIVE:
				apply_effect("parry_cooldown", parry_cooldown)

func apply_effect(name: String, duration: float) -> void:
	status_effects[name] = duration

func has_effect(name: String) -> bool:
	return status_effects.has(name)

func try_execute_buffer() -> void:
	if not can_act():
		return
	match queued_action:
		ActionType.ATTACK:
			if try_attack(true, queued_direction):
				current_attack_direction = queued_direction
				queued_action = ActionType.NONE
				queued_direction = Vector2.ZERO

func try_attack(from_buffer := false, dir := Vector2.ZERO) -> bool:
	if combat_state in [CombatState.STUNNED]:
		return false
	if not owner_node or owner_node.attack_sequence.is_empty():
		return false

	var sequence = owner_node.attack_sequence
	var attack = sequence[combo_index]

	if owner_node.has_method("has_stamina") and not owner_node.has_stamina(attack.stamina_cost):
		return false

	if combat_state == CombatState.IDLE:
		current_attack_direction = dir
		combo_timeout_timer = combo_timeout_duration
		combo_in_progress = true
		change_state(CombatState.STARTUP)
		return true
	elif not from_buffer:
		queued_action = ActionType.ATTACK
		queued_direction = dir
		buffer_timer = input_buffer_duration

	return false

func on_attack_finished(was_parried: bool) -> void:
	if was_parried:
		combo_index = 0
		combo_in_progress = false
	else:
		if owner_node and not owner_node.attack_sequence.is_empty():
			combo_index = (combo_index + 1) % owner_node.attack_sequence.size()

func try_parry(from_buffer := false, dir := Vector2.ZERO) -> bool:
	if combat_state == CombatState.PARRY_ACTIVE:
		return false
	if has_effect("parry_cooldown"):
		return false
	if owner_node.has_method("has_stamina") and not owner_node.has_stamina(1):
		return false
	if combat_state not in [CombatState.IDLE, CombatState.STARTUP, CombatState.STUNNED]:
		return false

	change_state(CombatState.PARRY_ACTIVE)

	if not from_buffer:
		queued_action = ActionType.NONE
		queued_direction = dir
		buffer_timer = 0.0

	return true

func on_parried() -> void:
	stun_kind = StunKind.PARRIED
	change_state(CombatState.STUNNED)

func on_blocked() -> void:
	stun_kind = StunKind.BLOCKED
	change_state(CombatState.STUNNED)
	if owner_node.has_method("consume_stamina"):
		owner_node.consume_stamina(block_stamina_cost)

func can_act() -> bool:
	return combat_state in [CombatState.IDLE, CombatState.RECOVERING]
