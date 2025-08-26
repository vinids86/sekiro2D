extends RefCounted
class_name CombatStateRegistry

static var _S: Dictionary = {}

static var _map: Dictionary = {}

static func bind_states(state_enum: Dictionary) -> void:
	_S = state_enum.duplicate()
	_map.clear()

	# Núcleo
	_map[_S.IDLE]    = StateIdle.new()
	_map[_S.STARTUP] = StateStartupLight.new()
	_map[_S.HIT]     = StateHit.new()
	_map[_S.RECOVER] = StateRecover.new()
	_map[_S.STUN]    = StateStun.new()

	# Parry
	_map[_S.PARRY_STARTUP] = StateParryStartup.new()
	_map[_S.PARRY_SUCCESS] = StateParrySuccess.new()
	_map[_S.PARRY_RECOVER] = StateParryRecover.new()

	# Reações / guard
	_map[_S.HIT_REACT]     = StateHitReact.new()
	_map[_S.PARRIED]       = StateParried.new()
	_map[_S.GUARD_HIT]     = StateGuardHit.new()
	_map[_S.GUARD_RECOVER] = StateGuardRecover.new()

	# Counter
	_map[_S.COUNTER_STARTUP] = StateCounterStartup.new()
	_map[_S.COUNTER_HIT]     = StateCounterHit.new()
	_map[_S.COUNTER_RECOVER] = StateCounterRecover.new()

	# Guard broken / broken finisher
	_map[_S.GUARD_BROKEN]          = StateGuardBroken.new()
	_map[_S.BROKEN_FINISHER_REACT] = StateBrokenFinisherReact.new()

	# Finisher
	_map[_S.FINISHER_STARTUP] = StateFinisherStartup.new()
	_map[_S.FINISHER_HIT]     = StateFinisherHit.new()
	_map[_S.FINISHER_RECOVER] = StateFinisherRecover.new()

	# Combo
	_map[_S.COMBO_PARRY]   = StateComboParry.new()
	_map[_S.COMBO_PREP]    = StateComboPrep.new()
	_map[_S.COMBO_STARTUP] = StateComboStartup.new()
	_map[_S.COMBO_HIT]     = StateComboHit.new()
	_map[_S.COMBO_RECOVER] = StateComboRecover.new()

	# Dodge
	_map[_S.DODGE_STARTUP] = StateDodgeStartup.new()
	_map[_S.DODGE_ACTIVE]  = StateDodgeActive.new()
	_map[_S.DODGE_RECOVER] = StateDodgeRecover.new()

	# Heavy (novos estados dedicados)
	_map[_S.HEAVY_STARTUP] = StateHeavyStartup.new()
	_map[_S.HEAVY_HIT]     = StateHeavyHit.new()
	_map[_S.HEAVY_RECOVER] = StateHeavyRecover.new()

static func get_state_for(state_id: int) -> StateBase:
	assert(_map.has(state_id), "CombatStateRegistry: estado sem classe registrada (id=%s)" % [str(state_id)])
	return _map[state_id]

static func validate_all_states() -> void:
	for k in _S.values():
		assert(_map.has(k), "CombatStateRegistry: estado sem classe registrada (id=%s)" % [str(k)])
