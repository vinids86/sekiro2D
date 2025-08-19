extends RefCounted
class_name LockoutManager

var parry_success_override: float = -1.0
var stun_override: float = -1.0
var guard_broken_override: float = -1.0

# --- Cooldowns ---
var _parry_cd: float = 0.0
var _dodge_cd: float = 0.0

# ===================== TICK =====================
func tick(delta: float) -> void:
	if _parry_cd > 0.0:
		_parry_cd -= delta
	if _dodge_cd > 0.0:
		_dodge_cd -= delta

# ===================== OVERRIDES DE DURAÇÃO =====================
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

# ===================== COOLDOWNS =====================
func start_parry_cd(duration: float) -> void:
	_parry_cd = maxf(_parry_cd, maxf(0.0, duration))

func is_parry_on_cooldown() -> bool:
	return _parry_cd > 0.0

func start_dodge_cd(duration: float) -> void:
	_dodge_cd = maxf(_dodge_cd, maxf(0.0, duration))

func is_dodge_on_cooldown() -> bool:
	return _dodge_cd > 0.0

# ===================== CLEAR =====================
func clear_all() -> void:
	parry_success_override = -1.0
	stun_override = -1.0
	guard_broken_override = -1.0
	_parry_cd = 0.0
	_dodge_cd = 0.0
