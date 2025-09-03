extends RefCounted
class_name CombatStateRegistry

static var _S: Dictionary = {}
static var _map: Dictionary = {}

static func bind_states(state_enum: Dictionary) -> void:
	_S = state_enum.duplicate()
	_map.clear()

	_map[_S.IDLE]         = StateIdle.new()
	_map[_S.ATTACK]       = StateAttack.new()
	_map[_S.PARRY]        = StateParry.new()
	_map[_S.PARRIED]      = StateParried.new()
	_map[_S.DODGE]        = StateDodge.new()
	_map[_S.STUNNED]      = StateStunned.new()
	_map[_S.GUARD_BROKEN] = StateGuardBroken.new()
	_map[_S.GUARD_HIT]    = StateGuardHit.new()
	_map[_S.FINISHER_READY]   = StateFinisherReady.new()
	_map[_S.BROKEN_FINISHER]  = StateBrokenFinisher.new()
	_map[_S.DEAD]         = StateDead.new()

static func get_state_for(state_id: int) -> StateBase:
	assert(_map.has(state_id), "CombatStateRegistry: estado sem classe registrada (id=%s)" % [str(state_id)])
	return _map[state_id]

static func validate_all_states() -> void:
	for k in _S.values():
		assert(_map.has(k), "CombatStateRegistry: estado sem classe registrada (id=%s)" % [str(k)])
