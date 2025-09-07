extends Node
class_name PoiseController

var _base_poise: float = 0.0
var _bonus_poise_pending: float = 0.0
var _attack_bonus_poise_applied: float = 0.0
var _parry_bonus_ready: bool = false
var _parry_bonus_amount: float = 0.0
var _parry_bonus_duration: float = 0.0

var _bonus_poise_timer: Timer

func _ready() -> void:
	_bonus_poise_timer = Timer.new()
	_bonus_poise_timer.one_shot = true
	add_child(_bonus_poise_timer)
	_bonus_poise_timer.timeout.connect(_on_bonus_poise_timeout)

func initialize(base_poise: float) -> void:
	_base_poise = base_poise
	_bonus_poise_pending = 0.0
	_attack_bonus_poise_applied = 0.0
	_bonus_poise_timer.stop()

func get_effective_poise(current_action_poise: float) -> float:
	var bonus_now: float = _attack_bonus_poise_applied
	if _bonus_poise_pending > bonus_now:
		bonus_now = _bonus_poise_pending
	return _base_poise + current_action_poise + bonus_now

func on_attack_started() -> void:
	if _bonus_poise_timer.time_left > 0.0 and _bonus_poise_pending > 0.0:
		if _bonus_poise_pending > _attack_bonus_poise_applied:
			_attack_bonus_poise_applied = _bonus_poise_pending
		_bonus_poise_pending = 0.0

func on_action_finished() -> void:
	_attack_bonus_poise_applied = 0.0

func on_guard_broken() -> void:
	_bonus_poise_pending = 0.0
	_bonus_poise_timer.stop()

func arm_parry_bonus(parry_profile: ParryProfile) -> void:
	# --- CORREÇÃO FINAL APLICADA ---
	# Voltando a um método seguro que verifica o tipo da propriedade.
	var amount: float = 0.0
	var duration: float = 0.0
	
	var amount_var: Variant = parry_profile.get("bonus_poise_amount")
	if typeof(amount_var) == TYPE_FLOAT or typeof(amount_var) == TYPE_INT:
		amount = float(amount_var)
		
	var duration_var: Variant = parry_profile.get("bonus_poise_duration")
	if typeof(duration_var) == TYPE_FLOAT or typeof(duration_var) == TYPE_INT:
		duration = float(duration_var)

	if amount > 0.0 and duration > 0.0:
		_parry_bonus_ready = true
		_parry_bonus_amount = amount
		_parry_bonus_duration = duration
	else:
		_parry_bonus_ready = false
		_parry_bonus_amount = 0.0
		_parry_bonus_duration = 0.0

func try_activate_parry_bonus_window() -> void:
	if _parry_bonus_ready:
		if _parry_bonus_duration > 0.0 and _parry_bonus_amount > 0.0:
			_bonus_poise_pending = _parry_bonus_amount
			_bonus_poise_timer.start(_parry_bonus_duration)
		
		_parry_bonus_ready = false
		_parry_bonus_amount = 0.0
		_parry_bonus_duration = 0.0

func _on_bonus_poise_timeout() -> void:
	_bonus_poise_pending = 0.0
