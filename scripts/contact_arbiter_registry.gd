extends Node
class_name ContactArbiterRegistry

var _map: Dictionary = {}  # "attackerId:defenderId" -> ContactArbiter

func _ready() -> void:
	add_to_group("contact_registry")

static func _pair_key(a: Node, b: Node) -> String:
	var sa: String = str(a.get_instance_id())
	var sb: String = str(b.get_instance_id())
	return sa + ":" + sb

func get_for(attacker_root: Node2D, defender_root: Node2D) -> ContactArbiter:
	assert(attacker_root != null, "Registry.get_for: attacker_root nulo")
	assert(defender_root != null, "Registry.get_for: defender_root nulo")

	var key: String = _pair_key(attacker_root, defender_root)
	if not _map.has(key):
		var arb: ContactArbiter = ContactArbiter.new()
		arb.name = "Arb_" + key
		add_child(arb)
		arb.setup(attacker_root, defender_root)
		_map[key] = arb
	return _map[key] as ContactArbiter

func release_for(attacker_root: Node, defender_root: Node) -> void:
	var key: String = _pair_key(attacker_root, defender_root)
	if _map.has(key):
		var arb: ContactArbiter = _map[key] as ContactArbiter
		if is_instance_valid(arb):
			arb.queue_free()
		_map.erase(key)
