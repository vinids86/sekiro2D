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
		
		# --- LÓGICA DE CONEXÃO CORRIGIDA E FINAL ---

		# 1. Conecta o sinal de impacto do DEFENSOR.
		# Se o defensor for uma IA, ele precisa saber o resultado do golpe que sofreu.
		var defender_ai_driver: EnemyAIDriver = defender_root.get_node_or_null("EnemyAIDriver")
		if defender_ai_driver:
			if not arb.defender_impact.is_connected(defender_ai_driver._on_self_defender_impact):
				arb.defender_impact.connect(defender_ai_driver._on_self_defender_impact)
		
		# 2. Conecta o sinal de feedback do ATACANTE.
		# Se o atacante for uma IA, ele precisa saber se o golpe dele foi aparado.
		var attacker_ai_driver: EnemyAIDriver = attacker_root.get_node_or_null("EnemyAIDriver")
		if attacker_ai_driver:
			if not arb.attacker_impact.is_connected(attacker_ai_driver._on_self_attacker_impact):
				arb.attacker_impact.connect(attacker_ai_driver._on_self_attacker_impact)
			
	return _map[key] as ContactArbiter

func release_for(attacker_root: Node, defender_root: Node) -> void:
	var key: String = _pair_key(attacker_root, defender_root)
	if _map.has(key):
		var arb: ContactArbiter = _map[key] as ContactArbiter
		if is_instance_valid(arb):
			arb.queue_free()
		_map.erase(key)
