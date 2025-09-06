extends Node
class_name MoveController

signal movement_changed(moving: bool)

@export var speed: float = 220.0
@export var accel: float = 1200.0
@export var decel: float = 1600.0

# Enquanto o Enemy for Node2D (sem corpo físico), mantenha ON
@export var use_min_spacing: bool = true
@export var min_spacing: float = 48.0

# Histerese para filtrar ruído e não ficar ligando/desligando animação
@export var epsilon_speed: float = 2.0

var _was_moving: bool = false

# Aux: aproximação numérica sem usar operador ternário
func _approach(current: float, target: float, rate: float, delta: float) -> float:
	var diff: float = target - current
	var step: float = rate * delta
	if diff > 0.0:
		if diff < step:
			return target
		return current + step
	elif diff < 0.0:
		if -diff < step:
			return target
		return current - step
	return target

# Calcula vx desejado considerando FSM + clamp opcional de aproximação.
# Também emite movement_changed quando o estado (parado/andando) muda.
func compute_vx(
		body: CharacterBody2D,
		cc: CombatController,
		fd: FacingDriver,
		axis: float,
		delta: float
) -> float:
	var allowed: bool = cc != null and cc.allows_movement_now()
	var target: float = 0.0
	if allowed:
		target = axis * speed

	var vx: float = body.velocity.x
	var rate: float = accel
	if absf(target) < absf(vx):
		rate = decel
	vx = _approach(vx, target, rate, delta)

	var clamped: bool = false

	if use_min_spacing and fd != null:
		var opp: Node2D = fd.opponent
		if opp != null and is_instance_valid(opp):
			var dx: float = opp.global_position.x - body.global_position.x
			var dist: float = absf(dx)

			var facing_sign: int = 1
			if typeof(fd.sign) == TYPE_INT:
				facing_sign = fd.sign

			var toward_opp: bool = (axis * float(facing_sign)) > 0.0
			if dist <= min_spacing and toward_opp:
				if vx * float(facing_sign) > 0.0:
					vx = 0.0
					clamped = true

	# ===== Emissão de evento de locomoção =====
	var is_moving: bool = allowed and absf(vx) > epsilon_speed
	if is_moving != _was_moving:
		_was_moving = is_moving
		print("[MOVE_EVT] moving=%s vx=%.2f allowed=%s" % [str(is_moving), vx, str(allowed)])
		movement_changed.emit(is_moving)

	return vx
