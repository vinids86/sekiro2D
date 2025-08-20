extends Resource
class_name AttackSet

@export var attacks: Array[AttackConfig] = []
@export var loop: bool = false

func is_empty() -> bool:
	return attacks.is_empty()

func count() -> int:
	return attacks.size()

func get_attack(index: int) -> AttackConfig:
	if index < 0:
		return null
	if index >= attacks.size():
		return null
	return attacks[index]

func next_index(current_index: int) -> int:
	var i: int = current_index + 1
	if i < attacks.size():
		return i
	if loop and attacks.size() > 0:
		return 0
	return -1
