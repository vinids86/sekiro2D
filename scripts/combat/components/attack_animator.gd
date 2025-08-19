extends Node
class_name AttackAnimator

signal phase_changed(phase: int) # 0=STARTUP,1=ACTIVE,2=RECOVERY,3=DONE
signal active_toggled(is_on: bool)

enum Phase { STARTUP, ACTIVE, RECOVERY, DONE }

@export var sprite: AnimatedSprite2D

var _anims: AttackPhaseAnims
var _durations: PackedFloat32Array = PackedFloat32Array()

var _phase: int = Phase.DONE
var _phase_time: float = 0.0
var _playing: bool = false

# controle por frames com tempo fixo por frame
var _phase_frame_count: int = 0
var _phase_last_index: int = 0
var _per_frame: float = 0.0
var _frame_accum: float = 0.0
var _current_frame: int = 0

func _ready() -> void:
	set_process(false)

func play_attack(anims: AttackPhaseAnims, startup: float, active: float, recovery: float) -> void:
	_anims = anims
	_durations = PackedFloat32Array([
		maxf(startup, 0.0001),
		maxf(active, 0.0001),
		maxf(recovery, 0.0001)
	])

	_phase = Phase.STARTUP
	_phase_time = 0.0
	_playing = true
	set_process(true)

	_set_anim_for_phase(_phase)
	emit_signal("phase_changed", _phase)
	emit_signal("active_toggled", false)

func is_playing() -> bool:
	return _playing

func _process(delta: float) -> void:
	if not _playing:
		return

	_phase_time += delta
	var dur: float = _durations[_phase] if _phase < Phase.DONE else 0.0

	# avanço com tempo igual por frame
	if sprite != null and _phase < Phase.DONE:
		_frame_accum += delta
		while _frame_accum >= _per_frame and _current_frame < _phase_last_index:
			_frame_accum -= _per_frame
			_current_frame += 1
			sprite.frame = _current_frame

	if _phase_time >= dur:
		_advance_phase()

func _advance_phase() -> void:
	if _phase == Phase.STARTUP:
		_phase = Phase.ACTIVE
		_phase_time = 0.0
		_set_anim_for_phase(_phase)
		emit_signal("phase_changed", _phase)
		emit_signal("active_toggled", true)
		return

	if _phase == Phase.ACTIVE:
		_phase = Phase.RECOVERY
		_phase_time = 0.0
		_set_anim_for_phase(_phase)
		emit_signal("phase_changed", _phase)
		emit_signal("active_toggled", false)
		return

	# DONE
	_phase = Phase.DONE
	_phase_time = 0.0
	stop()  # <-- garante speed_scale = 1.0
	emit_signal("phase_changed", _phase)

func _set_anim_for_phase(phase: int) -> void:
	if sprite == null:
		return
	sprite.speed_scale = 0.0
	match phase:
		Phase.STARTUP:
			sprite.animation = _anims.startup_anim
		Phase.ACTIVE:
			sprite.animation = _anims.active_anim
		Phase.RECOVERY:
			sprite.animation = _anims.recovery_anim
	sprite.play()
	_setup_phase(phase)

func _setup_phase(phase: int) -> void:
	if sprite == null:
		return
	var frames: SpriteFrames = sprite.sprite_frames
	var anim: StringName = sprite.animation

	_phase_frame_count = frames.get_frame_count(anim)
	if _phase_frame_count <= 0:
		_phase_frame_count = 1
	_phase_last_index = _phase_frame_count - 1

	_current_frame = 0
	_frame_accum = 0.0

	var dur: float = _durations[phase]
	_per_frame = dur / float(_phase_frame_count)
	if _per_frame <= 0.0:
		_per_frame = 0.0001

	sprite.frame = 0


func stop() -> void:
	_playing = false
	set_process(false)
	if sprite != null:
		sprite.speed_scale = 1.0
