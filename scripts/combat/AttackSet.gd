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
	if attacks == null:
		return -1
	var count: int = attacks.size()
	if count <= 0:
		return -1

	assert(current_index >= -1 and current_index < count, "AttackSet.next_index: current_index fora do intervalo.")

	var i: int = current_index + 1
	if i < count:
		return i
	return -1
