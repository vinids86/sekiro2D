extends RefCounted
class_name LockoutManager

var force_timer: float = -1.0
var forced_active: bool = false

var parry_success_override: float = -1.0
var stun_override: float = -1.0
var guard_broken_override: float = -1.0

# -------- Force Recover (lockout forçado) --------
func begin_force_recover(duration: float) -> void:
	force_timer = maxf(duration, 0.0)
	forced_active = false

# Retorna o tempo do lockout forçado (>=0) e marca como ativo; se não houver, retorna -1
func pop_force_recover() -> float:
	if force_timer >= 0.0:
		forced_active = true
		return force_timer
	return -1.0

func is_forced_active() -> bool:
	return forced_active

func finish_force_recover() -> void:
	forced_active = false
	force_timer = -1.0

func clear_force_recover() -> void:
	forced_active = false
	force_timer = -1.0

# -------- Overrides de duração (consumidos uma vez) --------
func set_parry_success_override(duration: float) -> void:
	parry_success_override = maxf(duration, 0.0)

func set_stun_override(duration: float) -> void:
	stun_override = maxf(duration, 0.0)

func set_guard_broken_override(duration: float) -> void:
	guard_broken_override = maxf(duration, 0.0)

func consume_parry_success_duration(default_val: float) -> float:
	var v: float = default_val
	if parry_success_override >= 0.0:
		v = parry_success_override
	parry_success_override = -1.0
	return v

func consume_stun_duration(default_val: float) -> float:
	var v: float = default_val
	if stun_override >= 0.0:
		v = stun_override
	stun_override = -1.0
	return v

func consume_guard_broken_duration(default_val: float) -> float:
	var v: float = default_val
	if guard_broken_override >= 0.0:
		v = guard_broken_override
	guard_broken_override = -1.0
	return v

func clear_all() -> void:
	clear_force_recover()
	parry_success_override = -1.0
	stun_override = -1.0
	guard_broken_override = -1.0
