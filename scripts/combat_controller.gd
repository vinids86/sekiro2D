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
signal play_stream(stream: AudioStream) # <-- NOVO: para quando attack_sound for AudioStream
signal hitbox_active_changed(is_on: bool)
signal attack_step(distance_px: float)

var step_emitted := false
var active_clock := 0.0

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

# 0 = none/outro estado; 1 = recovering_hard; 2 = recovering_soft
var recovering_phase := 0

var transitions := {
	CombatState.IDLE:          [CombatState.STARTUP, CombatState.PARRY_ACTIVE, CombatState.STUNNED],
	CombatState.STARTUP:       [CombatState.ATTACKING, CombatState.PARRY_ACTIVE, CombatState.STUNNED],
	CombatState.ATTACKING:     [CombatState.RECOVERING, CombatState.STUNNED, CombatState.PARRY_ACTIVE],
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
	if combat_state == CombatState.ATTACKING:
		active_clock += delta
		_check_attack_step(active_clock) 

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
			var attack = _current_attack()
			if recovering_phase == 1:
				recovering_phase = 2
				state_timer = attack.recovery_soft if attack else 0.0
				if buffer_timer > 0.0:
					buffer_timer = max(buffer_timer, chain_grace)
				if queued_action == ActionType.ATTACK and _can_chain_next_on_soft(attack):
					on_attack_finished(did_parry_succeed)
					combo_in_progress = true
					combo_timeout_timer = combo_timeout_duration
					current_attack_direction = queued_direction
					_clear_buffer()
					change_state(CombatState.STARTUP)
					return
				elif state_timer <= 0.0:
					_finish_recover_and_exit()
			else:
				_finish_recover_and_exit()
		CombatState.STUNNED:
			change_state(CombatState.IDLE)
		CombatState.PARRY_SUCCESS:
			change_state(CombatState.IDLE)
		CombatState.PARRY_ACTIVE:
			if did_parry_succeed:
				change_state(CombatState.PARRY_SUCCESS)
			else:
				change_state(CombatState.IDLE)

func _finish_recover_and_exit() -> void:
	on_attack_finished(did_parry_succeed)
	if queued_action == ActionType.ATTACK && buffer_timer > 0.0:
		current_attack_direction = queued_direction
		_clear_buffer()
		change_state(CombatState.STARTUP)
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

	var attack = _current_attack()

	match state:
		CombatState.STARTUP:
			if attack:
				state_timer = attack.startup
				if owner_node.has_method("consume_stamina"):
					owner_node.consume_stamina(attack.stamina_cost)

		CombatState.ATTACKING:
			if attack:
				state_timer = attack.active_duration
				active_clock = 0.0
				hitbox_active_changed.emit(true)
				step_emitted = false
				if attack and attack.attack_sound:
					play_stream.emit(attack.attack_sound)

		CombatState.RECOVERING:
			recovering_phase = 1
			if attack:
				state_timer = attack.recovery_hard
			else:
				state_timer = 0.0
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
			recovering_phase = 0
			await get_tree().process_frame
			try_execute_buffer()

func _on_exit_state(state: CombatState) -> void:
	match state:
		CombatState.STARTUP, CombatState.ATTACKING, CombatState.PARRY_ACTIVE:
			if state == CombatState.PARRY_ACTIVE:
				apply_effect("parry_cooldown", parry_cooldown)
			if state == CombatState.ATTACKING:
				hitbox_active_changed.emit(false)

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
				_clear_buffer()
		ActionType.PARRY:
			if try_parry(true, queued_direction):
				_clear_buffer()

func try_attack(from_buffer := false, dir := Vector2.ZERO) -> bool:
	if combat_state in [CombatState.STUNNED]:
		return false
	if not owner_node or owner_node.attack_sequence.is_empty():
		return false

	var attack = _current_attack()
	if owner_node.has_method("has_stamina") and not owner_node.has_stamina(attack.stamina_cost):
		return false

	if combat_state == CombatState.IDLE:
		current_attack_direction = dir
		combo_timeout_timer = combo_timeout_duration
		combo_in_progress = true
		change_state(CombatState.STARTUP)
		return true
	elif combat_state == CombatState.RECOVERING and recovering_phase == 2:
		if _can_chain_next_on_soft(attack):
			# finalize o golpe atual antes de encadear
			on_attack_finished(false)
			combo_in_progress = true
			combo_timeout_timer = combo_timeout_duration
			current_attack_direction = dir
			_clear_buffer()
			change_state(CombatState.STARTUP)
			return true

	if not from_buffer:
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

func can_transition_to_parry() -> bool:
	# mesmas regras que combinamos (inclui STUNNED = true)
	if combat_state == CombatState.PARRY_ACTIVE:
		return false
	if has_effect("parry_cooldown"):
		return false
	if owner_node.has_method("has_stamina") and not owner_node.has_stamina(1):
		return false

	var attack = _current_attack()
	match combat_state:
		CombatState.IDLE:
			return true
		CombatState.STARTUP:
			return attack and attack.can_cancel_to_parry_on_startup
		CombatState.ATTACKING:
			return attack and attack.can_cancel_to_parry_on_active
		CombatState.RECOVERING:
			return false
		CombatState.STUNNED:
			return true
		_:
			return false

func try_parry(from_buffer := false, dir := Vector2.ZERO) -> bool:
	if not can_transition_to_parry():
		if not from_buffer:
			queued_action = ActionType.PARRY
			queued_direction = dir
			buffer_timer = input_buffer_duration
		return false

	change_state(CombatState.PARRY_ACTIVE)
	if not from_buffer:
		_clear_buffer()
		queued_direction = dir
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

func _current_attack():
	if owner_node and not owner_node.attack_sequence.is_empty():
		return owner_node.attack_sequence[combo_index]
	return null

func _can_chain_next_on_soft(attack) -> bool:
	return attack and attack.can_chain_next_attack_on_soft_recovery

func _clear_buffer() -> void:
	queued_action = ActionType.NONE
	queued_direction = Vector2.ZERO
	buffer_timer = 0.0

func _resolve_attack_stream(snd) -> AudioStream:
	# aceitamos AudioStream direto ou path (com/sem extensão)
	if snd == null:
		return null
	if snd is AudioStream:
		return snd
	var path := str(snd)
	if path.is_empty():
		return null
	# anexa extensão se preciso
	if not (path.ends_with(".wav") or path.ends_with(".ogg")):
		if ResourceLoader.exists(path + ".wav"):
			path += ".wav"
		elif ResourceLoader.exists(path + ".ogg"):
			path += ".ogg"
	# carrega
	if ResourceLoader.exists(path):
		var s: AudioStream = load(path)
		return s
	print("⚠️ Attack sound não encontrado: ", path)
	return null

func _play_attack_stream(stream: AudioStream) -> void:
	if stream == null:
		return
	# tenta tocar direto no dono (Player/Enemy) se tiver AudioPlayer
	if owner_node:
		var p = owner_node.get_node_or_null("AudioPlayer")
		if p and p is AudioStreamPlayer2D:
			p.stream = stream
			p.play()
			return
	# fallback por sinal (caso você já tenha algo conectado)
	play_stream.emit(stream)

func get_current_attack():
	return _current_attack()

func _check_attack_step(t: float) -> void:
	var atk = _current_attack()
	if not atk or step_emitted:
		return
	if atk.step_distance_px == 0.0:
		return
	if t >= atk.step_time_in_active and t <= (atk.step_time_in_active + 0.02):
		step_emitted = true
		attack_step.emit(atk.step_distance_px)
