extends RefCounted
class_name CombatStateRegistry

static func build_states(state_enum: Dictionary) -> Dictionary:
	var map: Dictionary = {}

	map[state_enum.IDLE]             = StateIdle.new()
	map[state_enum.ATTACK]           = StateAttack.new()
	map[state_enum.PARRY]            = StateParry.new()
	map[state_enum.PARRIED]          = StateParried.new()
	map[state_enum.DODGE]            = StateDodge.new()
	map[state_enum.STUNNED]          = StateStunned.new()
	map[state_enum.GUARD_BROKEN]     = StateGuardBroken.new()
	map[state_enum.GUARD_HIT]        = StateGuardHit.new()
	map[state_enum.FINISHER_READY]   = StateFinisherReady.new()
	map[state_enum.BROKEN_FINISHER]  = StateBrokenFinisher.new()
	map[state_enum.DEAD]             = StateDead.new()

	return map
