extends RefCounted
class_name ParrySystem

signal success(kind_is_heavy: bool)

var clock: float = 0.0
var did_succeed: bool = false
var last_was_heavy: bool = false

func begin() -> void:
	clock = 0.0
	did_succeed = false
	last_was_heavy = false

func tick(delta: float) -> void:
	clock += delta

func within(window: float) -> bool:
	return clock <= window

func set_success(is_heavy: bool) -> void:
	did_succeed = true
	last_was_heavy = is_heavy
	success.emit(is_heavy)
