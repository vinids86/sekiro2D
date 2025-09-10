extends Node
class_name BufferController

var _has_buffer: bool = false

func has_buffer() -> bool:
	return _has_buffer

func clear() -> void:
	_has_buffer = false

func capture() -> void:
	_has_buffer = true

func can_buffer_now(cc: CombatController) -> bool:
	return cc.get_state_instance_for(cc.get_state()).allows_attack_buffer(cc)
